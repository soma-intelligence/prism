//
//  MindMeetingsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Meeting stress: a verdict on the week's meetings and the three numbers
/// behind it, the meetings ahead with a forecast for each, the meetings gone
/// by grouped under their day, stress through today's workday, mornings
/// against afternoons, the people and series that lean toward stress, and the
/// recurring meetings that line up with a rise.
///
/// Meetings come from every calendar source (`MeetingCalendar`), asked for
/// when the page opens and only when the consent allowed it. Each meeting is
/// read against the hour before it, with the walking set aside
/// (`MeetingStressAnalysis`); the workday chart is the half-hour curve of
/// heart rate above resting (`MindStressCurve`). A correlation, never a
/// cause: the page says a meeting ran above the usual, never that a person
/// raised it. Every sentence and name on it comes from `MeetingDisplay`.
struct MindMeetingsPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var access: MindCalendar.Access = .notAsked
    @State private var curves: [MindStressDayCurve]?
    @State private var events: [MindCalendarEvent] = []
    @State private var upcoming: [MindCalendarEvent] = []
    @State private var assessments: [MeetingStressAnalysis.Assessment] = []
    @State private var isBreathing = false
    /// The calendar's lines against stress, worked out on the phone.
    @State private var insights: [MindCalendarInsights.Insight]?

    static let historyDays = 30
    static let upcomingShown = 6
    static let recentShown = 8

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
        // Only the series that lean one way: an unclear one has nothing to say.
        let series = MindMeetingStress.series(days: curves ?? [], events: events, calendar: calendar).filter(\.isDirectional)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let lateCalls = MindMeetingStress.meetings(in: upcoming).filter {
            calendar.isDate($0.start, inSameDayAs: tomorrowStart) && calendar.component(.hour, from: $0.start) >= 14
        }
        let history = MeetingStressAnalysis.history(assessments, calendar: calendar)
        let forecasts = MeetingStressAnalysis.forecasts(upcoming, history: history, now: now, calendar: calendar)
        let nextTense = forecasts.first { $0.level == .likely }
        let recent = Array(assessments.filter { $0.event.end <= now }.reversed().prefix(Self.recentShown))
        let raisers = Array(history.raisers.prefix(5))
        let summary = MeetingDisplay.summary(assessments, now: now, calendar: calendar)
        let granted = access == .granted

        // The head is drawn here rather than by the scaffold: this page keeps
        // its one line of reason under the verdict, which the shared hero
        // leaves out (owner, 2026-10-24).
        MindPage(navigationTitle: String(localized: "Meetings")) {
            MeetingHeader(
                title: granted ? MeetingDisplay.headline(summary) : "Meetings and your stress.",
                reason: granted ? MeetingDisplay.reason(summary) : nil,
                stats: [
                    SomaStat("Meetings read", value: granted && summary.read > 0 ? "\(summary.read)" : nil),
                    SomaStat("Ran tense", value: summary.share.map { "\(Int(($0 * 100).rounded()))%" }),
                    SomaStat("Heart rise", value: summary.meanRise.map(MindMath.signed), unit: "bpm"),
                ]
            )
            .somaColumnSpan(.full)

            if !granted {
                MindCalendarAccessCard(access: access) {
                    Task { await load(asking: true) }
                }
            } else {
                MindCalendarCard(state: MindCalendarState(access: access, insights: insights))
            }

            if !forecasts.isEmpty {
                MeetingUpcomingCard(forecasts: Array(forecasts.prefix(Self.upcomingShown)), now: now, words: words, calendar: calendar)
            }

            if let nextTense {
                SomaActionCard(
                    eyebrow: "Prepare · \(when(nextTense.event.start, words: words, calendar: calendar))",
                    title: "Breathe for 3 minutes before \(MeetingDisplay.title(nextTense.event.title, attendees: nextTense.event.attendees))",
                    detail: MeetingDisplay.namingPeople(in: nextTense.reason),
                    actionTitle: "Try now",
                    action: { isBreathing = true }
                ) {
                    SomaOrb(aspect: .mind, scale: .mini)
                }
            } else if !lateCalls.isEmpty {
                SomaActionCard(
                    eyebrow: "Tomorrow · \(lateCalls.count) after 14:00",
                    title: "Breathe for 3 minutes before each",
                    detail: "Slow breathing before a call helps your heart come back down after it.",
                    actionTitle: "Try now",
                    action: { isBreathing = true }
                ) {
                    SomaObjectIcon(aspect: .mind, size: .row)
                }
            }

            if !recent.isEmpty {
                MeetingLatelyCard(assessments: recent, now: now, words: words, calendar: calendar)
            }

            // Only on a day with meetings: an empty workday says nothing.
            if granted, !today.meetings.isEmpty {
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
            }

            if halves.meetings > 0 {
                MindHalvesCard(halves: halves)
            }

            if !raisers.isEmpty {
                MindRowsCard(title: "Tends to run tense", caption: "Out of meetings read, \(Int(((history.overall ?? 0) * 100).rounded()))% ran above your usual", rows: raisers) { link in
                    MindSignalRowView(row: MindSignalRow(
                        kind: .peaks,
                        title: linkTitle(link),
                        detail: "\(link.stressful) of \(link.read) ran above your usual",
                        value: link.meanRise.map { MindMath.signed($0) + " bpm" },
                        isCost: true,
                        number: nil, usual: nil
                    ))
                }
            }

            if !series.isEmpty {
                MindRowsCard(title: "Recurring meetings", caption: "Against the same hour on days without", rows: Array(series.prefix(5))) { item in
                    MindSignalRowView(row: MindSignalRow(
                        kind: .peaks,
                        title: MeetingDisplay.title(item.title),
                        detail: "\(item.scored) of \(item.found) times read",
                        value: MindMath.signed(item.delta),
                        isCost: item.delta > 0,
                        number: nil, usual: nil
                    ))
                }
            }

            if raisers.isEmpty, granted, history.read > 0 {
                MeetingFootnote(footnote: MeetingDisplay.footnote(history))
            }
        }
        .task { await load(asking: true) }
        .somaRefreshable { await load(asking: false) }
        .sheet(isPresented: $isBreathing) { MindBreatheSession(length: 3 * 60) }
    }

    /// "Today 14:00", "Tomorrow 09:30", "Thu 11:00".
    private func when(_ date: Date, words: PulseWording, calendar: Calendar) -> String {
        "\(MeetingDisplay.dayTitle(date, now: Date(), calendar: calendar)) \(words.time(date))"
    }

    private func linkTitle(_ link: MeetingStressAnalysis.Link) -> String {
        switch link.kind {
        case .attendee: "With \(MeetingDisplay.personName(link.title))"
        case .series: MeetingDisplay.title(link.title)
        case .keyword: "About \u{201C}\(link.title)\u{201D}"
        case .partOfDay: "In the \(link.title)"
        }
    }

    private func load(asking: Bool) async {
        access = asking ? await MeetingCalendar.requestAccess() : MeetingCalendar.access
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -Self.historyDays, to: calendar.startOfDay(for: now)) ?? now
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let horizon = calendar.date(byAdding: .day, value: MeetingStressAnalysis.forecastDays, to: now) ?? now
        events = MeetingCalendar.events(from: start, to: tomorrowStart)
        upcoming = MeetingCalendar.events(from: now, to: horizon)
        let inputs = await MindLoad.inputs(health)
        curves = await MindJourneyLoad.curves(health, inputs: inputs, days: Self.historyDays)
        assessments = await MeetingStressLoad.assessments(health, inputs: inputs, meetings: MindMeetingStress.meetings(in: events))
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
            SomaActionCard(eyebrow: "Calendar", title: "Read your meetings", detail: "Each event’s time, title and who it is with, kept on this phone.", actionTitle: "Allow", action: ask) {
                SomaOrb(aspect: .mind, scale: .mini)
            }
        case .granted:
            EmptyView()
        }
    }
}

