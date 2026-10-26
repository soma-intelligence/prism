//
//  ScoreParts.swift
//  Prism
//

import SwiftUI
import SomaUI
import UserNotifications

// The pieces every score page is built from, so the pages read as one
// family (the head, the chart and the readings are in AspectPageParts): the
// sentence, the lines against your usual, the trend table, the tank, the links, the move at the foot, and the sheet
// frame. Each reads the theme and draws from its inputs only.

// MARK: - The page

/// A score page: the aspect's weather behind the head, then the cards in one
/// column. The first visit to any score page opens the page guide once; the
/// toolbar's info button opens it again.
struct ScorePageScaffold<Content: View>: View {
    let aspect: SomaAspect
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme
    @State private var showsGuide = false

    init(aspect: SomaAspect, title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.aspect = aspect
        self.title = title
        self.content = content()
    }

    var body: some View {
        let metrics = theme.metrics

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                content
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle(Text(title))
        .softScrollEdges()
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsGuide = true
                } label: {
                    Label("How to read this page", systemImage: "info.circle")
                }
            }
        }
        // The guide opens when asked for, never on its own: a page that
        // covers itself on the first visit has not been read yet.
        .sheet(isPresented: $showsGuide) {
            ScoreGuideSheet(eyebrow: String(localized: title), aspect: aspect)
        }
    }
}

// MARK: - Gauge

/// Today's score on a three quarter arc: a thin line in the aspect's
/// colour over a faint track, ticks where one band of the score meets the
/// next, the number and its word in the middle, the change under them, and
/// the ends of the scale at the feet of the arc.
struct ScoreGauge: View {
    let aspect: SomaAspect
    let lead: ScorePages.Lead

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until the gauge first appears, so the fill sweeps in.
    @State private var hasAppeared = false

    /// The arc runs from 135 degrees to 405, a gap at the bottom.
    private static let start = 135.0
    private static let sweep = 270.0
    /// Where one band meets the next, on the scale of 100 the bands are cut
    /// on: the same edges as ``ScoreMath/Band``.
    private static let bandEdges = [34.0, 67.0]

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color
        let share = lead.value.map { min(1, max(0, Double($0) / Double(lead.scale))) } ?? 0
        let width = metrics.scoreGaugeWidth
        let stroke = metrics.scoreGaugeStroke
        let rangeInset = metrics.scoreDialRangeStroke + metrics.scoreDialRangeGap * 1.5

