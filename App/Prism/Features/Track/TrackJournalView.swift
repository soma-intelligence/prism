//
//  TrackJournalView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Track, Journal: the week, then the chosen day.
/// A count and a ring for what is logged, a grid of things to add, the tags
/// as grouped rows with a switch each, what Health measured as automatic
/// rows, how the day felt on one scale, and two compact cards for what the
/// tags have done to the body over the last two months.
///
/// The tags and the feeling are the person's own words, kept by
/// ``JournalStore``. Everything set beside them is read from Apple Health; a
/// value Health does not hold is a dash.
struct TrackJournalView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var measured = TrackBody()
    @State private var totals = TrackDayTotals()
    @State private var source: (any HealthSampleSource)?
    @State private var opened: TrackRoute?

    private let calendar = Calendar.current
    private let log = TrackLogStore.shared

    /// False lays the column out without its scroll view, for a render
    /// check: an image renderer draws a scroll view as an empty box.
    private let scrolls: Bool

    init() { scrolls = true }

    /// Starts from readings already in hand, for previews and render checks:
    /// the page reads Health again when it appears.
    init(measured: TrackBody, totals: TrackDayTotals, scrolls: Bool = true) {
        _measured = State(initialValue: measured)
        _totals = State(initialValue: totals)
        self.scrolls = scrolls
    }

    var body: some View {
        if scrolls {
            SomaPageScroll {
                // SomaPageScroll holds the column to the scroll view's width:
                // a card whose content ran a point wider made the whole page
                // pan sideways under a finger.
                column
                    .clipped()
            }
            .softScrollEdges()
                .background(theme.colors.canvas.color.ignoresSafeArea())
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .task { await load() }
                .task(id: selected) { await readTotals() }
                .somaRefreshable {
                    await load()
                    await readTotals()
                }
        } else {
            column.background(theme.colors.canvas.color)
        }
    }

    private var column: some View {
        let metrics = theme.metrics
        let today = calendar.startOfDay(for: .now)
        let days = loggedDays
        let points = TrackJournal.feelPoints(days: days, body: measured, today: today, calendar: calendar)

        let spacing = metrics.spaceL

        // The week over everything; under it, what the day holds and how it
        // went. A phone reads them as one column; where the width holds two,
        // the log sits beside the feeling and the charts, as an iPad page
        // would set them.
        return SomaColumnsLayout(
            minColumnWidth: metrics.cardColumnMinWidth,
            spacing: spacing,
            maxColumns: metrics.cardColumnLimit
        ) {
            TrackWeekStrip(selected: $selected, today: today, calendar: calendar) { day in
                !journal.day(day).isEmpty
            }
            .somaColumnSpan(.full)

            VStack(alignment: .leading, spacing: spacing) {
                entriesHeader

                TrackAddToday()

                tagSections

                automaticSection
            }

            VStack(alignment: .leading, spacing: spacing) {
                TrackFeelingRow(feeling: journal.day(selected).feeling) {
                    journal.setFeeling($0, on: selected)
                }

                TrackFeelMeasureCard(points: points, highlighted: selected, today: today, calendar: calendar)

                TrackEffectsCard(
                    effects: TrackJournal.effects(
                        tags: journal.tags, days: days, body: measured, today: today, calendar: calendar
                    )
                )

                copyButton
            }
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, metrics.cardSpacing)
        .padding(.bottom, metrics.pagePadding)
        .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var loggedDays: [Date: JournalDay] {
        Dictionary(journal.loggedDays.map { ($0.date, $0.day) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Entries header

    /// What the chosen day holds: tags, a feeling, and what was added from
    /// the grid (drinks, meals, doses).
    private var entryCount: Int {
        let entry = journal.day(selected)
        return entry.tags.count + entry.declined.count + (entry.feeling == nil ? 0 : 1)
            + log.drinks(on: selected).count + log.meals(on: selected).count + log.doses(on: selected).count
    }

    private var entriesHeader: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let count = entryCount
        // The ring fills as the journal itself does: the tags on offer and
        // the feeling are the day's questions.
        let day = journal.day(selected)
        let questions = max(1, journal.offeredTags.count + 1)
        let answered = journal.offeredTags.filter { day.answer($0.id) != nil }.count + (day.feeling == nil ? 0 : 1)

        return HStack(alignment: .center, spacing: metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                Text(entriesTitle)
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(count == 1 ? "1 entry" : "\(count) entries")
                    .somaFont(type.caption)
                    .monospacedDigit()
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: metrics.cardSpacing)
            // The ring and its number say the same thing: how many of the
            // day's questions have an answer.
            SomaProgressRing(fraction: Double(answered) / Double(questions)) {
                Text("\(answered)/\(questions)")
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkPrimary.color)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("\(answered) of \(questions) answered"))
        }
        .padding(.top, metrics.scoreLabelSpacing)
    }

    private var entriesTitle: String {
        if calendar.isDateInToday(selected) { return "Today\u{2019}s entries" }
        if calendar.isDateInYesterday(selected) { return "Yesterday" }
        return selected.formatted(.dateTime.weekday(.wide))
    }

    // MARK: Tags

    /// A row of the tag list: a yes or no question, or an amount the day
    /// counts (drinks, caffeine) that opens where it is logged.
    private enum HabitItem: Identifiable {
        case tag(JournalTag)
        case quantity(TrackJournalQuantity)

        var id: String {
            switch self {
            case .tag(let tag): "tag.\(tag.id)"
            case .quantity(let quantity): "quantity.\(quantity.rawValue)"
            }
        }
    }

    private var tagSections: some View {
        let metrics = theme.metrics
        let entry = journal.day(selected)
        let grouped = Dictionary(grouping: journal.offeredTags) { TrackTagStyle.of($0.id).section }
        let quantities = Dictionary(grouping: TrackJournalQuantity.allCases, by: \.section)
        let sections = TrackTagStyle.Section.allCases.filter { grouped[$0] != nil || quantities[$0] != nil }

        return VStack(alignment: .leading, spacing: metrics.spaceXL) {
            ForEach(sections) { section in
                let tags = grouped[section] ?? []
                let items = (quantities[section] ?? []).map(HabitItem.quantity) + tags.map(HabitItem.tag)
                let answered = tags.filter { entry.answer($0.id) != nil }.count
                VStack(alignment: .leading, spacing: metrics.journalSectionHeadingSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        sectionHeading(section.title)
                        Spacer(minLength: metrics.cardSpacing)
                        if !tags.isEmpty {
                            Text("\(answered) of \(tags.count)")
                                .somaFont(theme.typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(answered == tags.count ? section.tone.color : theme.colors.inkSecondary.color)
                        }
                    }
                    .padding(.horizontal, metrics.scoreLabelSpacing)
                    SomaHabitStack(items) { item in
                        habitRow(item)
                    }
                }
            }
        }
        .trackEntrySheet(item: $opened)
    }

    @ViewBuilder
    private func habitRow(_ item: HabitItem) -> some View {
        switch item {
        case .tag(let tag):
            let style = TrackTagStyle.of(tag.id)
            SomaHabitRow(
                glyph: style.glyph,
                title: tag.title,
                tone: style.tone,
                answer: Binding(
                    get: { journal.day(selected).answer(tag.id) },
                    set: { journal.answer(tag.id, $0, on: selected) }
                )
            )
        case .quantity(let quantity):
            let amount = quantity.amount(on: selected, log: log)
            SomaHabitRow(glyph: quantity.glyph, title: quantity.title, tone: quantity.tone,
                         value: amount.value, unit: amount.unit) {
                opened = quantity.route
            }
        }
    }

    /// A section's name over its cards, such as Daytime or Evening: small, in
    /// the secondary ink.
    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .somaFont(theme.typography.cardTitle)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Automatic

    private struct AutoRow: Identifiable {
        var id: String { title }
        var title: String
        var glyph: SomaTrackGlyph.Kind
        var tone: SomaTrackTone
        var detail: String?
        var mark: SomaHabitMark.State
    }

    /// What Health measured on the chosen day, each against its goal: met is
    /// a check, short of it is a ring part filled, nothing is a dash.
    private var autoRows: [AutoRow] {
        typealias Goal = TrackDayTotals.Goal
        func mark(_ value: Double?, goal: Double) -> SomaHabitMark.State {
            guard let value else { return .missing }
            return value >= goal ? .met : .progress(value / goal)
        }
        let slept = measured.nightAsleep[selected]
        let variability = measured.dayVariability[selected]
        let usual = measured.usualVariability
        // Sleep is read against your own need where Soma knows it, the way
        // every other page reads it; the fixed seven hours only stand in
        // until then.
        let need = health.scores?.sleepNeedHours ?? Goal.sleepHours

        return [
            AutoRow(title: "Sleep need, \(TrackJournalFormat.hours(need))", glyph: .sleep, tone: .dusk,
                    detail: slept.map(TrackJournalFormat.hours), mark: mark(slept, goal: need)),
            AutoRow(title: "8,000 steps", glyph: .steps, tone: .moss,
                    detail: totals.steps.map(TrackFormat.whole), mark: mark(totals.steps, goal: Goal.steps)),
            AutoRow(title: "30 min outdoors", glyph: .daylight, tone: .sand,
                    detail: totals.daylightMinutes.map(TrackJournalFormat.minutes),
                    mark: mark(totals.daylightMinutes, goal: Goal.daylightMinutes)),
            AutoRow(title: "30 min exercise", glyph: .exercise, tone: .sage,
                    detail: totals.exerciseMinutes.map(TrackJournalFormat.minutes),
                    mark: mark(totals.exerciseMinutes, goal: Goal.exerciseMinutes)),
            AutoRow(title: "HRV at usual", glyph: .hrv, tone: .tide,
                    detail: variability.map { "\(TrackFormat.whole($0)) ms" },
                    mark: usual.map { mark(variability, goal: $0) } ?? .missing),
        ]
    }

    private var automaticSection: some View {
        let metrics = theme.metrics
        return VStack(alignment: .leading, spacing: metrics.journalSectionHeadingSpacing) {
            sectionHeading("Automatic")
                .padding(.leading, metrics.scoreLabelSpacing)
            SomaHabitStack(autoRows) { row in
                SomaHabitRow(glyph: row.glyph, title: row.title, detail: row.detail,
                             tone: row.tone, mark: row.mark)
            }
        }
    }

    // MARK: Copy

    @ViewBuilder
    private var copyButton: some View {
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: selected) {
            let before = journal.day(yesterday)
            let answered = journal.day(selected).tags.union(journal.day(selected).declined)
            if !before.tags.union(before.declined).subtracting(answered).isEmpty {
                SomaActionButton("Copy answers from the day before", role: .secondary) {
                    journal.copyTags(from: yesterday, to: selected)
                }
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let source = await health.prepare([]) else {
            self.source = nil
            measured = TrackBody()
            return
        }
        self.source = source
        let inputs = await TrackInputs.read(from: source, now: .now, calendar: calendar)
        measured = TrackBody.make(from: inputs, calendar: calendar)
    }

    private func readTotals() async {
        let source: (any HealthSampleSource)?
        if let known = self.source {
            source = known
        } else {
            source = await health.prepare([])
        }
        guard let source else {
            totals = TrackDayTotals()
            return
        }
        totals = await TrackDayTotals.read(from: source, day: selected, now: .now, calendar: calendar)
    }
}

/// What the Journal counts rather than asks, set among the tags with an
/// amount and an arrow: the day's drinks and its caffeine, both read from
/// what was poured on the drink sheet, which the row opens.
enum TrackJournalQuantity: String, CaseIterable {
    case caffeine, drinks

    var title: String {
        switch self {
        case .caffeine: "Caffeine"
        case .drinks: "Drinks"
        }
    }

    var glyph: SomaTrackGlyph.Kind {
        switch self {
        case .caffeine: .coffee
        case .drinks: .drink
        }
    }

    var section: TrackTagStyle.Section { .daytime }

    var tone: SomaTrackTone {
        switch self {
        case .caffeine: section.tone
        case .drinks: .tide
        }
    }

    var route: TrackRoute {
        switch self {
        case .caffeine: .drink(.coffee)
        case .drinks: .drink(.water)
        }
    }

    /// The day's amount and its unit. Nothing logged is a nil value, which
    /// the row draws as the missing mark, with no unit beside it.
    @MainActor
    func amount(on day: Date, log: TrackLogStore) -> (value: String?, unit: String) {
        switch self {
        case .caffeine:
            return (log.caffeineMg(on: day).map(TrackFormat.whole), "mg")
        case .drinks:
            return TrackJournalFormat.volume(log.waterMl(on: day))
        }
    }
}

/// Numbers the Journal's rows set.
enum TrackJournalFormat {
    /// Hours and minutes the way every duration is written: "7h 24m".
    static func hours(_ hours: Double) -> String {
        SomaFormat.duration(hours * 3600)
    }

    /// Minutes as a duration: "45m", "1h 10m".
    static func minutes(_ minutes: Double) -> String {
        SomaFormat.duration(minutes * 60)
    }

    /// Millilitres under a litre, litres from there: "750" ml, "1.5" L. Nil
    /// stays nil, in millilitres.
    static func volume(_ ml: Double?) -> (value: String?, unit: String) {
        guard let ml else { return (nil, "ml") }
        if ml < 1000 { return (TrackFormat.whole(ml), "ml") }
        return ((ml / 1000).formatted(.number.precision(.fractionLength(0...1))), "L")
    }
}

// MARK: - Week strip

/// Monday to Sunday of the chosen week. The chosen day sits in a raised tile
/// with the accent dot; a grey dot marks a day that holds entries. A swipe
/// moves a week, never past this one.
private struct TrackWeekStrip: View {
    @Binding var selected: Date
    let today: Date
    let calendar: Calendar
    let hasEntries: (Date) -> Bool

    @Namespace private var tile
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let days = TrackWeek.days(containing: selected, calendar: calendar)

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
        }
        .contentShape(.rect)
        .sensoryFeedback(.selection, trigger: selected)
        .somaClaimsSwipe()
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    move(weeks: value.translation.width > 0 ? -1 : 1)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(weeks: 1)
            case .decrement: move(weeks: -1)
            @unknown default: break
            }
        }
    }

    private func move(weeks: Int) {
        select(TrackWeek.shift(selected, weeks: weeks, today: today, calendar: calendar))
    }

    /// One change, one motion: a tapped day and a swiped week land on the
    /// same selection spring, and simply land under Reduce Motion.
    private func select(_ day: Date) {
        guard day != selected else { return }
        if reduceMotion {
            selected = day
        } else {
            withAnimation(theme.motion.selection) { selected = day }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isFuture = TrackWeek.isFuture(day, today: today, calendar: calendar)
        // The accent rides the chosen day's letter and number; the tile is
        // the tonal step.
        let future = colors.inkSecondary.color.opacity(theme.motion.dimOpacity)
        let ink = isFuture ? future : (isSelected ? colors.accent.color : colors.inkSecondary.color)
        let number = isFuture ? future : (isSelected ? colors.accent.color : colors.inkPrimary.color)

        return Button {
            select(day)
        } label: {
            VStack(spacing: metrics.spaceXS) {
                Text(TrackWeek.letter(day, calendar: calendar))
                    .somaFont(type.tabLabel)
                    .foregroundStyle(ink)
                Text(day.formatted(.dateTime.day()))
                    .somaFont(type.body)
                    .monospacedDigit()
                    .foregroundStyle(number)
                Circle()
                    .fill(isSelected ? colors.accent.color : colors.inkSecondary.color)
                    .frame(width: metrics.aspectDotSize, height: metrics.aspectDotSize)
                    .opacity(isSelected || (!isFuture && hasEntries(day)) ? 1 : 0)
            }
            .padding(.vertical, metrics.spaceS)
            .frame(maxWidth: .infinity)
            .background {
                // One tile that moves to the chosen day, rather than one
                // fading out while another fades in.
                if isSelected {
                    RoundedRectangle(cornerRadius: metrics.controlCornerRadius, style: .continuous)
                        .fill(colors.surface.color)
                        .matchedGeometryEffect(id: "chosen", in: tile)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
        .disabled(isFuture)
        .accessibilityLabel(Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}


// MARK: - How you felt

/// The day's feeling on one row of seven stops along the calm ramp. The chosen stop's
/// name sits beside the label, in its own colour.
private struct TrackFeelingRow: View {
    let feeling: Int?
    let set: (Int?) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.spaceXS) {
                HStack(alignment: .firstTextBaseline) {
                    TrackEyebrow("How you felt")
                    Spacer(minLength: metrics.cardSpacing)
                    SomaNumber(feeling.map { TrackJournal.feelingLabels[$0] }, theme.typography.caption)
                        .foregroundStyle(feeling.map { SomaFeelingScale.color($0, theme: theme) } ?? colors.inkSecondary.color)
                }
                SomaFeelingScale(
                    value: Binding(get: { feeling }, set: { set($0) }),
                    names: TrackJournal.feelingLabels
                )
            }
        }
    }
}

// MARK: - Feel and measure

/// The last three weeks as a strip, one column a day: a bar up or down from
/// the line by how far the day's variability sat from the usual, coloured by
/// how the day felt. A filled bar is a day the two agreed; an outlined one, a
/// day they parted.
private struct TrackFeelMeasureCard: View {
    let points: [TrackFeelPoint]
    let highlighted: Date
    let today: Date
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let enough = points.count >= TrackJournal.feelMinimum
        let agreed = points.filter(\.agrees).count

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.spaceXS) {
                    TrackEyebrow("Feel and measure")
                    Spacer(minLength: metrics.cardSpacing)
                    SomaNumber(enough ? "\(agreed)/\(points.count)" : nil, type.metricCompact)
                        .monospacedDigit()
                        .foregroundStyle(enough ? SomaTrackTone.sage.color : colors.inkSecondary.color)
                    Text(enough ? "agree" : "\(points.count) of \(TrackJournal.feelMinimum) days")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                strip
            }
        }
    }

    private var strip: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let byDay = Dictionary(points.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let days = (0..<TrackJournal.feelDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let largest = points.map { abs($0.deviation) }.max() ?? 0
        let range = max(10, (largest / 5).rounded(.up) * 5)
        let height = metrics.journalTileHeight

        return VStack(spacing: metrics.spaceXS) {
            GeometryReader { proxy in
                let slot = proxy.size.width / CGFloat(days.count)
                let bar = max(2, slot * 0.55)
                let mid = proxy.size.height / 2

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity))
                        .frame(width: proxy.size.width, height: 0.5)
                        .offset(y: mid)

                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        let x = slot * (CGFloat(index) + 0.5)
                        let isHighlighted = calendar.isDate(day, inSameDayAs: highlighted)
                        if let point = byDay[day] {
                            let hue = SomaFeelingScale.color(point.feeling, theme: theme)
                            let length = max(bar, CGFloat(abs(point.deviation) / range) * (mid - bar / 2))
                            let shape = RoundedRectangle(cornerRadius: bar / 2, style: .continuous)
                            Group {
                                if point.agrees {
                                    shape.fill(hue)
                                } else {
                                    shape.strokeBorder(hue, lineWidth: 1.5)
                                }
                            }
                            .frame(width: bar, height: length)
                            .position(x: x, y: point.deviation >= 0 ? mid - length / 2 : mid + length / 2)
                        } else {
                            Circle()
                                .fill(colors.surfaceRecessed.color)
                                .frame(width: metrics.aspectDotSize, height: metrics.aspectDotSize)
                                .position(x: x, y: mid)
                        }
                        if isHighlighted {
                            Circle()
                                .fill(colors.accent.color)
                                .frame(width: metrics.aspectDotSize, height: metrics.aspectDotSize)
                                .position(x: x, y: proxy.size.height - metrics.aspectDotSize / 2)
                        }
                    }
                }
            }
            .frame(height: height)

            HStack {
                Image(systemName: "arrow.up")
                Text("HRV")
                Spacer()
                Text("\(TrackJournal.feelDays) days")
            }
            .somaFont(theme.typography.tabLabel)
            .foregroundStyle(colors.inkSecondary.color)
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(points.filter(\.agrees).count) of \(points.count) days, feeling and body agreed."))
    }
}

