//
//  SomaDayTimeline.swift
//  SomaUI
//

import SwiftUI

/// The whole day down a time axis: the hours on the leading edge, each event a
/// card beside its time with its glyph in its hue, the axis itself coloured
/// while something lasts, and an ink line across the present moment.
///
/// Quiet hours fold away: an hour is drawn only when something happens in it,
/// and every run of hours left out becomes one short dotted span. Events
/// still to come draw as outlines.
public struct SomaDayTimeline: View {
    private let events: [SomaTimelineEvent]
    private let now: Date
    private let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    public init(_ events: [SomaTimelineEvent], now: Date, calendar: Calendar = .current) {
        self.events = events
        self.now = now
        self.calendar = calendar
    }

    public var body: some View {
        let layout = SomaDayTimelineLayout(events: events, now: now, calendar: calendar)
        let labels = layout.rows.compactMap(\.label)

        VStack(spacing: 0) {
            ForEach(Array(layout.rows.enumerated()), id: \.element.id) { index, row in
                SomaDayTimelineRowView(
                    row: row,
                    labels: labels,
                    upper: index > 0 ? layout.span(between: layout.rows[index - 1], and: row) : .none,
                    lower: index < layout.rows.count - 1 ? layout.span(between: row, and: layout.rows[index + 1]) : .none
                )
            }
        }
    }
}

/// One stop down the axis.
enum SomaDayTimelineRow: Identifiable {
    case hour(Date)
    /// A run of quiet hours folded into one span.
    case gap(from: Date, to: Date)
    case event(SomaTimelineEvent, Date)
    case now(Date)

    var id: String {
        switch self {
        case .hour(let date): "hour-\(date.timeIntervalSinceReferenceDate)"
        case .gap(let from, _): "gap-\(from.timeIntervalSinceReferenceDate)"
        case .event(let event, _): "event-\(event.id)"
        case .now: "now"
        }
    }

    /// Where the row's marker sits on the clock.
    var time: Date {
        switch self {
        case .hour(let date), .event(_, let date), .now(let date): date
        case .gap(let from, let to): from.addingTimeInterval(to.timeIntervalSince(from) / 2)
        }
    }

    /// The order among rows at the same minute: the hour, then the event, then now.
    var rank: Int {
        switch self {
        case .hour: 0
        case .gap: 1
        case .event: 2
        case .now: 3
        }
    }

    var label: String? {
        switch self {
        case .hour(let date), .now(let date): SomaDayTimelineLayout.clock(date)
        case .event(let event, _): event.time
        case .gap: nil
        }
    }
}

/// What the axis draws between two rows.
enum SomaDayTimelineSpan: Equatable {
    case none
    /// The plain hairline.
    case plain
    /// Dotted, through folded hours.
    case folded
    /// Coloured, while an event lasts.
    case lasting(SomaHealthHue, planned: Bool)
}

/// The rows of a day, worked out once per render from the events and now.
struct SomaDayTimelineLayout {
    let rows: [SomaDayTimelineRow]
    private let lasting: [SomaTimelineEvent]

