//
//  PhoneMotion.swift
//  Prism
//

import Foundation
import Observation

/// The iPhone's own read of the day: steps, distance, floors and what the
/// person is doing, from Core Motion, so a day without a watch still counts.
///
/// Owned by `HealthDashboard`, which asks for it alongside Apple Health (one
/// question, one moment; see `HealthAccess`) and merges its counts with
/// Health's. Nothing here asks on its own: until the question has an answer
/// every read returns nothing, because a read of the step counter is itself
/// what puts the question.
@MainActor
@Observable
final class PhoneMotion {
    private(set) var authorization: MotionAuthorization
    /// Today since midnight, kept live while the app runs. Nil until read.
    private(set) var today: PedometerDay?
    /// The six days before today and today, oldest first. A day the phone
    /// holds nothing for is absent rather than zero.
    private(set) var week: [PedometerDay] = []
    /// Today's activity changes as Core Motion reported them.
    private(set) var samples: [MotionActivitySample] = []
    /// Today's activity as segments with a start and an end. See
    /// `MotionSegmenter` for how the raw changes become these.
    private(set) var timeline: [MotionSegment] = []
    /// What the person is doing right now, when the phone is sure.
    private(set) var current: MotionActivityKind?

    private let source: any PhoneMotionSource
    private let calendar: Calendar
    private let clock: @Sendable () -> Date

    private var liveTasks: [Task<Void, Never>] = []
    /// The midnight the live stream counts from, so a new day restarts it.
    private var liveFrom: Date?

    init(
        source: any PhoneMotionSource = UnavailableMotionSource(),
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.calendar = calendar
        self.clock = clock
        authorization = source.isAvailable ? source.authorization : .unavailable
    }

    var isAvailable: Bool { source.isAvailable }

    /// The segments that are movement, without the stillness between them:
    /// what a day's timeline draws as events.
    var movingSegments: [MotionSegment] { timeline.filter { $0.kind != .stationary } }

    /// Puts the Motion & Fitness question, if it has no answer yet. Called
    /// from `HealthAccess.requestEverything`, right after Health's sheet.
    func requestAccess() async {
        guard source.isAvailable else { return }
        if source.authorization == .notDetermined {
            await source.requestAccess()
        }
        authorization = source.authorization
    }

    /// Reads today, the week and today's activity, then keeps today live.
    func refresh() async {
        // Each property is written only when it changed: every page that
        // shows steps reads these, and an unchanged write still redraws it.
        let access = source.isAvailable ? source.authorization : .unavailable
        if access != authorization { authorization = access }
        guard authorization == .authorized else { return }

        let now = clock()
        let midnight = calendar.startOfDay(for: now)

        let day = (try? await source.pedometer(from: midnight, to: now)) ?? today
        if day != today { today = day }
        let days = await readWeek(midnight: midnight, now: now)
        if days != week { week = days }
        let read = (try? await source.activities(from: midnight, to: now)) ?? []
        if read != samples { samples = read }
        retime(now: now)

        startLive(from: midnight)
    }

    /// What the phone counted between two moments: the cardio fitness test
    /// polls this for its distance. A query rather than a second live stream,
    /// because Core Motion's step counter keeps one live handler and the day's
    /// count already holds it. Nil until Motion & Fitness is allowed: this is
    /// never the read that puts the question.
    func counted(from start: Date, to end: Date) async -> PedometerDay? {
        guard source.isAvailable, source.authorization == .authorized else { return nil }
        return try? await source.pedometer(from: start, to: end)
    }

    /// Stops the live streams. They also end with the app.
    func stopLive() {
        liveTasks.forEach { $0.cancel() }
        liveTasks = []
        liveFrom = nil
    }

    // MARK: - Reading

    private func readWeek(midnight: Date, now: Date) async -> [PedometerDay] {
        var days: [PedometerDay] = []
        for offset in (0...6).reversed() {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: midnight),
                  let next = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            if let day = try? await source.pedometer(from: start, to: min(next, now)) {
                days.append(day)
            }
        }
        return days
    }

    private func retime(now: Date) {
        let segments = MotionSegmenter.segments(from: samples, until: now)
        if segments != timeline { timeline = segments }
        if let last = samples.last(where: { $0.confidence >= .medium }), last.kind != current {
            current = last.kind
        }
    }

    private func startLive(from midnight: Date) {
        guard liveFrom != midnight else { return }
        stopLive()
        liveFrom = midnight

        let pedometer = source.pedometerUpdates(from: midnight)
        liveTasks.append(Task { [weak self] in
            for await day in pedometer {
                guard let self, !Task.isCancelled else { return }
                self.today = day
                self.replaceToday(in: day)
            }
        })

        let activity = source.activityUpdates()
        liveTasks.append(Task { [weak self] in
            for await sample in activity {
                guard let self, !Task.isCancelled else { return }
                guard sample.start >= midnight else { continue }
                self.samples.append(sample)
                self.retime(now: self.clock())
            }
        })
    }

    /// Keeps the week's last day in step with the live count.
    private func replaceToday(in day: PedometerDay) {
        guard let midnight = liveFrom else { return }
        if let last = week.last, calendar.isDate(last.start, inSameDayAs: midnight) {
            week[week.count - 1] = day
        } else {
            week.append(day)
        }
    }

    // MARK: - Launch

    /// The source a launch reads from: Core Motion on an iPhone, the sample
    /// week in the Simulator (it has no motion hardware), and nothing on a
    /// Mac, a headset, or a launch with `-health.empty YES`, which must never
    /// ask anything.
    static func launchSource(defaults: UserDefaults = .standard) -> any PhoneMotionSource {
        if defaults.bool(forKey: HealthDashboard.emptyLaunchKey) { return UnavailableMotionSource() }
        #if targetEnvironment(simulator)
        return PhoneMotionFixtureSource.sampleWeek()
        #elseif canImport(CoreMotion) && os(iOS)
        return CoreMotionSource()
        #else
        return UnavailableMotionSource()
        #endif
    }
}