        VStack(spacing: 0) {
            ZStack {
                ScoreArc(start: Self.start, sweep: Self.sweep)
                    .stroke(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 1.5),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                if lead.value != nil {
                    ScoreArc(start: Self.start, sweep: Self.sweep * share)
                        .stroke(hue, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
                GeometryReader { proxy in
                    let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    let radius = (min(proxy.size.width, proxy.size.height) - stroke) / 2
                    let tick = metrics.scoreGaugeTickLength
                    ForEach(Self.bandEdges, id: \.self) { edge in
                        let angle = Angle.degrees(Self.start + Self.sweep * edge / 100).radians
                        Path { path in
                            path.move(to: CGPoint(x: center.x + (radius - tick / 2) * cos(angle),
                                                  y: center.y + (radius - tick / 2) * sin(angle)))
                            path.addLine(to: CGPoint(x: center.x + (radius + tick / 2) * cos(angle),
                                                     y: center.y + (radius + tick / 2) * sin(angle)))
                        }
                        .stroke(colors.inkSecondary.color,
                                style: StrokeStyle(lineWidth: metrics.scoreGaugeTickWidth, lineCap: .round))
                    }
                    if lead.value != nil {
                        let angle = Angle.degrees(Self.start + Self.sweep * share).radians
                        Circle()
                            .fill(hue)
                            .overlay(Circle().strokeBorder(colors.canvas.color, lineWidth: 2))
                            .frame(width: metrics.scoreGaugeKnob, height: metrics.scoreGaugeKnob)
                            .position(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    }
                }
                .padding(rangeInset + stroke / 2)

                // A watch bezel: a fine short tick at every two points of
                // the score, and the existing tick every ten over them.
                ScoreTicks(start: Self.start, sweep: Self.sweep, count: 50, skipEvery: 5, length: 2.5)
                    .stroke(colors.inkSecondary.color.opacity(0.3), lineWidth: 0.5)
                    .padding(rangeInset + stroke + metrics.spaceS)
                ScoreTicks(start: Self.start, sweep: Self.sweep, count: 10)
                    .stroke(colors.inkSecondary.color.opacity(0.5), lineWidth: 1)
                    .padding(rangeInset + stroke + metrics.spaceS)

                VStack(spacing: metrics.spaceXS) {
                    Text(lead.value.map { "\($0)" } ?? "-")
                        .somaFont(type.scoreGaugeFigure)
                        .foregroundStyle(colors.inkPrimary.color)
                    if let word = lead.word {
                        Text(word)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                    if let change = lead.change {
                        Text(change)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .padding(.top, metrics.spaceM)
            }
            .frame(width: width, height: width)
            .padding(.bottom, -width * 0.12)

            HStack {
                Text(verbatim: "0")
                Spacer()
                Text(verbatim: "\(lead.scale)")
            }
            .somaFont(type.captionValue)
            .foregroundStyle(colors.inkSecondary.color)
            .frame(width: width * 0.86)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.heroTopPadding)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(theme.motion.reveal) { hasAppeared = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lead.word ?? "No score yet"))
        .accessibilityValue(accessibilityValue)
    }

    /// The display role at the gauge's size: one large light number, set at
    /// its own size rather than scaled up, so it stays sharp.
    private var numberFont: SomaFontSpec {
        var spec = theme.typography.display
        spec.size *= theme.metrics.scoreGaugeNumberScale
        spec.tracking = -1.5
        spec.weight = .light
        spec.digits = .tabular
        return spec
    }

    private var accessibilityValue: Text {
        guard let value = lead.value else { return Text("Not measured") }
        var read = Text("\(value) of \(lead.scale)")
        if let change = lead.change { read = Text("\(read), \(change)") }
        return read
    }
}

/// Short ticks along an arc, one every `1 / count` of it, the first, middle
/// and last a little longer. With `skipEvery`, every nth tick is left out,
/// for a set of fine ticks drawn between coarser ones; `length` then sets
/// them all one size.
struct ScoreTicks: Shape {
    var start: Double
    var sweep: Double
    var count: Int
    var skipEvery: Int? = nil
    var length: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for index in 0...count {
            if let skipEvery, index % skipEvery == 0 { continue }
            let angle = Angle.degrees(start + sweep * Double(index) / Double(count)).radians
            let major = index == 0 || index == count || index * 2 == count
            let inner = outer - (length ?? (major ? 7 : 4))
            path.move(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
            path.addLine(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
        }
        return path
    }
}

/// An arc of a circle inset by nothing, from `start` degrees clockwise.
struct ScoreArc: Shape {
    var start: Double
    var sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(start + max(0.01, sweep)), clockwise: false)
        return path
    }
}

// MARK: - The sentence

/// The headline, then the reason: its first part in the primary ink, what
/// follows in the secondary.
struct ScoreHead: View {
    let headline: String
    let reason: String
    let aside: String?

    @Environment(\.somaTheme) private var theme

    init(_ lead: ScorePages.Lead) {
        headline = lead.headline
        reason = lead.reason
        aside = lead.aside
    }

    init(headline: String, reason: String, aside: String?) {
        self.headline = headline
        self.reason = reason
        self.aside = aside
    }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .somaFont(type.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            ScoreTwoTone.text(reason, aside, colors: colors)
                .somaFont(type.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, theme.metrics.leadSpacing / 2)
    }
}

/// The value at the head of a sheet: the number large, its unit beside it.
struct ScoreFigure: View {
    let value: String?
    let unit: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
            Text(value ?? "-")
                .somaFont(theme.typography.display)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Text(unit)
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Against your usual

/// A card of lines, each a value against the person's own usual band.
struct ScoreUsualCard: View {
    let title: LocalizedStringResource
    var caption: LocalizedStringResource = "Against your usual"
    let aspect: SomaAspect
    let lines: [ScoreMath.UsualLine]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                SomaCardHeader(title, caption: caption)
                    .padding(.bottom, theme.metrics.scoreRowSpacing / 2)
                ScoreRows(lines) { line in
                    ScoreUsualRow(line: line, aspect: aspect)
                }
            }
        }
    }
}

/// Rows with a hairline between each two.
struct ScoreRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let row: (Item) -> Row

    @Environment(\.somaTheme) private var theme

    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.row = row
    }

    var body: some View {
        let metrics = theme.metrics
        VStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Rectangle()
                        .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: 0.5)
                }
                row(item)
                    .padding(.vertical, metrics.scoreRowSpacing)
            }
        }
    }
}

