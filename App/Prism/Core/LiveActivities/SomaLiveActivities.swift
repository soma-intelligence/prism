//
//  SomaLiveActivities.swift
//  Prism
//

import Foundation
import SomaWidgetKit
import UserNotifications
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Starts, moves and ends Soma's Live Activities: one per kind at a time, a
/// new start of a kind replacing the one running. Elsewhere than iPhone, and
/// when the person turned Live Activities off for Soma, every call does
/// nothing.
@MainActor
final class SomaLiveActivities {
    static let shared = SomaLiveActivities()

    /// Whether Live Activities can show at all on this device.
    var isAvailable: Bool {
        #if canImport(ActivityKit) && os(iOS)
        ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        false
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private var running: [SomaActivityKind: Activity<SomaActivityAttributes>] = [:]
    #endif

    /// Starts the kind's activity, ending any of the same kind first. The
    /// activity leaves the lock screen on its own `stale` after its end, or
    /// after `staleAfter` when it counts up.
    func start(_ kind: SomaActivityKind, _ content: SomaActivityContent, staleAfter: TimeInterval = 3600) {
        #if canImport(ActivityKit) && os(iOS)
        guard isAvailable else { return }
        let previous = running[kind] ?? Activity<SomaActivityAttributes>.activities.first { $0.attributes.kind == kind }
        let stale = (content.end ?? content.start.addingTimeInterval(staleAfter)).addingTimeInterval(60)
        do {
            let activity = try Activity.request(attributes: SomaActivityAttributes(kind: kind),
                                                content: ActivityContent(state: content, staleDate: stale),
                                                pushType: nil)
            running[kind] = activity
        } catch {
            return
        }
        if let previous {
            Task { await previous.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    /// Moves the kind's running activity to `content`.
    func update(_ kind: SomaActivityKind, _ content: SomaActivityContent) {
        #if canImport(ActivityKit) && os(iOS)
        guard let activity = running[kind] else { return }
        Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        #endif
    }

    /// Ends the kind's activity, leaving `final` on the lock screen for a
    /// few minutes when given, else removing it at once.
    func end(_ kind: SomaActivityKind, final content: SomaActivityContent? = nil) {
        #if canImport(ActivityKit) && os(iOS)
        let activities = Activity<SomaActivityAttributes>.activities.filter { $0.attributes.kind == kind }
        running[kind] = nil
        for activity in activities {
            Task {
                if let content {
                    await activity.end(ActivityContent(state: content, staleDate: nil),
                                       dismissalPolicy: .after(Date().addingTimeInterval(5 * 60)))
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }

    /// Whether the kind is showing.
    func isRunning(_ kind: SomaActivityKind) -> Bool {
        #if canImport(ActivityKit) && os(iOS)
        Activity<SomaActivityAttributes>.activities.contains { $0.attributes.kind == kind && $0.activityState == .active }
        #else
        false
        #endif
    }
}

/// The words each activity shows, written here so the extension only lays
/// them out. Pure, so tests pin them.
nonisolated enum SomaActivityCopy {
    /// Wind down to lights out at `lightsOut`, waking at `wake`.
    static func windDown(now: Date, lightsOut: Date, wake: Date?, need: Double?, calendar: Calendar = .current) -> SomaActivityContent {
        var parts: [String] = []
        if let wake { parts.append("Wake at \(ScoreMath.clock(wake, calendar: calendar))") }
        if let need { parts.append("\(SleepTrends.hm(need)) needed") }
        return SomaActivityContent(title: "Lights out at \(ScoreMath.clock(lightsOut, calendar: calendar))",
                                   detail: parts.isEmpty ? "Screens down, lights low" : parts.joined(separator: " · "),
                                   start: now, end: lightsOut)
    }

    /// A nap of `minutes`, from `now`.
    static func nap(now: Date, minutes: Int, calendar: Calendar = .current) -> SomaActivityContent {
        let wake = now.addingTimeInterval(TimeInterval(minutes * 60))
        return SomaActivityContent(title: "Nap", detail: "Wake at \(ScoreMath.clock(wake, calendar: calendar))",
                                   start: now, end: wake, value: "\(minutes) min", valueLabel: "Length")
    }

    /// A meeting that could run tense, counting down to its start.
    static func meeting(title: String, start: Date, now: Date, calendar: Calendar = .current) -> SomaActivityContent {
        SomaActivityContent(title: title, detail: "Starts at \(ScoreMath.clock(start, calendar: calendar)) · a slow breath first",
                            start: now, end: start)
    }

    /// The cardio test at a moment of its run.
    static func cardioTest(name: String, start: Date, metres: Double, heartRate: Double?, slowDown: Bool) -> SomaActivityContent {
        SomaActivityContent(title: name, detail: slowDown ? "Slow down" : nil, start: start,
                            value: "\(Int(metres.rounded())) m", valueLabel: "Distance",
                            secondary: heartRate.map { "\(Int($0.rounded())) bpm" }, alert: slowDown)
    }
}

/// A nap started from Nap Architect: the Live Activity counting down, and a
/// notification with sound at the end to wake to.
@MainActor
enum NapTimer {
    static let wakeID = "nap.wake"

    /// Starts a nap of `minutes`. Returns false when notifications are off,
    /// in which case the activity still counts down but nothing rings.
    @discardableResult
    static func start(minutes: Int, now: Date = Date()) async -> Bool {
        SomaLiveActivities.shared.start(.nap, SomaActivityCopy.nap(now: now, minutes: minutes))
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Time to get up"
        content.body = "Your \(minutes) minute nap is done."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: wakeID, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    /// Ends the nap now: the activity goes and the wake up is cancelled.
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [wakeID])
        SomaLiveActivities.shared.end(.nap)
    }
}
