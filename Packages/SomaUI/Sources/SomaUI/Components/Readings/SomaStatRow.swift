//
//  SomaStatRow.swift
//  SomaUI
//

import SwiftUI

/// One value in a row of stats: what it is, the number, and a mark when it
/// rose or fell. The same reading as ``SomaScore``, named by its own label
/// rather than by an aspect: fitness age, lean mass, HRV.
public struct SomaStat: Identifiable, Sendable {
    public var id: String { label.key }
    /// Set in small capitals over the number.
    public var label: LocalizedStringResource
    /// The number as it should read, or nil for a dash: not measured is not
    /// zero.
    public var value: String?
    /// What the number counts, set small beside it.
    public var unit: LocalizedStringResource?
    /// Nil when it held steady, or when there is nothing to compare it with.
    public var trend: SomaTrend?
    /// A few words on what the value means, set under it. Never a sentence.
    public var cue: LocalizedStringResource?
    public var cueTone: SomaCueTone

    public init(
        _ label: LocalizedStringResource,
        value: String?,
        unit: LocalizedStringResource? = nil,
        trend: SomaTrend? = nil,
        cue: LocalizedStringResource? = nil,
        cueTone: SomaCueTone = .neutral
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.trend = trend
        self.cue = cue
        self.cueTone = cueTone
    }
}

/// Three values side by side, each taking an equal share of the width: the row
/// under a tab part's headline.
///
/// Laid out exactly as ``SomaScoreRow``, so a part's stats and the Today page's
/// scores read as one family. It carries no hairline: under a headline the
/// space above already separates it.
public struct SomaStatRow: View {
    private let stats: [SomaStat]
    private let onSelect: ((SomaStat) -> Void)?

    /// - Parameter onSelect: when set, each stat is a button that opens its
    ///   detail.
    public init(_ stats: [SomaStat], onSelect: ((SomaStat) -> Void)? = nil) {
        self.stats = stats
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stats) { stat in
                let view = SomaStatView(
                    label: stat.label, value: stat.value, unit: stat.unit, trend: stat.trend,
                    cue: stat.cue, cueTone: stat.cueTone
                )
                .frame(maxWidth: .infinity)
                if let onSelect {
                    Button { onSelect(stat) } label: { view.contentShape(.rect) }
                        .buttonStyle(.somaGlassPress)
                } else {
                    view
                }
            }
        }
    }
}

/// The label, number and mark that ``SomaScoreRow`` and ``SomaStatRow`` share.
struct SomaStatView: View {
    let label: LocalizedStringResource
    let value: String?
    let unit: LocalizedStringResource?
    let trend: SomaTrend?
    var cue: LocalizedStringResource? = nil
    var cueTone: SomaCueTone = .neutral

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(spacing: metrics.scoreLabelSpacing) {
            Text(label)
                .somaFont(type.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .center, spacing: metrics.trendMarkSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.trendMarkSpacing) {
                    Text(value ?? "-")
                        .somaFont(type.metric)
                        .foregroundStyle(colors.inkPrimary.color)
                    if let unit, value != nil {
                        Text(unit)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                if let trend, value != nil {
                    SomaTrendMark(trend: trend)
                }
            }

            if let cue, value != nil {
                Text(cue)
                    .somaFont(type.caption)
                    .foregroundStyle(cueTone.color(colors))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        guard let value else { return Text("Not measured") }
        let unit = unit.map { Text($0) } ?? Text(verbatim: "")
        let read: Text = switch trend {
        case .up: Text("\(value) \(unit), rising")
        case .down: Text("\(value) \(unit), falling")
        case nil: Text("\(value) \(unit)")
        }
        guard let cue else { return read }
        return Text("\(read), \(Text(cue))")
    }
}

#Preview("Stat row") {
    ZStack {
        SomaPreviewBackdrop()
        SomaStatRow([
            SomaStat("Fitness age", value: "41", trend: .down),
            SomaStat("Lean mass", value: "53.6", trend: .up),
            SomaStat("VO2 max", value: nil),
        ])
        .padding()
    }
}
