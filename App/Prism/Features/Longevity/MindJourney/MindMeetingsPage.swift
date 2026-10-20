//
//  MindMeetingsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Meeting stress: today's meetings against the usual, stress through the
/// workday, mornings against afternoons over the last thirty days, and the
/// recurring meetings that line up with a rise.
///
/// Meetings come from the calendar, asked for when the page opens and only
/// when the consent allowed it; stress is the half-hour curve of heart rate
/// above resting (`MindStressCurve`). A correlation, never a cause.
struct MindMeetingsPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var access: MindCalendar.Access = .notAsked
    @State private var curves: [MindStressDayCurve]?
    @State private var events: [MindCalendarEvent] = []
    @State private var tomorrow: [MindCalendarEvent] = []
    @State private var isBreathing = false
    /// The calendar's lines against stress, worked out on the phone.
    @State private var insights: [MindCalendarInsights.Insight]?

    static let historyDays = 30

    var body: some View {
        let calendar = Calendar.current
        let words = PulseWording(calendar: calendar, locale: .current)
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let todayCurve = curves?.last.flatMap { calendar.isDate($0.day, inSameDayAs: now) ? $0 : nil }
        let past = (curves ?? []).filter { $0.day < todayStart }
        let usual = MindStressRadar.usualRange(past)
        let todayEvents = events.filter { $0.start >= todayStart }
        let today = MindMeetingStress.today(todayCurve, events: todayEvents)
        let halves = MindMeetingStress.halves(days: past, events: events, calendar: calendar)
        let series = MindMeetingStress.series(days: curves ?? [], events: events, calendar: calendar)
        let raised = today.raised(over: usual)
        let lateCalls = MindMeetingStress.meetings(in: tomorrow).filter { calendar.component(.hour, from: $0.start) >= 14 }

        MindPage(
            navigationTitle: "Meetings",
            title: headline(today: today, raised: raised),
            stats: [
                SomaStat("Meetings", value: access == .granted ? "\(today.meetings.count)" : nil),
                SomaStat("In meetings", value: access == .granted ? MindFormat.duration(today.minutes) : nil),
                SomaStat("Peak", value: MindFormat.whole(today.peak?.peak), trend: (today.peak?.peak ?? 0) > (usual?.upperBound ?? .infinity) ? .up : nil),
            ]
        ) {
            if access != .granted {
                MindCalendarAccessCard(access: access) {
                    Task { await load(asking: true) }
                }
            } else {
                MindCalendarCard(state: MindCalendarState(access: access, insights: insights))
            }

            SomaChartCard(
                eyebrow: "Stress through the workday",
                value: MindFormat.whole(today.peak?.peak),
                unit: today.peak.map { "peak, at \(words.time($0.event.start))" },
                note: todayCurve?.usableCount ?? 0 < MindStressRadar.minimumCovered
                    ? "The line fills from your watch’s heart rate while you sit still. Workouts and sleep are left out."
                    : "Grey blocks are meetings; the band is your usual, the middle half of the last thirty days."
            ) {
                MindWorkdayChart(curve: todayCurve, meetings: today.meetings, usual: usual)
            }

            if !today.meetings.isEmpty {
                MindRowsCard(
                    title: "Each meeting",
                    caption: usual.map { "Peak against your usual \(Int($0.lowerBound.rounded())) to \(Int($0.upperBound.rounded()))" } ?? "Peak stress in each",
                    rows: today.meetings
                ) { meeting in
                    MindSignalRowView(row: MindSignalRow(
                        kind: .peaks,
                        title: "\(meeting.event.title), \(words.time(meeting.event.start))",
                        detail: MindFormat.duration(meeting.event.minutes),
                        value: meeting.peak.map { "peak \(Int($0.rounded()))" },
                        isCost: (meeting.peak ?? 0) > (usual?.upperBound ?? .infinity),
                        number: meeting.peak,
                        usual: usual
                    ))
                }
            }

            if halves.meetings > 0 {
                MindHalvesCard(halves: halves)
            }

            if !series.isEmpty {
                MindRowsCard(title: "Recurring meetings", caption: "Against the same hour on days without", rows: Array(series.prefix(5))) { item in
                    MindSignalRowView(row: MindSignalRow(
                        kind: .peaks,
                        title: item.title,
                        detail: "\(item.scored) of \(item.found) times read",
                        value: item.isDirectional ? MindMath.signed(item.delta) : "unclear",
                        isCost: item.isDirectional && item.delta > 0,
                        number: nil, usual: nil
                    ))
                }
            }

            if !lateCalls.isEmpty {
                SomaActionCard(
                    eyebrow: "Tomorrow · \(lateCalls.count) after 14:00",
                    title: "Breathe for 3 minutes before each",
                    detail: "Slow breathing before a call helps your heart come back down after it.",
                    actionTitle: "Try now",
                    action: { isBreathing = true }
                ) {
                    SomaOrb(aspect: .mind, scale: .mini)
                }
            }
        }
        .task { await load(asking: true) }
        .refreshable { await load(asking: false) }
        .sheet(isPresented: $isBreathing) { MindBreatheSession(length: 3 * 60) }
    }

    private func headline(today: MindMeetingStress.Today, raised: [MindMeetingStress.Meeting]) -> String {
        guard access == .granted else { return "Meetings and your stress." }
        if today.meetings.isEmpty { return "No meetings today." }
        switch raised.count {
        case 0: return "Your meetings stayed in range."
        case 1: return "One meeting raised your stress."
        default: return "\(raised.count) meetings raised your stress."
        }
    }

    private func load(asking: Bool) async {
        access = asking ? await MindCalendar.requestAccess() : MindCalendar.access
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -Self.historyDays, to: calendar.startOfDay(for: now)) ?? now
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        events = await MindCalendar.events(from: start, to: tomorrowStart)
        tomorrow = await MindCalendar.events(from: tomorrowStart, to: tomorrowStart.addingTimeInterval(24 * 60 * 60))
        let inputs = await MindLoad.inputs(health)
        curves = await MindJourneyLoad.curves(health, inputs: inputs, days: Self.historyDays)
        insights = MindCalendarInsights.lines(curves: curves ?? [], events: events, hrv: inputs.heartRateVariability,
                                              now: now, calendar: calendar)
    }
}

