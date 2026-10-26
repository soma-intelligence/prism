//
//  SomaDayPlan.swift
//  SomaUI
//

import SwiftUI

/// One moment of the day: something that happened, or something your readings
/// suggest, at its clock time.
public struct SomaPlanItem: Identifiable, Equatable, Sendable {
    public enum State: Sendable, Equatable {
        /// Already happened.
        case done
        /// The next thing coming up.
        case next
        /// Later today.
        case later
    }

    public let id: String
    public let title: String
    public let detail: String?
    public let state: State
    public let start: Date
    /// Where the moment lasts, such as a workout or the focus window. Nil
    /// draws a tick on the track instead of a span.
    public let end: Date?

    public init(id: String, title: String, detail: String?, state: State, start: Date, end: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.start = start
        self.end = end
    }
}

/// The day as Flighty draws a flight: one track from morning to midnight with
/// what lasts as spans, single moments as ticks and a line at the present, and
/// under it the same moments as rows, each with its clock time.
public struct SomaDayPlan: View {
    private let items: [SomaPlanItem]
    private let now: Date
    private let calendar: Calendar
    private let showsTrack: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - now: the present, which the track marks and which decides what is
    ///     done.
    ///   - showsTrack: false draws the rows alone.
    public init(_ items: [SomaPlanItem], now: Date, calendar: Calendar = .current, showsTrack: Bool = true) {
        self.items = items.sorted { $0.start < $1.start }
        self.now = now
        self.calendar = calendar
        self.showsTrack = showsTrack
    }

    public var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            if showsTrack {
                PlanTrack(items: items, now: now, calendar: calendar)
            }
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PlanRow(item: item, calendar: calendar)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                                .frame(height: 0.5)
                                .padding(.leading, metrics.cardPadding + metrics.planTimeWidth)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                        .fill(theme.colors.surface.color)
                )
            }
        }
    }
}

/// The track from six in the morning to midnight.
private struct PlanTrack: View {
    let items: [SomaPlanItem]
    let now: Date
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let type = theme.typography
        let day = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .hour, value: 6, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let length = end.timeIntervalSince(start)
        let hours = [6, 12, 18, 24].compactMap { calendar.date(byAdding: .hour, value: $0, to: day) }
        let items = items
        let now = now

        VStack(spacing: 4) {
            Canvas { context, size in
                func x(_ date: Date) -> CGFloat {
                    size.width * CGFloat(min(1, max(0, date.timeIntervalSince(start) / length)))
                }
                let mid = size.height / 2
                let track = metrics.planTrackHeight
                let bar = CGRect(x: 0, y: mid - track / 2, width: size.width, height: track)
                context.fill(Path(roundedRect: bar, cornerRadius: track / 2), with: .color(colors.surfaceRecessed.color))

                for item in items {
                    let ink = item.state == .done ? colors.inkSecondary.color : colors.inkPrimary.color
                    if let finish = item.end, finish > item.start {
                        let from = x(item.start)
                        let rect = CGRect(x: from, y: mid - track / 2, width: max(track, x(finish) - from), height: track)
                        context.fill(Path(roundedRect: rect, cornerRadius: track / 2), with: .color(ink))
                    } else {
                        let tick = CGRect(x: x(item.start) - 1, y: mid - metrics.planTickHeight / 2,
                                          width: 2, height: metrics.planTickHeight)
                        context.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(ink))
                    }
                }

                let nowX = x(now)
                var line = Path()
                line.move(to: CGPoint(x: nowX, y: mid - metrics.planNowHeight / 2))
                line.addLine(to: CGPoint(x: nowX, y: mid + metrics.planNowHeight / 2))
                context.stroke(line, with: .color(colors.inkPrimary.color), lineWidth: 1.5)
                let dot = metrics.timelineNowDotDiameter
                context.fill(Path(ellipseIn: CGRect(x: nowX - dot / 2, y: mid - metrics.planNowHeight / 2 - dot / 2,
                                                     width: dot, height: dot)),
                             with: .color(colors.inkPrimary.color))
            }
            .frame(height: metrics.planNowHeight + metrics.timelineNowDotDiameter)

            HStack {
                ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                    if index > 0 { Spacer() }
                    // The person's own clock: 18:00, or 6 PM.
                    Text(hour.formatted(.dateTime.hour()))
                }
            }
            .somaFont(type.captionValue)
            .foregroundStyle(colors.inkSecondary.color)
        }
        .accessibilityHidden(true)
    }
}

private struct PlanRow: View {
    let item: SomaPlanItem
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let type = theme.typography

        HStack(alignment: .center, spacing: 0) {
            Text(item.start.formatted(date: .omitted, time: .shortened))
                .somaFont(type.captionValue)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize()
                .frame(minWidth: metrics.planTimeWidth, alignment: .leading)
                .padding(.trailing, metrics.cardHeaderSpacing)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .somaFont(type.body)
                    .foregroundStyle(item.state == .done ? colors.inkSecondary.color : colors.inkPrimary.color)
                if let detail = item.detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: metrics.cardSpacing)
            switch item.state {
            case .done:
                Text("Done").somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
            case .next:
                Text("Next").somaFont(type.eyebrow).foregroundStyle(colors.inkPrimary.color)
            case .later:
                EmptyView()
            }
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .frame(minHeight: metrics.minimumTapTarget)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Day plan") {
    let day = Calendar.current.startOfDay(for: .now)
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? day
    }
    return ZStack {
        SomaPreviewBackdrop()
        SomaDayPlan([
            SomaPlanItem(id: "wake", title: "Woke up", detail: "7 h 12 asleep", state: .done, start: at(7, 21)),
            SomaPlanItem(id: "focus", title: "Focus window", detail: "Alertness peaks until 13:00", state: .next,
                         start: at(10, 30), end: at(13)),
            SomaPlanItem(id: "coffee", title: "Last coffee", detail: "Keeps caffeine low by bedtime", state: .later, start: at(14)),
            SomaPlanItem(id: "bed", title: "In bed", detail: "Gives you the 7 h 40 you need", state: .later, start: at(23, 15)),
        ], now: at(7, 42))
        .padding(16)
    }
}