struct ScoreUsualRow: View {
    let line: ScoreMath.UsualLine
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .center, spacing: theme.metrics.moveRowGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(line.detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(line.value ?? "-")
                    .somaFont(type.rowValue)
                    .foregroundStyle(line.isOff ? colors.danger.color : colors.inkPrimary.color)
                if line.band != nil || line.position != nil {
                    ScoreTrack(position: line.position, band: line.band, aspect: aspect, isOff: line.isOff)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short track with the usual band laid on it and a dot for the value.
struct ScoreTrack: View {
    let position: Double?
    let band: ClosedRange<Double>?
    let aspect: SomaAspect
    var isOff = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color
        let width = metrics.scoreTrackWidth

        ZStack(alignment: .leading) {
            Capsule()
                .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 1.5))
                .frame(height: metrics.scoreTrackHeight)
            if let band {
                Capsule()
                    .fill(hue.opacity(0.7))
                    .frame(width: max(metrics.scoreTrackHeight, width * (band.upperBound - band.lowerBound)),
                           height: metrics.scoreTrackHeight)
                    .offset(x: width * band.lowerBound)
            }
            if let position {
                Circle()
                    .fill(isOff ? theme.colors.danger.color : theme.colors.onOrb.color)
                    .frame(width: metrics.scoreTrackDot, height: metrics.scoreTrackDot)
                    .offset(x: width * position - metrics.scoreTrackDot / 2)
            }
        }
        .frame(width: width, height: metrics.scoreTrackDot)
        .accessibilityHidden(true)
    }
}

// MARK: - Trend table

struct ScoreTrendCard: View {
    let caption: LocalizedStringResource
    let rows: [ScoreMath.TrendRow]
    let note: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let column = theme.metrics.scoreTableColumn

        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                SomaCardHeader("Trend", caption: caption)
                if rows.isEmpty {
                    Text("The table fills in after two weeks of this score.")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .padding(.top, theme.metrics.spaceM)
                } else {
                    HStack {
                        Text("Period").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Change").frame(width: column, alignment: .trailing)
                        Text("Direction").frame(width: column, alignment: .trailing)
                    }
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.top, theme.metrics.spaceM)
                    ScoreRows(rows) { row in
                        HStack {
                            Text(row.period)
                                .foregroundStyle(colors.inkPrimary.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.change)
                                .foregroundStyle(row.isWorse ? colors.danger.color : colors.inkPrimary.color)
                                .frame(width: column, alignment: .trailing)
                            Text(row.direction)
                                .foregroundStyle(row.isWorse ? colors.danger.color : colors.inkSecondary.color)
                                .frame(width: column, alignment: .trailing)
                        }
                        .somaFont(type.rowValue)
                        .accessibilityElement(children: .combine)
                    }
                    Text(note)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
    }
}

// MARK: - Stats

/// Three numbers under a hairline, the way the Today page sets its scores.
struct ScoreStats: View {
    let stats: [SomaStat]

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: theme.metrics.heroSpacing) {
            Rectangle()
                .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
                .frame(height: 1 / displayScale)
            SomaStatRow(stats)
        }
        .padding(.vertical, theme.metrics.spaceXS)
    }
}

// MARK: - Links

/// One row of a links card.
/// A row with no action states a fact and carries no chevron.
struct ScoreLink: Identifiable {
    var id: String { title }
    var title: String
    var detail: String?
    var action: (() -> Void)?
}

struct ScoreLinks: View {
    let links: [ScoreLink]

    var body: some View {
        SomaBrowseGroup(links, hasGlyphs: false) { link in
            SomaBrowseRow(title: link.title, detail: link.detail, opensSomething: link.action != nil,
                          action: link.action)
        }
    }
}

// MARK: - The move

/// The one thing the page offers. A move with a time carries a reminder,
/// which is a local notification on this device and nothing else.
struct ScoreMoveCard: View {
    let move: ScorePages.Move
    let aspect: SomaAspect
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var reminded = false

    var body: some View {
        let title: String? = actionTitle ?? (move.remindAt == nil ? nil : (reminded ? "Set" : "Remind me"))
        SomaActionCard(
            eyebrow: move.eyebrow,
            title: move.title,
            detail: move.detail,
            actionTitle: title,
            action: action ?? move.remindAt.map { hour in
                {
                    Task {
                        reminded = await ScoreReminder.schedule(title: move.title, body: move.detail, at: hour)
                    }
                }
            }
        ) {
            SomaObjectIcon(aspect: aspect, size: .row)
        }
    }
}

/// A one time reminder for a page's move.
enum ScoreReminder {
    /// Asks for permission if it was never asked, then schedules the reminder
    /// for the next time the clock reads `hour`. Returns whether it was set.
    @discardableResult
    static func schedule(title: String, body: String, at hour: Double, calendar: Calendar = .current) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return false }
        let wrapped = ScoreMath.HealthStatsClock.wrap(hour)
        let minutes = Int((wrapped * 60).rounded())
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: false)
        let request = UNNotificationRequest(identifier: "score.move." + title, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - About

/// What a reading is, at the foot of its sheet: one explainer row, the bold
/// term saying what it is and the grey line saying how to read it.
struct ScoreAbout: View {
    let lead: String
    let rest: String
    var symbol = "info.circle.fill"
    var hue: SomaHealthHue = .other

    var body: some View {
        SomaExplainerSection("About") {
            SomaExplainerRow(symbol: symbol, hue: hue, term: lead, line: rest)
        }
    }
}

/// The small print at the foot of a sheet.
struct ScoreFootnote: View {
    let text: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .somaColumnSpan(.full)
    }
}

