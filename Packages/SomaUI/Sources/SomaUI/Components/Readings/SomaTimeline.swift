//
//  SomaTimeline.swift
//  SomaUI
//

import SwiftUI

/// One number on an event's stats line, with the glyph that names it.
public struct SomaTimelineStat: Hashable, Sendable {
    public var symbol: String
    public var text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }
}

/// One thing that happened, placed on the day.
///
/// Two events compare by their fields and by their destinations' values.
public struct SomaTimelineEvent: Identifiable, Sendable, Equatable {
    public let id: String
    /// The clock time, already formatted: 07:16.
    public var time: String
    /// What happened: Woke up, Walk, Stress peak.
    public var title: String
    /// The numbers behind it, in one sentence. Shown when there are no stats.
    public var detail: String?
    /// The aspect the event belongs to, which colours it when no hue is given.
    public var aspect: SomaAspect?
    /// Whether this is the present moment. The short list leaves it out; the
    /// full day draws its own line on now.
    public var isNow: Bool
    /// The event's colour, over the aspect's: violet for a log, which has no
    /// aspect of its own.
    public var hue: SomaHealthHue?
    /// The SF Symbol in the event's circle. Nil takes the hue's own.
    public var symbol: String?
    /// The numbers behind it, each with its glyph: one short line.
    public var stats: [SomaTimelineStat]
    /// When it began and, for something that lasts, when it ended. The full
    /// day places events by these and skips one without a start.
    public var start: Date?
    public var end: Date?
    /// Something still to come: drawn as an outline, not a filled card.
    public var isPlanned: Bool
    /// Where tapping the event goes: a route value the host's navigation stack
    /// registers with `navigationDestination(for:)`. Nil leaves the event a
    /// plain row, with no chevron.
    public var destination: (any Hashable & Sendable)?

    public init(
        id: String,
        time: String,
        title: String,
        detail: String? = nil,
        aspect: SomaAspect? = nil,
        isNow: Bool = false,
        hue: SomaHealthHue? = nil,
        symbol: String? = nil,
        stats: [SomaTimelineStat] = [],
        start: Date? = nil,
        end: Date? = nil,
        isPlanned: Bool = false,
        destination: (any Hashable & Sendable)? = nil
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.detail = detail
        self.aspect = aspect
        self.isNow = isNow
        self.hue = hue
        self.symbol = symbol
        self.stats = stats
        self.start = start
        self.end = end
        self.isPlanned = isPlanned
        self.destination = destination
    }

    public static func == (lhs: SomaTimelineEvent, rhs: SomaTimelineEvent) -> Bool {
        lhs.id == rhs.id && lhs.time == rhs.time && lhs.title == rhs.title && lhs.detail == rhs.detail
            && lhs.aspect == rhs.aspect && lhs.isNow == rhs.isNow && lhs.hue == rhs.hue && lhs.symbol == rhs.symbol
            && lhs.stats == rhs.stats && lhs.start == rhs.start && lhs.end == rhs.end && lhs.isPlanned == rhs.isPlanned
            && lhs.destination.map { AnyHashable($0) } == rhs.destination.map { AnyHashable($0) }
    }

    /// The colour the event wears: its hue, else its aspect's, else a log's violet.
    public var resolvedHue: SomaHealthHue {
        if let hue { return hue }
        switch aspect {
        case .sleep: return .sleep
        case .activity: return .activity
        case .mind: return .mind
        case .gut: return .nutrition
        case .heart: return .heart
        case .body: return .body
        case nil: return .symptoms
        }
    }

    /// The glyph in the event's circle.
    public var resolvedSymbol: String {
        if let symbol { return symbol }
        switch resolvedHue {
        case .sleep: return "moon.stars.fill"
        case .activity, .mobility: return "figure.walk"
        case .mind: return "brain.head.profile.fill"
        case .nutrition: return "fork.knife"
        case .heart, .vitals: return "heart.fill"
        case .body: return "figure"
        case .respiratory: return "lungs.fill"
        case .medications: return "pills.fill"
        default: return "square.and.pencil"
        }
    }

    /// Whether it lasts long enough to draw as a span on the full day.
    var lasts: Bool {
        guard let start, let end else { return false }
        return end.timeIntervalSince(start) >= 60
    }
}

/// The day so far, as a card shows it: the last three events, newest first,
/// each a coloured glyph, its time, its title and one line of numbers, and a
/// pill under them that reads as the way into the full day.
///
/// The pill is a label, not a button: the card around the list is the link.
public struct SomaTimeline: View {
    private let events: [SomaTimelineEvent]
    private let limit: Int

    @Environment(\.somaTheme) private var theme

    public init(_ events: [SomaTimelineEvent], limit: Int = 3) {
        self.events = events
        self.limit = limit
    }

