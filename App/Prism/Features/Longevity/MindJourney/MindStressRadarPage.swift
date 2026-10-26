//
//  MindStressRadarPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Stress Radar, today: the episodes of medium stress or higher, each tied to
/// the calendar event it overlapped, the day as a timeline, where stress
/// rises over the last thirty days, and the scale it is read on.
///
/// The radar runs over the half-hour curve of heart rate above
/// resting; sleep and workouts are left out of it.
struct MindStressRadarPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?
    @State private var curves: [MindStressDayCurve]?
    @State private var events: [MindCalendarEvent] = []
    @State private var isBreathing = false

    var body: some View {
        let calendar = Calendar.current
        let words = PulseWording(calendar: calendar, locale: .current)
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let todayCurve = curves?.last.flatMap { calendar.isDate($0.day, inSameDayAs: now) ? $0 : nil }
        let past = (curves ?? []).filter { $0.day < todayStart }
        let todayEvents = events.filter { $0.start >= todayStart }
        let reading = todayCurve.flatMap { MindStressRadar.reading($0, events: todayEvents) }
        let usual = MindStressRadar.usual(past)
        let rises = rises(past: past, calendar: calendar)
        let episodes = reading?.episodes ?? []

        MindPage(
            navigationTitle: "Stress Radar",
            title: headline(episodes),
            stats: [
                SomaStat("Day peak", value: MindFormat.whole(reading?.peak), trend: (reading?.peak ?? 0) >= MindStressRadar.elevated ? .up : nil),
                SomaStat("Elevated", value: reading.map { MindFormat.duration(Double($0.elevatedMinutes)) }),
                SomaStat("Episodes", value: reading.map { "\($0.episodes.count)" }),
            ]
        ) {
            SomaChartCard(
                eyebrow: "Today",
                value: now.formatted(date: .omitted, time: .shortened),
                unit: "now",
                note: timelineNote(inputs, episodes: episodes, calendar: calendar, words: words)
            ) {
                MindDayTimeline(
                    nights: PulseNights.nights(from: inputs?.sleep ?? [], calendar: calendar),
                    workouts: inputs?.workouts ?? [],
                    meals: todayEvents.filter { MindEventClassifier.category(title: $0.title) == .food },
                    curve: todayCurve,
                    now: now
                )
                .frame(height: theme.metrics.aspectChartHeight * 2.6)
            }

            if !rises.isEmpty {
                MindRowsCard(title: "Where it rises", caption: "Average stress, last 30 days", rows: rises) { MindSignalRowView(row: $0) }
            }

            MindBandScale(usual: usual)

            if let worst = reading?.worst {
                SomaActionCard(
                    eyebrow: "Before the next one",
                    title: worst.trigger.map { "Pause before \($0)" } ?? "Take a pause",
                    detail: "Today’s highest stretch began at \(words.time(todayCurve?.date(ofBucket: worst.startBucket) ?? now)). Three slow minutes before it lands keep the peak lower.",
                    actionTitle: "Breathe",
                    action: { isBreathing = true }
                ) {
                    SomaObjectIcon(aspect: .mind, size: .row)
                }
            }
        }
        .task {
            _ = await MindCalendar.requestAccess()
            let start = calendar.date(byAdding: .day, value: -30, to: todayStart) ?? todayStart
            events = await MindCalendar.events(from: start, to: now.addingTimeInterval(24 * 60 * 60))
            let read = await MindLoad.inputs(health)
            inputs = read
            curves = await MindJourneyLoad.curves(health, inputs: read, days: 30)
        }
        .sheet(isPresented: $isBreathing) { MindBreatheSession(length: 3 * 60) }
    }

    private func headline(_ episodes: [MindStressRadar.Episode]) -> String {
        guard curves != nil else { return "Stress Radar" }
        let triggered = episodes.filter { $0.trigger != nil }.count
        switch episodes.count {
        case 0: return "No stress episode today."
        case 1: return triggered == 1 ? "One peak, in a meeting." : "One peak today."
        default:
            if triggered == episodes.count { return "\(episodes.count) peaks, all in meetings." }
            return "\(episodes.count) peaks today."
        }
    }

    private func timelineNote(_ inputs: MindInputs?, episodes: [MindStressRadar.Episode], calendar: Calendar, words: PulseWording) -> String {
        let night = PulseNights.nights(from: inputs?.sleep ?? [], calendar: calendar).last { calendar.isDateInToday($0.day) }
        var parts: [String] = []
        if let night { parts.append("Slept \(words.clock(night.asleep))") }
        let moves = (inputs?.workouts ?? []).filter { calendar.isDateInToday($0.start) }.count
        if moves > 0 { parts.append("moved \(words.count(moves, "time", "times"))") }
        parts.append(words.count(episodes.count, "stress episode", "stress episodes"))
        let text = words.list(parts)
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    /// Mean stress inside each kind of calendar moment, and outside them.
    private func rises(past: [MindStressDayCurve], calendar: Calendar) -> [MindSignalRow] {
        var inside: [MindEventCategory: [Double]] = [:]
        var outside: [Double] = []
        for curve in past {
            let dayEvents = events.filter { calendar.isDate($0.start, inSameDayAs: curve.day) }
            var covered = Set<Int>()
            for event in dayEvents {
                let category = MindStore.shared.category(of: event.title)
                for bucket in curve.buckets(from: event.start, to: event.end) {
                    covered.insert(bucket)
                    if let value = curve.value(bucket) { inside[category, default: []].append(value) }
                }
            }
            for bucket in 0..<MindStressDayCurve.buckets where !covered.contains(bucket) {
                if let value = curve.value(bucket) { outside.append(value) }
            }
        }
        var rows: [(String, String, Double)] = inside.compactMap { category, values in
            guard values.count >= 4, let mean = MindUsual.mean(values) else { return nil }
            return (category == .meeting ? "In meetings" : category.title, "from your calendar", mean)
        }
        if let mean = MindUsual.mean(outside), outside.count >= 4, !rows.isEmpty {
            rows.append(("Outside the calendar", "the rest of your awake day", mean))
        }
        return rows.sorted { $0.2 > $1.2 }.map { title, detail, mean in
            MindSignalRow(kind: .peaks, title: title, detail: detail, value: "\(Int(mean.rounded()))", isCost: mean >= MindStressRadar.elevated, number: mean, usual: nil)
        }
    }
}