/// A titled block on a score page: the title, an optional caption on the
/// trailing edge, and what it introduces.
struct ScoreSection<Content: View>: View {
    let title: LocalizedStringResource
    var caption: String?
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(title: LocalizedStringResource, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .somaFont(theme.typography.title)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let caption {
                    Text(caption)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            content
        }
        .padding(.top, theme.metrics.cardSpacing)
    }
}

/// A heading over a group of links.
struct ScoreSectionTitle: View {
    let text: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text(text)
            .somaFont(theme.typography.cardTitle)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, theme.metrics.spaceS)
    }
}

// MARK: - Bands

/// The bands a score is read in, side by side, with today's value marked
/// over its band and, optionally, the usual as a ring.
struct ScoreBandBar: View {
    struct Band: Identifiable {
        var id: String { title }
        var title: String
        var detail: String
    }

    let bands: [Band]
    let aspect: SomaAspect
    /// 0 to 1 across the whole bar.
    let position: Double?
    var label: String?
    var usual: Double?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color

        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: theme.metrics.spaceXS) {
                        ForEach(Array(bands.enumerated()), id: \.offset) { index, _ in
                            Capsule()
                                .fill(hue.opacity(0.35 + 0.55 * Double(index) / Double(max(1, bands.count - 1))))
                        }
                    }
                    .frame(height: 8)
                    if let usual {
                        Circle()
                            .strokeBorder(colors.onOrb.color, lineWidth: 2)
                            .frame(width: metrics.scoreTrackDot + 2, height: metrics.scoreTrackDot + 2)
                            .offset(x: width * usual - (metrics.scoreTrackDot + 2) / 2)
                    }
                    if let position {
                        Circle()
                            .fill(colors.onOrb.color)
                            .frame(width: metrics.scoreTrackDot + 4, height: metrics.scoreTrackDot + 4)
                            .offset(x: width * position - (metrics.scoreTrackDot + 4) / 2)
                        if let label {
                            Text(label)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkPrimary.color)
                                .fixedSize()
                                .offset(x: min(max(0, width * position - 30), width - 70), y: -20)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            .padding(.top, label == nil ? 0 : 20)

            HStack(alignment: .top) {
                ForEach(bands) { band in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(band.title)
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text(band.detail)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The sheet

/// A sheet over a score page: the Done button, an eyebrow, a title, then the
/// content in one column.
struct ScoreSheet<Content: View>: View {
    let eyebrow: String
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(eyebrow: String, title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.title = title
        self.content = content()
    }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                        Text(eyebrow)
                            .somaFont(type.eyebrow)
                            .foregroundStyle(colors.inkSecondary.color)
                        Text(title)
                            .somaFont(type.title)
                            .foregroundStyle(colors.inkPrimary.color)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.bottom, theme.metrics.spaceXS)
                    content
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.pagePadding)
                .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .softScrollEdges()
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A plain lead paragraph: its first part in the primary ink.
struct ScoreParagraph: View {
    let lead: String
    let rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        ScoreTwoTone.text(lead, rest, colors: colors)
            .somaFont(theme.typography.callout)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A sentence in two inks: the part that says what it means in the primary,
/// the part that says why in the secondary.
enum ScoreTwoTone {
    static func text(_ first: String, _ second: String?, colors: SomaColors) -> Text {
        let lead = Text(first).foregroundStyle(colors.inkPrimary.color)
        guard let second, !second.isEmpty else { return lead }
        let rest = Text(" " + second).foregroundStyle(colors.inkSecondary.color)
        return Text("\(lead)\(rest)")
    }
}

/// Rows that push another score page.
struct ScorePageLinks: View {
    let routes: [(route: ScoreRoute, title: String, detail: String?)]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaBrowseGroup(routes.map(ScorePageLinkRow.init), hasGlyphs: false) { row in
            NavigationLink(value: row.route) {
                SomaBrowseRow(title: row.title, detail: row.detail)
            }
            .zoomSource(row.route)
            .buttonStyle(.plain)
        }
    }
}

private struct ScorePageLinkRow: Identifiable {
    var id: String { title }
    let route: ScoreRoute
    let title: String
    let detail: String?

    init(_ item: (route: ScoreRoute, title: String, detail: String?)) {
        route = item.route
        title = item.title
        detail = item.detail
    }
}
