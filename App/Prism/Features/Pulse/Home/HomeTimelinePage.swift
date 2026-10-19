//
//  HomeTimelinePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The day down a time axis, pushed from Today's day card: last night, the
/// workouts, meals, logs, stress peaks and mindful minutes where they
/// happened, a line on now, and the evening still to come as outlines.
///
/// Every event opens the page behind it: the sleep and stress scores, the
/// sessions, the Vault's mindful minutes, the log it was entered on, the
/// supplement and caffeine tools, and the next move for the evening.
struct HomeTimelinePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var day: HomeDay?

    private var log: HomeLog { .shared }
    private var track: TrackLogStore { .shared }
    private let calendar = Calendar.current

    var body: some View {
        let now = day?.now ?? Date()

        HomePage("Today") {
            SomaPageHero(
                eyebrow: now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                title: "Your day.",
                reason: summary
            )
            .padding(.bottom, theme.metrics.cardSpacing)

            SomaDayTimeline(events, now: now, calendar: calendar)
        }
        .task { day = await HomeDay.load(health: health, log: log) }
    }

    // MARK: - What happened

    private var events: [SomaTimelineEvent] {
        guard let day else { return [] }
        let now = day.now
        let today = calendar.startOfDay(for: now)
        var events: [SomaTimelineEvent] = []

        if let night = day.lastNight {
            events.append(event(
                "sleep", at: night.fellAsleep, until: night.woke, title: "Sleep", aspect: .sleep,
                stats: [stat("bed.double.fill", Self.duration(night.asleep)),
                        stat("sun.horizon.fill", HomeFormat.clock(night.woke))],
                to: ScoreRoute.sleep
            ))
        }
        for workout in day.workouts {
            var stats = [stat("timer", Self.duration(workout.minutes * 60))]
            if let steps = workout.steps, steps > 0 {
                stats.append(stat("shoeprints.fill", HomeFormat.whole(steps)))
            } else if let zone = workout.zoneThreeMinutes, zone > 0 {
                stats.append(stat("bolt.heart.fill", "\(Int(zone.rounded()))m zone 3+"))
            } else if let heart = workout.averageHeartRate {
                stats.append(stat("heart.fill", "\(HomeFormat.whole(heart)) bpm"))
            }
            events.append(event(
                "workout-\(workout.start.timeIntervalSinceReferenceDate)", at: workout.start, until: workout.end,
                title: workout.name, aspect: .activity,
                symbol: workout.kind == .onFoot ? "figure.walk" : "figure.mixed.cardio", stats: stats,
                to: MetricRoute.activitySummary
            ))
        }
        for session in day.inputs.mindful where session.start >= today {
            events.append(event(
                "mindful-\(session.start.timeIntervalSinceReferenceDate)", at: session.start, until: session.end,
                title: "Mindful", aspect: .mind, symbol: "wind",
                stats: [stat("timer", Self.duration(session.end.timeIntervalSince(session.start)))],
                to: Self.mindfulMinutes
            ))
        }
        for peak in day.peaks {
            events.append(event(
                "peak-\(peak.start.timeIntervalSinceReferenceDate)", at: peak.start, until: peak.end,
                title: "Stress peak", aspect: .mind, symbol: "waveform.path.ecg",
                stats: [stat("heart.fill", "\(HomeFormat.whole(peak.peak)) bpm"),
                        stat("arrow.up", "+\(HomeFormat.whole(peak.above))")],
                to: ScoreRoute.stress
            ))
        }
        for meal in track.meals(on: now) {
            events.append(event(
                "meal-\(meal.id)", at: meal.date, title: meal.meal.title, aspect: .gut,
                stats: [stat("flame.fill", "\(HomeFormat.whole(meal.kilocalories)) kcal"),
                        stat("p.circle.fill", "\(HomeFormat.whole(meal.proteinEaten)) g")],
                to: TrackRoute.food
            ))
        }
        for dose in track.doses(on: now) {
            events.append(event(
                "dose-\(dose.id)", at: dose.date, title: dose.name, hue: .symptoms, symbol: "pills.fill",
                stats: [stat("scalemass.fill", "\(HomeFormat.decimal(dose.amount, dose.amount.rounded() == dose.amount ? 0 : 1)) \(dose.unit.symbol)")],
                to: ToolRoute.supplementWindow
            ))
        }
        for drink in track.drinks(on: now) where drink.caffeineMg > 0 {
            events.append(event(
                "drink-\(drink.id)", at: drink.date, title: drink.drink.title, hue: .symptoms, symbol: "cup.and.saucer.fill",
                stats: [stat("bolt.fill", "\(HomeFormat.whole(drink.caffeineMg)) mg")],
                to: ToolRoute.caffeineWindow
            ))
        }
        // Meditation reaches the day through Health's mindful minutes.
        for practice in TrackPractice.allCases where practice != .meditation {
            for entry in track.practices(practice, since: today) {
                events.append(event(
                    "practice-\(entry.id)", at: entry.date, title: practice.title, hue: .symptoms,
                    symbol: practice == .sauna ? "flame.fill" : "snowflake",
                    stats: [stat("timer", Self.duration(entry.minutes * 60))],
                    to: TrackRoute.practice(practice)
                ))
            }
        }
        for mood in track.moods(on: now) where !mood.isDaily {
            events.append(event(
                "mood-\(mood.id)", at: mood.date, title: "Mood", hue: .symptoms, symbol: "face.smiling",
                stats: mood.words.first.map { [stat("text.bubble.fill", $0)] } ?? [],
                to: TrackRoute.moodNow
            ))
        }
        return events + planned
    }

    // MARK: - Still to come

    /// Dinner, the wind down and bed, from the usual bedtime: drawn as outlines.
    private var planned: [SomaTimelineEvent] {
        guard let day, let bed = day.context.habitualBedHour else { return [] }
        let now = day.now
        var events: [SomaTimelineEvent] = []
        if let dinner = clock(bed - 3), dinner > now, !track.meals(on: now).contains(where: { $0.meal == .dinner }) {
            events.append(event("dinner", at: dinner, title: "Dinner", aspect: .gut, planned: true,
                                stats: [stat("clock", "By \(HomeFormat.clock(dinner))")], to: HomeRoute.nextMove))
        }
        // A bedtime after midnight belongs to tomorrow's date.
        guard let bedDate = clock(bed, dayOffset: bed < 12 ? 1 : 0) else { return events }
        if let wind = calendar.date(byAdding: .minute, value: -30, to: bedDate), wind > now {
            events.append(event("wind", at: wind, title: "Wind down", aspect: .mind, symbol: "moon.haze.fill", planned: true,
                                to: HomeRoute.nextMove))
        }
        if bedDate > now {
            let wake = day.context.sleepNeedSeconds.map { bedDate.addingTimeInterval($0) }
            events.append(event(
                "bed", at: bedDate, title: "In bed", aspect: .sleep, symbol: "bed.double.fill", planned: true,
                stats: wake.map { [stat("alarm.fill", "Up \(HomeFormat.clock($0))")] } ?? [],
                to: HomeRoute.nextMove
            ))
        }
        return events
    }

    /// A decimal hour today, or on a later day with `dayOffset`.
    private func clock(_ hour: Double, dayOffset: Int = 0) -> Date? {
        let base = calendar.startOfDay(for: day?.now ?? Date())
        let normal = (hour + 24).truncatingRemainder(dividingBy: 24)
        return calendar.date(byAdding: .minute, value: Int((normal * 60).rounded()) + dayOffset * 24 * 60, to: base)
    }

    // MARK: - Parts

    private func event(
        _ id: String,
        at start: Date,
        until end: Date? = nil,
        title: String,
        aspect: SomaAspect? = nil,
        hue: SomaHealthHue? = nil,
        symbol: String? = nil,
        planned: Bool = false,
        stats: [SomaTimelineStat] = [],
        to destination: (any Hashable & Sendable)? = nil
    ) -> SomaTimelineEvent {
        SomaTimelineEvent(
            id: id, time: HomeFormat.clock(start), title: title, aspect: aspect, hue: hue,
            symbol: symbol, stats: stats, start: start, end: end, isPlanned: planned,
            destination: destination
        )
    }

    /// The Vault's page of mindful minutes, where a session's record sits.
    private static var mindfulMinutes: VaultRoute? {
        HealthMetricCatalog.metric(for: "HKCategoryTypeIdentifierMindfulSession").map { VaultRoute.dataType(BodyDataType($0)) }
    }

    private func stat(_ symbol: String, _ text: String) -> SomaTimelineStat {
        SomaTimelineStat(symbol: symbol, text: text)
    }

    /// A duration the way a stats line prints it: "7h 12m", "42m".
    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private var summary: String? {
        guard let day else { return nil }
        var parts: [String] = []
        if let night = day.lastNight { parts.append("Slept \(HomeFormat.hoursMinutes(night.asleep))") }
        if let exercise = day.inputs.exerciseToday, exercise > 0 { parts.append("moved \(HomeFormat.span(exercise * 60))") }
        let meals = track.meals(on: day.now).count
        if meals > 0 { parts.append(meals == 1 ? "one meal" : "\(meals) meals") }
        guard !parts.isEmpty else { return "Nothing recorded yet today." }
        return parts.joined(separator: ", ") + "."
    }
}
