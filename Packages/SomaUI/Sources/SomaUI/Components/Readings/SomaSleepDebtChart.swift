//
//  SomaSleepDebtChart.swift
//  SomaUI
//

import SwiftUI

/// Sleep debt over the last nights, the earlier app's well redrawn in the
/// house style: the debt carried each night as one line rising from zero, a
/// ring on last night's, and under it each night's own shortfall as a thin
/// bar, up for a night short of the need and down for a night over it.
///
/// A night with no record is a gap in both: the line breaks and no bar
/// stands there. With nothing recorded the grid still stands, empty.
public struct SomaSleepDebtChart: View {
    private let debt: [Double?]
    private let shortfall: [Double?]
    private let labels: [String]

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - debt: the debt carried each night, in hours, oldest first.
    ///   - shortfall: each night's need less its sleep, in hours, the same
    ///     nights: above zero a night short, below zero a night over.
    ///   - labels: spread under the plot, oldest first.
    public init(debt: [Double?], shortfall: [Double?], labels: [String] = []) {
        self.debt = debt
        self.shortfall = shortfall
        self.labels = labels
    }

    /// The scale both marks share: round hours, zero always on it so the bars
    /// stand on a line and the debt rises from it. Nil with nothing to draw.
    public nonisolated static func scale(debt: [Double?], shortfall: [Double?]) -> SomaPlotScale? {
        let values = debt.compactMap { $0 } + shortfall.compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return SomaPlotScale(values: values, fromZero: true, desired: 3)
    }

    public var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[.sleep].identity.color
        let debt = debt
        let shortfall = shortfall
        let count = max(debt.count, shortfall.count)

        VStack(alignment: .leading, spacing: metrics.spaceS) {
            SomaPlot(scale: Self.scale(debt: debt, shortfall: shortfall), xLabels: labels,
                     label: { "\($0.formatted(.number.precision(.fractionLength(0...1))))h" }) { context, space, pen in
                let pitch = space.pitch(count)
                let zero = space.y(0)
                for (index, value) in shortfall.enumerated() {
                    guard let value, value != 0 else { continue }
                    let x = space.slot(index, of: count)
                    let y = space.y(value)
                    pen.span(context, x: x, top: min(y, zero), bottom: max(y, zero), pitch: pitch,
                             color: pen.inkSecondary.opacity(pen.contextOpacity))
                }
                let line: [CGPoint?] = debt.enumerated().map { index, value in
                    value.map { CGPoint(x: space.slot(index, of: count), y: space.y($0)) }
                }
                pen.line(context, line, color: hue)
                if let last = line.last ?? nil {
                    pen.ring(context, at: last, color: hue)
                }
            }
            HStack(spacing: metrics.cardSpacing) {
                legend("Debt carried") {
                    Capsule().fill(hue)
                        .frame(width: metrics.sleepDebtLegendLine, height: metrics.chartStroke)
                }
                legend("Each night, short or over") {
                    Capsule().fill(theme.colors.inkSecondary.color.opacity(metrics.chartContextBarOpacity))
                        .frame(width: metrics.chartThinBarWidth, height: metrics.sleepDebtLegendLine)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep debt each night"))
        .accessibilityValue(Text((debt.last ?? nil).map { SomaFormat.duration($0 * 3600) } ?? SomaFormat.notMeasured))
    }

    private func legend(_ title: LocalizedStringResource, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: theme.metrics.spaceXS) {
            mark()
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .lineLimit(1)
        }
    }
}

#Preview("Sleep debt chart") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: SomaMetrics.standard.cardSpacing) {
            SomaCard {
                SomaSleepDebtChart(debt: [1.2, 1.6, 2.4, nil, 2.1, 2.9, 3.4, 3.0, 2.2, 2.6, 3.1, 2.8, 2.0, 1.7],
                                   shortfall: [0.4, 0.4, 0.8, nil, -0.3, 0.8, 0.5, -0.4, -0.8, 0.4, 0.5, -0.3, -0.8, -0.3],
                                   labels: ["14 nights ago", "Last night"])
            }
            SomaCard { SomaSleepDebtChart(debt: [], shortfall: []) }
        }
        .padding()
    }
}