    init(events: [SomaTimelineEvent], now: Date, calendar: Calendar) {
        let placed = events
            .filter { !$0.isNow && $0.start != nil }
            .sorted { $0.start! < $1.start! }
        lasting = placed.filter(\.lasts)

        // Every moment that keeps the hours around it on the axis.
        var moments = placed.compactMap(\.start) + placed.filter(\.lasts).compactMap(\.end)
        moments.append(now)

        let starts = placed.compactMap(\.start) + [now]
        let first = Self.floorHour(moments.min() ?? now, calendar: calendar)
        let lastStart = (placed.compactMap(\.start) + [now]).max() ?? now
        let last = Self.floorHour(lastStart, calendar: calendar).addingTimeInterval(3600)

        var rows: [SomaDayTimelineRow] = []
        var folded: [Date] = []
        var hour = first
        while hour <= last {
            // The hour an event falls in stays; an event on the hour stands in
            // for its tick, so the same time is never printed twice.
            let holds = moments.contains { Self.floorHour($0, calendar: calendar) == hour }
            let onTheHour = starts.contains { $0 >= hour && $0.timeIntervalSince(hour) < 5 * 60 }
            if onTheHour {
                if let start = folded.first, let end = folded.last {
                    rows.append(.gap(from: start, to: end))
                    folded.removeAll()
                }
            } else if holds || hour == first || hour == last {
                if let start = folded.first, let end = folded.last {
                    rows.append(.gap(from: start, to: end))
                    folded.removeAll()
                }
                rows.append(.hour(hour))
            } else {
                folded.append(hour)
            }
            hour = hour.addingTimeInterval(3600)
        }
        rows += placed.map { .event($0, $0.start!) }
        rows.append(.now(now))
        self.rows = rows.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.rank < rhs.rank : lhs.time < rhs.time
        }
    }

    /// How the axis reads between two neighbouring rows: coloured under a
    /// lasting event's card and wherever one lasts across the middle of the
    /// stretch, dotted through folded hours.
    func span(between upper: SomaDayTimelineRow, and lower: SomaDayTimelineRow) -> SomaDayTimelineSpan {
        let middle = upper.time.addingTimeInterval(lower.time.timeIntervalSince(upper.time) / 2)
        // An event always colours the stretch under its own card, however short,
        // so a folded axis never swallows it.
        if case .event(let event, _) = upper, event.lasts {
            return .lasting(event.resolvedHue, planned: event.isPlanned)
        }
        if let event = lasting.first(where: { $0.start! <= middle && middle < $0.end! }) {
            return .lasting(event.resolvedHue, planned: event.isPlanned)
        }
        if case .gap = upper { return .folded }
        if case .gap = lower { return .folded }
        return .plain
    }

    static func floorHour(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// A clock time, 24 hour: 14:00.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// One row: the time in the leading column, the axis with its marker, and the
/// row's content.
struct SomaDayTimelineRowView: View {
    let row: SomaDayTimelineRow
    /// Every label on the axis, laid out hidden so the column takes the widest.
    let labels: [String]
    let upper: SomaDayTimelineSpan
    let lower: SomaDayTimelineSpan

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        let row = HStack(spacing: 0) {
            label
                .padding(.trailing, metrics.timelineTextGap)
                .accessibilityHidden(true)
            content
                .padding(.leading, metrics.timelineAxisColumn + metrics.timelineTextGap)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(alignment: .leading) {
                    axis.frame(width: metrics.timelineAxisColumn)
                }
        }

        // An event speaks through its own row, which carries the link; the
        // now line speaks for itself; the hours and folds stay silent.
        switch self.row {
        case .event:
            row
        case .now:
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        case .hour, .gap:
            row.accessibilityHidden(true)
        }
    }

    private var minHeight: CGFloat {
        let metrics = theme.metrics
        switch row {
        case .hour: return metrics.timelineHourRowHeight
        case .gap: return metrics.timelineGapRowHeight
        case .now: return metrics.timelineNowRowHeight
        case .event: return 0
        }
    }

    // MARK: The leading column

    private var label: some View {
        let colors = theme.colors

        return ZStack(alignment: .trailing) {
            ForEach(Array(Set(labels)).sorted(), id: \.self) { other in
                Text(other).hidden()
            }
            if let text = row.label {
                switch row {
                case .now:
                    Text(text)
                        .fontWeight(.semibold)
                        .foregroundStyle(colors.inkPrimary.color)
                case .event(let event, _):
                    Text(text)
                        .foregroundStyle(event.isPlanned ? colors.inkSecondary.color : colors.inkPrimary.color)
                default:
                    Text(text)
                        .foregroundStyle(colors.inkSecondary.color.opacity(0.7))
                }
            }
        }
        .somaFont(theme.typography.captionValue)
    }

    // MARK: The axis

    private var axis: some View {
        VStack(spacing: 0) {
            segment(upper)
            segment(lower)
        }
        .overlay { marker }
    }

    @ViewBuilder
    private func segment(_ span: SomaDayTimelineSpan) -> some View {
        let metrics = theme.metrics
        let ink = theme.colors.inkPrimary.color

        switch span {
        case .none:
            Color.clear
        case .plain:
            Rectangle()
                .fill(ink.opacity(metrics.hairlineOpacity * 2))
                .frame(width: metrics.timelineAxisWidth)
        case .folded:
            SomaVerticalLine()
                .stroke(ink.opacity(metrics.hairlineOpacity * 3),
                        style: StrokeStyle(lineWidth: metrics.timelineAxisWidth, lineCap: .round, dash: [1, 4]))
        case .lasting(let hue, let planned):
            Rectangle()
                .fill(hue.color.opacity(planned ? 0.35 : 0.85))
                .frame(width: metrics.timelineDurationWidth)
        }
    }

    @ViewBuilder
    private var marker: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        switch row {
        case .hour:
            Circle()
                .fill(colors.canvas.color)
                .overlay { Circle().strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 4), lineWidth: 1) }
                .frame(width: metrics.timelineHourMarkDiameter, height: metrics.timelineHourMarkDiameter)
        case .gap:
            EmptyView()
        case .event(let event, _):
            Circle()
                .fill(event.isPlanned ? colors.canvas.color : event.resolvedHue.color)
                .overlay {
                    if event.isPlanned {
                        Circle().strokeBorder(event.resolvedHue.color, lineWidth: 1.5)
                    }
                }
                .frame(width: metrics.timelineDotDiameter + 1, height: metrics.timelineDotDiameter + 1)
                .padding(2)
                .background(colors.canvas.color, in: .circle)
        case .now:
            Circle()
                .fill(colors.inkPrimary.color)
                .frame(width: metrics.timelineNowDotDiameter, height: metrics.timelineNowDotDiameter)
                .padding(2)
                .background(colors.canvas.color, in: .circle)
        }
    }

    // MARK: The content

    @ViewBuilder
    private var content: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        switch row {
        case .hour:
            Rectangle()
                .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                .frame(height: 0.5)
        case .gap:
            Color.clear.frame(height: 0)
        case .now:
            Rectangle()
                .fill(colors.inkPrimary.color)
                .frame(height: metrics.timelineNowLineWidth)
                .clipShape(.capsule)
        case .event(let event, _):
            SomaTimelineLink(event: event) {
                card(event)
            }
            .padding(.vertical, metrics.timelineCardSpacing)
        }
    }

    private func card(_ event: SomaTimelineEvent) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors

        return SomaTimelineRow(event: event, showsTime: false)
            .padding(metrics.timelineCardPadding)
            .background {
                let shape = RoundedRectangle(cornerRadius: metrics.timelineCardCornerRadius, style: .continuous)
                if event.isPlanned {
                    shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 2),
                                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                } else {
                    shape.fill(colors.surface.color)
                        .overlay(shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
                }
                }
    }

    // MARK: Accessibility

    private var accessibilityLabel: Text {
        switch row {
        case .now(let date): Text("Now, \(SomaDayTimelineLayout.clock(date))")
        default: Text(verbatim: "")
        }
    }
}

/// A line down the middle of its frame, for the dotted folded hours.
struct SomaVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

#Preview("Day timeline") {
    let start = Calendar.current.startOfDay(for: Date())
    func at(_ hour: Double) -> Date { start.addingTimeInterval(hour * 3600) }
    return ScrollView {
        SomaDayTimeline([
            SomaTimelineEvent(id: "sleep", time: "23:40", title: "Sleep", aspect: .sleep,
                              stats: [SomaTimelineStat(symbol: "bed.double.fill", text: "7h 12m")],
                              start: at(-0.33), end: at(7.27)),
            SomaTimelineEvent(id: "walk", time: "12:05", title: "Walk", aspect: .activity,
                              stats: [SomaTimelineStat(symbol: "timer", text: "35m")],
                              start: at(12.08), end: at(12.66)),
            SomaTimelineEvent(id: "bed", time: "23:00", title: "In bed", aspect: .sleep,
                              start: at(23), isPlanned: true),
        ], now: at(19.77))
        .padding()
    }
}
