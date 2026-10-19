//
//  ToolAlarmScheduler.swift
//  Prism
//

import Foundation
import SwiftUI
#if canImport(AlarmKit) && os(iOS)
import AlarmKit
#endif

/// Sets the Smart Alarm's ring.
///
/// On iOS the real alarm is AlarmKit's: it breaks through
/// silent mode and Focus. AlarmKit refuses an app whose Info.plist carries no
/// `NSAlarmKitUsageDescription`, and this target does not carry one yet, so the
/// scheduler checks for the key first and, without it (or on a Mac, or when the
/// person says no), falls back to a local notification at the same moment. A
/// notification does not break through silent mode, and the page says which of
/// the two is set.
enum ToolAlarmScheduler {
    enum Kind: Equatable {
        case alarm
        case notification
        case none
    }

    /// Whether this build may use AlarmKit at all.
    static var alarmKitAllowed: Bool {
        #if canImport(AlarmKit) && os(iOS)
        return Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") != nil
        #else
        return false
        #endif
    }

    private static let idKey = "tools.smartAlarm.id"

    private static var alarmID: UUID {
        if let raw = UserDefaults.standard.string(forKey: idKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: idKey)
        return id
    }

    /// Sets one ring at `date`, replacing any earlier one. Returns what was set.
    static func set(_ date: Date, tint: Color) async -> Kind {
        #if canImport(AlarmKit) && os(iOS)
        if alarmKitAllowed, await scheduleAlarm(date, tint: tint) { return .alarm }
        #endif
        let set = await ToolNotifier.remind(id: "smart-alarm", title: "Time to get up",
                                            body: "Your Smart Alarm, inside the window you chose.", at: date)
        return set ? .notification : .none
    }

    static func cancel() {
        #if canImport(AlarmKit) && os(iOS)
        if alarmKitAllowed { try? AlarmManager.shared.cancel(id: alarmID) }
        #endif
        ToolNotifier.cancel(id: "smart-alarm")
    }

    #if canImport(AlarmKit) && os(iOS)
    struct Metadata: AlarmMetadata {}

    private static func scheduleAlarm(_ date: Date, tint: Color) async -> Bool {
        let manager = AlarmManager.shared
        var state = manager.authorizationState
        if state == .notDetermined {
            state = (try? await manager.requestAuthorization()) ?? .denied
        }
        guard state == .authorized else { return false }
        let alert = AlarmPresentation.Alert(title: "Time to get up")
        let attributes = AlarmAttributes<Metadata>(presentation: AlarmPresentation(alert: alert), tintColor: tint)
        let configuration = AlarmManager.AlarmConfiguration<Metadata>(schedule: .fixed(date), attributes: attributes)
        do {
            _ = try await manager.schedule(id: alarmID, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
    #endif
}