/// The calendar is off, not asked or refused: says which, and what to do.
struct MindCalendarAccessCard: View {
    let access: MindCalendar.Access
    let ask: () -> Void

    var body: some View {
        switch access {
        case .off:
            MindTextCard(title: "Calendar off", text: "Turn on in Mind’s choices.")
        case .denied:
            MindTextCard(title: "No calendar access", text: "Settings, Privacy, Calendars.")
        case .notAsked:
            SomaActionCard(eyebrow: "Calendar", title: "Read your busy times", detail: "Only each event’s time and title.", actionTitle: "Allow", action: ask) {
                SomaOrb(aspect: .mind, scale: .mini)
            }
        case .granted:
            EmptyView()
        }
    }
}

/// Mornings against afternoons: the average peak of each.
struct MindHalvesCard: View {
    let halves: MindMeetingStress.Halves

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color
        let highest = max(halves.morning ?? 0, halves.afternoon ?? 0, 1)
        let worse = (halves.afternoon ?? 0) > (halves.morning ?? 0)

        SomaCard {
            VStack(alignment: .leading, spacing: 14) {
                SomaCardHeader("Mornings against afternoons", caption: "Last 30 days · \(halves.meetings) meetings")
                bar("Before 12:00", halves.morning, fill: hue, isCost: !worse && halves.morning != nil && halves.afternoon != nil, highest: highest)
                bar("After 14:00", halves.afternoon, fill: worse ? colors.danger.color : hue, isCost: worse, highest: highest)
                if let morning = halves.morning, let afternoon = halves.afternoon, morning > 0 {
                    let ratio = afternoon / morning
                    MindReasonText(text: ratio >= 1.2
                        ? "Afternoon meetings raise your stress more. Their peaks run \(Int(((ratio - 1) * 100).rounded()))% higher."
                        : ratio <= 0.83 ? "Morning meetings raise your stress more." : "Mornings and afternoons land about the same.")
                }
            }
        }
    }

    private func bar(_ title: String, _ value: Double?, fill: Color, isCost: Bool, highest: Double) -> some View {
        let type = theme.typography
        let colors = theme.colors
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                Spacer()
                Text(value.map { "average peak \(Int($0.rounded()))" } ?? "-")
                    .somaFont(type.rowValue)
                    .foregroundStyle(isCost ? colors.danger.color : colors.inkPrimary.color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.surfaceRecessed.color)
                    if let value {
                        Capsule().fill(fill).frame(width: proxy.size.width * CGFloat(value / 100))
                    }
                }
            }
            .frame(height: theme.metrics.chartTrackHeight)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stress from 08:00 to 18:00: the line, the usual band in faint green, and
/// the meetings as faint grey blocks behind them.
struct MindWorkdayChart: View {
    let curve: MindStressDayCurve?
    let meetings: [MindMeetingStress.Meeting]
    let usual: ClosedRange<Double>?
    var fromHour = 8
    var toHour = 18

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.mind].identity.color
        let calendar = Calendar.current
        let curve = curve
        let meetings = meetings
        let usual = usual
        let first = fromHour * 2
        let last = toHour * 2

        SomaPlot(scale: SomaPlotScale(fixed: 0...100),
                 xLabels: stride(from: fromHour, through: toHour, by: 2).map { String(format: "%02d", $0) }) { context, space, pen in
            func x(_ bucket: Double) -> CGFloat { space.x(fraction: (bucket - Double(first)) / Double(last - first)) }
            if let curve {
                for meeting in meetings {
                    let range = curve.buckets(from: meeting.event.start, to: meeting.event.end)
                    let x0 = x(Double(range.lowerBound))
                    let rect = CGRect(x: x0, y: space.plot.minY, width: max(x(Double(range.upperBound)) - x0, 2), height: space.plot.height)
                    context.fill(Path(rect), with: .color(pen.grid))
                }
            }
            if let usual {
                pen.band(context, top: space.y(usual.upperBound), bottom: space.y(usual.lowerBound), in: space.plot)
            }
            guard let curve else { return }
            let points: [CGPoint?] = (first..<last).map { bucket in
                curve.value(bucket).map { CGPoint(x: x(Double(bucket) + 0.5), y: space.y($0)) }
            }
            pen.line(context, points, color: hue)
            if let end = points.compactMap({ $0 }).last { pen.ring(context, at: end, color: hue) }
        }
        .accessibilityElement()
        .accessibilityLabel("Stress through the workday")
        .accessibilityValue(meetings.isEmpty ? "No meetings" : "\(meetings.count) meetings, \(calendar.component(.hour, from: Date())) o’clock now")
    }
}