    private var shown: [SomaTimelineEvent] {
        Array(events.filter { !$0.isNow }.suffix(limit).reversed())
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let rows = shown

        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("Nothing yet today.")
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.vertical, metrics.timelineListRowPadding)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                if index > 0 {
                    Rectangle()
                        .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: 0.5)
                        .padding(.leading, metrics.timelineGlyphDiameter + metrics.timelineGlyphGap)
                        .accessibilityHidden(true)
                }
                SomaTimelineLink(event: event) {
                    SomaTimelineRow(event: event, showsTime: true)
                        .padding(.vertical, metrics.timelineListRowPadding)
                }
            }

            Text("View timeline")
                .somaFont(theme.typography.callout)
                .fontWeight(.medium)
                .foregroundStyle(colors.inkPrimary.color)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.timelinePillHeight)
                .background(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 0.6), in: .capsule)
                .padding(.top, metrics.cardSpacing)
        }
    }
}

/// One event: the glyph circle, then the time, the title and the stats line.
struct SomaTimelineRow: View {
    let event: SomaTimelineEvent
    /// The short list prints the time over the title; the full day prints it
    /// on the axis instead.
    let showsTime: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .center, spacing: metrics.timelineGlyphGap) {
            SomaTimelineGlyph(event: event)

            VStack(alignment: .leading, spacing: 2) {
                if showsTime {
                    Text(event.time)
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Text(event.title)
                    .somaFont(type.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(event.isPlanned ? colors.inkSecondary.color : colors.inkPrimary.color)
                    .lineLimit(1)
                SomaTimelineStats(event: event)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if event.destination != nil {
                Image(systemName: "chevron.right")
                    .somaFont(type.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.inkSecondary.color.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(event.time), \(event.title)"))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(event.destination == nil ? [] : .isLink)
    }

    private var accessibilityValue: String {
        if !event.stats.isEmpty { return event.stats.map(\.text).joined(separator: ", ") }
        return event.detail ?? ""
    }
}

/// The event as a link to its destination, pressed with the glass press
/// style; a plain view when it has none.
struct SomaTimelineLink<Label: View>: View {
    let event: SomaTimelineEvent
    @ViewBuilder let label: Label

    var body: some View {
        if let destination = event.destination {
            link(destination)
        } else {
            label
        }
    }

    /// Opens the existential so `NavigationLink(value:)` sees a concrete type.
    private func link<Route: Hashable>(_ route: Route) -> AnyView {
        AnyView(
            NavigationLink(value: route) {
                label.contentShape(.rect)
            }
            .buttonStyle(.somaGlassPress)
        )
    }
}

/// The event's glyph on a wash of its hue, or on a ring of it when the event
/// is still to come.
struct SomaTimelineGlyph: View {
    let event: SomaTimelineEvent

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let side = theme.metrics.timelineGlyphDiameter
        let hue = event.resolvedHue.color

        Image(systemName: event.resolvedSymbol)
            .somaFont(theme.typography.callout)
            .fontWeight(.semibold)
            .foregroundStyle(hue)
            .frame(width: side, height: side)
            .background {
                if event.isPlanned {
                    Circle().strokeBorder(hue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    Circle().fill(hue.opacity(0.16))
                }
            }
            .accessibilityHidden(true)
    }
}

/// The event's one line of numbers: each stat's glyph in the event's hue, the
/// number in the secondary ink. Falls back to the event's sentence.
struct SomaTimelineStats: View {
    let event: SomaTimelineEvent

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors

        if !event.stats.isEmpty {
            HStack(spacing: theme.metrics.timelineStatSpacing) {
                ForEach(event.stats, id: \.self) { stat in
                    HStack(spacing: theme.metrics.spaceXS) {
                        Image(systemName: stat.symbol)
                            .imageScale(.small)
                            .foregroundStyle(event.resolvedHue.color.opacity(event.isPlanned ? 0.6 : 1))
                        Text(stat.text)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }
            .somaFont(theme.typography.captionValue)
            .lineLimit(1)
        } else if let detail = event.detail {
            Text(detail)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Timeline") {
    ZStack {
        SomaPreviewBackdrop()
        SomaCard {
            SomaTimeline([
                SomaTimelineEvent(id: "wake", time: "07:16", title: "Woke up", aspect: .sleep,
                                  stats: [SomaTimelineStat(symbol: "bed.double.fill", text: "7h 12m")]),
                SomaTimelineEvent(id: "walk", time: "12:05", title: "Walk", aspect: .activity,
                                  stats: [SomaTimelineStat(symbol: "timer", text: "35m"),
                                          SomaTimelineStat(symbol: "shoeprints.fill", text: "3,900")]),
                SomaTimelineEvent(id: "peak", time: "14:30", title: "Stress peak", detail: "104 bpm while still.", aspect: .mind),
            ])
        }
        .padding()
    }
}
