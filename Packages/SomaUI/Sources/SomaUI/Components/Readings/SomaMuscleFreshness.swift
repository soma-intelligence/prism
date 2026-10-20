//
//  SomaMuscleFreshness.swift
//  SomaUI
//

import SwiftUI

/// One muscle group read off the last month of sessions: how rested it is,
/// when it last worked, and when it should read rested again.
public struct SomaMuscleReading: Sendable, Equatable, Identifiable {
    public let group: SomaMuscleGroup
    public let state: SomaMuscleState
    /// The end of the last session that worked it; nil when none did.
    public let lastWorked: Date?
    /// When it should read rested again; nil when it already does.
    public let freshAt: Date?

    public var id: SomaMuscleGroup { group }

    public init(group: SomaMuscleGroup, state: SomaMuscleState, lastWorked: Date? = nil, freshAt: Date? = nil) {
        self.group = group
        self.state = state
        self.lastWorked = lastWorked
        self.freshAt = freshAt
    }
}

/// Muscle freshness as one card: the body front and back in calm tones, the
/// three states as a legend that counts them, and the six groups as pills.
///
/// Tap a muscle on the figure, or a pill, and that group comes forward on
/// the figure while the line under the pills says when it last worked and
/// when it is fresh again. Tap it again to let go.
public struct SomaMuscleFreshness: View {
    private let readings: [SomaMuscleReading]
    private let now: Date

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: SomaMuscleGroup?

    public init(_ readings: [SomaMuscleReading], now: Date = .now) {
        self.readings = readings
        self.now = now
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let chosen = selected.flatMap(reading(for:))

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Muscle freshness")
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(Self.summary(readings))
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }

            SomaMuscleMap(states, highlight: selected?.muscles) { muscle in
                choose(muscle.map(SomaMuscleGroup.of))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.cardSpacing / 2)

            HStack(spacing: metrics.muscleLegendSpacing) {
                ForEach([SomaMuscleState.recovered, .fatigued, .depleted], id: \.self) { state in
                    SomaMuscleLegendItem(state: state, count: readings.filter { $0.state == state }.count)
                }
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: metrics.musclePillSpacing), count: 3),
                spacing: metrics.musclePillSpacing
            ) {
                ForEach(SomaMuscleGroup.allCases) { group in
                    SomaMuscleGroupPill(reading: reading(for: group) ?? SomaMuscleReading(group: group, state: .none),
                                        isSelected: selected == group) {
                        choose(group)
                    }
                }
            }

            if let chosen {
                SomaMuscleDetailLine(reading: chosen, now: now)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                    .id(chosen.group)
            }
        }
        .padding(metrics.cardPadding)
        .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var states: [SomaMuscle: SomaMuscleState] {
        var result: [SomaMuscle: SomaMuscleState] = [:]
        for muscle in SomaMuscle.allCases {
            result[muscle] = reading(for: SomaMuscleGroup.of(muscle))?.state ?? SomaMuscleState.none
        }
        return result
    }

    private func reading(for group: SomaMuscleGroup) -> SomaMuscleReading? {
        readings.first { $0.group == group }
    }

    private func choose(_ group: SomaMuscleGroup?) {
        withAnimation(reduceMotion ? nil : theme.motion.selection) {
            selected = group == selected ? nil : group
        }
    }

    /// The card's one line: how many groups are rested, or what is missing.
    nonisolated static func summary(_ readings: [SomaMuscleReading]) -> LocalizedStringResource {
        let read = readings.filter { $0.state != .none }
        guard !read.isEmpty else { return "No workouts yet" }
        let rested = read.filter { $0.state == .recovered }.count
        if rested == read.count { return "All rested" }
        return "\(rested) of \(read.count) rested"
    }
}

/// A state in the legend: its dot, its word, and how many groups are in it.
private struct SomaMuscleLegendItem: View {
    let state: SomaMuscleState
    let count: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        HStack(spacing: theme.metrics.identityDotSpacing) {
            Circle()
                .fill(state.tone?.color ?? colors.inkSecondary.color)
                .frame(width: theme.metrics.muscleLegendDot, height: theme.metrics.muscleLegendDot)
            Text(state.title)
                .foregroundStyle(colors.inkPrimary.color)
            Text(verbatim: "\(count)")
                .foregroundStyle(colors.inkSecondary.color)
        }
        .somaFont(theme.typography.caption)
        .accessibilityElement(children: .combine)
    }
}