// MARK: - Head

/// The verdict on the meetings read, the one grey line under it, and the
/// three numbers it stands on.
struct MeetingHeader: View {
    let title: String
    let reason: String?
    let stats: [SomaStat]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text(title)
                    .somaFont(type.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SomaStatRow(stats)
        }
        .padding(.top, metrics.heroTopPadding)
        .padding(.bottom, metrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Coming up

/// The meetings ahead as a timeline under their days: the time on the leading
/// edge, who it is with, and the forecast as a dot and a word. Only a meeting
/// worth preparing for carries its reason.
struct MeetingUpcomingCard: View {
    let forecasts: [MeetingStressAnalysis.Forecast]
    let now: Date
    let words: PulseWording
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceL) {
                SomaCardHeader("Coming up", caption: "Next \(MeetingStressAnalysis.forecastDays) days")
                ForEach(MeetingDisplay.days(forecasts, start: \.event.start, newestFirst: false, calendar: calendar), id: \.day) { group in
                    MeetingDaySection(title: MeetingDisplay.dayTitle(group.day, now: now, calendar: calendar)) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, forecast in
                            if index > 0 { MindHairline() }
                            MeetingForecastRow(forecast: forecast, time: words.time(forecast.event.start))
                        }
                    }
                }
            }
        }
    }
}

/// One meeting ahead: its time, who it is with, and the forecast.
struct MeetingForecastRow: View {
    let forecast: MeetingStressAnalysis.Forecast
    let time: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let event = forecast.event
        let isFlagged = forecast.level == .likely || forecast.level == .possible
        let title = MeetingDisplay.title(event.title, attendees: event.attendees)
        let people = MeetingDisplay.people(event.attendees)