// MARK: - What your tags do

/// Each tag's move on the reading it lands on, as a signed number over a
/// small centred bar: sage for the better, clay for a cost.
private struct TrackEffectsCard: View {
    let effects: [TrackTagEffect]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    TrackEyebrow("What your tags do")
                    Spacer(minLength: metrics.cardSpacing)
                    Text("\(TrackJournal.effectDays) d")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }

                if effects.isEmpty {
                    SomaMissingValue(type.metricCompact)
                } else {
                    ForEach(Array(effects.enumerated()), id: \.element.id) { index, effect in
                        if index > 0 { TrackHairline() }
                        row(effect)
                    }
                }
            }
        }
    }

    private func row(_ effect: TrackTagEffect) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let style = TrackTagStyle.of(effect.id)
        // No move, or one that rounds to nothing, stays in the ink.
        let tone = effect.fraction == nil || (effect.valueText?.hasPrefix("0") ?? true)
            ? colors.inkSecondary.color
            : (effect.isCost ? SomaTrackTone.clay.color : SomaTrackTone.sage.color)

        return HStack(alignment: .center, spacing: metrics.cardSpacing) {
            SomaTrackGlyph(style.glyph, tone: style.tone, style: .row)
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                Text(effect.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                Text(effect.reading.name)
                    .somaFont(type.tabLabel)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: metrics.scoreLabelSpacing)
            VStack(alignment: .trailing, spacing: metrics.spaceXS) {
                SomaNumber(effect.valueText, type.rowValue)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .fixedSize()
                SomaEffectBar(fraction: effect.fraction, isCost: effect.isCost)
                    .frame(width: metrics.aspectChartWidth * 0.6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(effect.title), \(effect.reading.name), \(effect.valueText ?? SomaFormat.notMeasured). \(effect.detailText)"))
    }
}

#if DEBUG
#Preview("Journal") {
    NavigationStack {
        TrackJournalView()
    }
    .environment(HealthDashboard())
    .environment(JournalStore(url: nil))
}
#endif