/// A group as a pill: its tone and its name; the legend above says what
/// the tone means. The selected one takes a tonal step and a hairline in its
/// tone.
private struct SomaMuscleGroupPill: View {
    let reading: SomaMuscleReading
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let tone = reading.state.tone?.color
        let shape = Capsule(style: .continuous)

        Button(action: action) {
            HStack(spacing: metrics.identityDotSpacing) {
                Circle()
                    .fill(tone ?? colors.inkSecondary.color.opacity(0.4))
                    .frame(width: metrics.muscleLegendDot, height: metrics.muscleLegendDot)
                Text(reading.group.title)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, metrics.musclePillPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.musclePillHeight)
            .background(shape.fill(isSelected ? (tone ?? colors.inkSecondary.color).opacity(metrics.musclePillSelectedTint) : colors.surfaceRecessed.color))
            .overlay(shape.strokeBorder((tone ?? colors.inkSecondary.color).opacity(isSelected ? 0.6 : 0), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(reading.group.title))
        .accessibilityValue(Text(reading.state.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The chosen group in one line: when it last worked and when it is fresh.
private struct SomaMuscleDetailLine: View {
    let reading: SomaMuscleReading
    let now: Date

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.identityDotSpacing) {
                Text(reading.group.title)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(reading.state.title)
                    .foregroundStyle(reading.state.tone?.color ?? colors.inkSecondary.color)
            }
            .somaFont(theme.typography.callout)
            Text(Self.line(reading, now: now))
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    /// "Worked 2 days ago, fresh in about 20 hours".
    static func line(_ reading: SomaMuscleReading, now: Date) -> LocalizedStringResource {
        guard let worked = reading.lastWorked else { return "No sessions in 30 days" }
        let ago = SomaMuscleTime.ago(now.timeIntervalSince(worked))
        guard let fresh = reading.freshAt, fresh > now else { return "Worked \(ago)" }
        return "Worked \(ago), fresh in \(SomaMuscleTime.span(fresh.timeIntervalSince(now)))"
    }
}

/// Spans of time in the few words the freshness card uses.
enum SomaMuscleTime {
    /// "today", "yesterday", "3 days ago".
    static func ago(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3_600
        if hours < 12 { return String(localized: "today") }
        let days = Int((hours / 24).rounded())
        if days <= 1 { return String(localized: "yesterday") }
        return String(localized: "\(days) days ago")
    }

    /// "about 6 hours", "about a day", "about 2 days".
    static func span(_ seconds: TimeInterval) -> String {
        let hours = Int((seconds / 3_600).rounded(.up))
        if hours < 20 { return String(localized: "about \(max(hours, 1)) hours") }
        let days = Int((Double(hours) / 24).rounded())
        if days <= 1 { return String(localized: "about a day") }
        return String(localized: "about \(days) days")
    }
}

#Preview("Muscle freshness") {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    ZStack {
        SomaPreviewBackdrop()
        SomaMuscleFreshness([
            SomaMuscleReading(group: .chest, state: .recovered, lastWorked: now.addingTimeInterval(-4 * 86_400)),
            SomaMuscleReading(group: .shoulders, state: .recovered, lastWorked: now.addingTimeInterval(-4 * 86_400)),
            SomaMuscleReading(group: .arms, state: .fatigued, lastWorked: now.addingTimeInterval(-30 * 3_600), freshAt: now.addingTimeInterval(14 * 3_600)),
            SomaMuscleReading(group: .core, state: .recovered, lastWorked: now.addingTimeInterval(-3 * 86_400)),
            SomaMuscleReading(group: .back, state: .none),
            SomaMuscleReading(group: .legs, state: .depleted, lastWorked: now.addingTimeInterval(-5 * 3_600), freshAt: now.addingTimeInterval(52 * 3_600)),
        ], now: now)
        .padding()
    }
}