        HStack(alignment: .firstTextBaseline, spacing: metrics.spaceM) {
            MeetingTime(text: time)
            VStack(alignment: .leading, spacing: metrics.spaceXS) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.spaceS) {
                    Text(title)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: metrics.spaceS)
                    MeetingStatusMark(word: forecast.level.shortTitle, tone: forecast.level.tone)
                }
                // A title that already is the person says it once.
                if !people.isEmpty, people != title {
                    Text("with \(people)")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
                if isFlagged {
                    Text(MeetingDisplay.namingPeople(in: forecast.reason))
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lately

/// The meetings gone by under their days, each one line: time, title, and
/// the heart's rise coloured by its verdict. A tap opens the evidence.
struct MeetingLatelyCard: View {
    let assessments: [MeetingStressAnalysis.Assessment]
    let now: Date
    let words: PulseWording
    let calendar: Calendar

    @State private var open: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceL) {
                SomaCardHeader("Lately", caption: "Your heart against the hour before")
                ForEach(MeetingDisplay.days(assessments, start: \.event.start, newestFirst: true, calendar: calendar), id: \.day) { group in
                    MeetingDaySection(title: MeetingDisplay.dayTitle(group.day, now: now, calendar: calendar)) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, assessment in
                            if index > 0 { MindHairline() }
                            MeetingVerdictRow(
                                assessment: assessment,
                                time: words.time(assessment.event.start),
                                isOpen: open == assessment.id
                            ) {
                                withAnimation(reduceMotion ? nil : theme.motion.emphasized) {
                                    open = open == assessment.id ? nil : assessment.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: open)
    }
}

/// One meeting gone by. Calm and tense rows carry their rise and a dot; a
/// meeting spent moving is dimmed under a walking figure, since the walk
/// explains its heart; one with too few readings carries a dash.
struct MeetingVerdictRow: View {
    let assessment: MeetingStressAnalysis.Assessment
    let time: String
    let isOpen: Bool
    let toggle: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let verdict = assessment.verdict
        let isDimmed = verdict == .active || verdict == .unknown

        VStack(alignment: .leading, spacing: metrics.spaceM) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.spaceM) {
                    MeetingTime(text: time)
                    Text(MeetingDisplay.title(assessment.event.title, attendees: assessment.event.attendees))
                        .somaFont(type.body)
                        .foregroundStyle(isDimmed ? colors.inkSecondary.color : colors.inkPrimary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: metrics.spaceS)
                    trailing
                }
                .contentShape(.rect)
            }
            .buttonStyle(SomaGlassPressStyle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isOpen ? "Hides the evidence" : "Shows the evidence")

            if isOpen {
                MeetingEvidence(assessment: assessment)
                    .padding(.leading, MeetingTime.width(metrics) + metrics.spaceM)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, metrics.browseRowVerticalPadding)
    }

    @ViewBuilder private var trailing: some View {
        let type = theme.typography
        let colors = theme.colors
        switch assessment.verdict {
        case .active:
            Image(systemName: "figure.walk")
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
        case .unknown:
            SomaMissingValue(type.captionValue)
        case .calm, .stressful:
            MeetingStatusMark(
                word: assessment.rise.map { "\(MindMath.signed($0)) bpm" } ?? assessment.verdict.title,
                tone: assessment.verdict == .stressful ? .out : .normal,
                isValue: true
            )
        }
    }

    private var accessibilityLabel: Text {
        let title = MeetingDisplay.title(assessment.event.title, attendees: assessment.event.attendees)
        let rise = assessment.rise.map { ", heart \(MindMath.signed($0)) bpm" } ?? ""
        return Text("\(time), \(title), \(assessment.verdict.title)\(rise)")
    }
}

/// The evidence under an opened row: the heart before and during, the steps,
/// and a sentence on what they add up to.
struct MeetingEvidence: View {
    let assessment: MeetingStressAnalysis.Assessment

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.spaceS) {
            HStack(alignment: .top, spacing: metrics.spaceL) {
                fact(assessment.baselineIsMeasured ? "Before" : "Usual", MindFormat.whole(assessment.baseline), unit: "bpm")
                fact("During", MindFormat.whole(assessment.stillHeartRate ?? assessment.heartRate), unit: "bpm")
                fact("Steps", MindFormat.whole(assessment.steps), unit: nil)
            }
            Text(MeetingDisplay.explanation(assessment))
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func fact(_ label: LocalizedStringResource, _ value: String?, unit: LocalizedStringResource?) -> some View {
        let type = theme.typography
        let colors = theme.colors
        return VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
            Text(label)
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceXS) {
                SomaNumber(value, type.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
                    .contentTransition(.numericText())
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
    }
}

// MARK: - Shared pieces

/// A day's heading and its rows.
struct MeetingDaySection<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: () -> Rows

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                rows()
            }
        }
    }
}