/// The 0 to 100 scale in its four bands, and where the usual day sits.
struct MindBandScale: View {
    let usual: Double?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color

        SomaCard {
            VStack(alignment: .leading, spacing: 12) {
                MindEyebrow(text: "Reference scale")
                HStack(alignment: .top, spacing: 4) {
                    ForEach(MindStressBand.allCases, id: \.self) { band in
                        VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
                            Capsule()
                                .fill(band == .high ? colors.danger.color : hue.opacity(0.35 + 0.25 * Double(band.rawValue)))
                                .frame(height: theme.metrics.chartTrackHeight * 1.5)
                            Text(band.title).somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                            Text("\(band.range.lowerBound) to \(band.range.upperBound)")
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(usual.map { "Your usual day sits in \(MindStressBand($0).title.localizedLowercase)." } ?? "Your usual day shows once a few days are read.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
    }
}

/// Today from midnight to midnight: sleep, workouts, meals and stress
/// episodes on four rows, and a line at now.
struct MindDayTimeline: View {
    let nights: [PulseNight]
    let workouts: [HealthReading]
    let meals: [MindCalendarEvent]
    let curve: MindStressDayCurve?
    let now: Date

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let type = theme.typography
        let hue = theme.aspects[.mind].identity.color
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let rows = ["Sleep", "Move", "Meals", "Stress"]
        let labelWidth = theme.metrics.aspectChartWidth * 0.55

        VStack(spacing: theme.metrics.spaceS) {
            GeometryReader { proxy in
                let width = proxy.size.width - labelWidth
                let rowHeight = proxy.size.height / CGFloat(rows.count)
                let mark = theme.metrics.chartTrackHeight * 2.5
                let x: (Date) -> CGFloat = { date in labelWidth + width * CGFloat(min(max(date.timeIntervalSince(day) / 86_400, 0), 1)) }
                let block: (Date, Date, Int, Color) -> AnyView = { start, end, row, fill in
                    let from = x(start)
                    let to = max(x(end), from + mark)
                    return AnyView(Capsule().fill(fill)
                        .frame(width: to - from, height: mark)
                        .position(x: (from + to) / 2, y: rowHeight * (CGFloat(row) + 0.5)))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, title in
                        Text(title)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .position(x: labelWidth / 2, y: rowHeight * (CGFloat(index) + 0.5))
                    }
                    ForEach(Array(nights.filter { $0.woke > day }.enumerated()), id: \.offset) { _, night in
                        block(night.fellAsleep, night.woke, 0, theme.aspects[.sleep].identity.color)
                    }
                    ForEach(Array(workouts.filter { $0.end > day }.enumerated()), id: \.offset) { _, workout in
                        block(workout.start, workout.end, 1, theme.aspects[.activity].identity.color)
                    }
                    ForEach(meals) { meal in
                        block(meal.start, meal.start, 2, colors.inkSecondary.color)
                    }
                    if let curve, let reading = MindStressRadar.reading(curve, events: []) {
                        ForEach(reading.episodes) { episode in
                            block(curve.date(ofBucket: episode.startBucket), curve.date(ofBucket: episode.endBucket), 3, hue)
                        }
                    }
                    Rectangle()
                        .fill(colors.accent.color)
                        .frame(width: 1, height: proxy.size.height)
                        .position(x: x(now), y: proxy.size.height / 2)
                }
            }
            HStack {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                    if hour < 24 { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Today’s timeline")
        .accessibilityValue("Sleep, movement, meals and stress episodes from midnight to now")
    }
}