/// The clock time on a row's leading edge, in tabular digits on a column of
/// its own so the titles beside it start on one edge.
struct MeetingTime: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    /// The column: room for "13:00" and for "10:00 AM" at caption size.
    static func width(_ metrics: SomaMetrics) -> CGFloat { metrics.minimumTapTarget + metrics.spaceL + metrics.spaceS }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.captionValue)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(width: Self.width(theme.metrics), alignment: .leading)
    }
}

/// What a status means, so a colour never stands alone: a dot and a word or
/// a value. The dot always carries the status ink; the word takes it only
/// when it asks for a look, so a page of calm rows stays quiet.
enum MeetingTone {
    case normal, out, quiet

    func color(_ colors: SomaColors) -> Color {
        switch self {
        case .normal: colors.statusNormal.color
        case .out: colors.statusOut.color
        case .quiet: colors.inkSecondary.color
        }
    }
}

/// A dot and its word, or its value, on a row's trailing edge.
struct MeetingStatusMark: View {
    let word: String
    let tone: MeetingTone
    var isValue = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        HStack(alignment: .center, spacing: theme.metrics.identityDotSpacing) {
            Circle()
                .fill(tone.color(colors))
                .frame(width: theme.metrics.identityDotDiameter, height: theme.metrics.identityDotDiameter)
            Text(word)
                .somaFont(isValue ? theme.typography.captionValue : theme.typography.caption)
                .foregroundStyle(tone == .out ? tone.color(colors) : colors.inkSecondary.color)
                .contentTransition(.numericText())
        }
        .fixedSize()
    }
}

extension MeetingStressAnalysis.Forecast.Level {
    /// The forecast on a row: two words, the one to watch named as such.
    var shortTitle: String {
        switch self {
        case .likely: "Watch this one"
        case .possible: "Could run tense"
        case .unlikely: "Likely calm"
        case .unknown: "New"
        }
    }

    var tone: MeetingTone {
        switch self {
        case .likely, .possible: .out
        case .unlikely: .normal
        case .unknown: .quiet
        }
    }
}

// MARK: - Mornings and afternoons

/// Mornings against afternoons: the verdict on top, then the average peak of
/// each as two bars on one scale. Only the half that runs clearly higher
/// takes the status ink.
struct MindHalvesCard: View {
    let halves: MindMeetingStress.Halves

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let lean = MeetingDisplay.lean(halves)
        let highest = max(halves.morning ?? 0, halves.afternoon ?? 0, 1)

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.spaceL) {
                SomaCardHeader("\(MeetingDisplay.halvesVerdict(halves))", caption: "Average peak stress in meetings · last 30 days")
                HStack(alignment: .bottom, spacing: metrics.spaceL * 2) {
                    column("Mornings", hours: "before 12:00", value: halves.morning, highest: highest, isHigher: lean == .mornings)
                    column("Afternoons", hours: "after 14:00", value: halves.afternoon, highest: highest, isHigher: lean == .afternoons)
                }
            }
        }
    }

    private func column(_ title: LocalizedStringResource, hours: LocalizedStringResource, value: Double?, highest: Double, isHigher: Bool) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let height = metrics.aspectChartHeight * 2
        let fill = isHigher ? colors.statusOut.color : colors.inkSecondary.color.opacity(metrics.chartContextOpacity)

        return VStack(alignment: .leading, spacing: metrics.spaceS) {
            SomaNumber(MindFormat.whole(value), type.metricCompact)
                .foregroundStyle(isHigher ? colors.statusOut.color : colors.inkPrimary.color)
                .contentTransition(.numericText())
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius, style: .continuous)
                    .fill(colors.surfaceRecessed.color)
                if let value {
                    RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius, style: .continuous)
                        .fill(fill)
                        .frame(height: max(height * CGFloat(value / highest), metrics.chartBarCornerRadius * 2))
                }
            }
            .frame(width: metrics.minimumTapTarget, height: height)
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                Text(title)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(hours)
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value.map { "average peak \(Int($0.rounded()))" } ?? "Not measured")
    }
}

// MARK: - Footnote

/// Why nobody is named yet, quietly, with how close the nearest person or
/// series is to being judged.
struct MeetingFootnote: View {
    let footnote: (text: String, progress: Double?)

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.spaceS) {
            Text(footnote.text)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = footnote.progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.surfaceRecessed.color)
                        Capsule()
                            .fill(colors.inkSecondary.color)
                            .frame(width: proxy.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .frame(width: metrics.aspectChartWidth, height: metrics.chartTrackHeight / 2)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
