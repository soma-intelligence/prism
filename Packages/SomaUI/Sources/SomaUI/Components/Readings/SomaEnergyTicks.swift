//
//  SomaEnergyTicks.swift
//  SomaUI
//

import SwiftUI

/// The energy bank as a battery of thin ticks: the ticks below today's level
/// in ink, the level itself in the accent, the rest recessed.
///
/// With no level every tick is recessed. An empty battery would say zero, and
/// zero is a value; this says there is none yet.
public struct SomaEnergyTicks: View {
    private let level: Double?

    @Environment(\.somaTheme) private var theme

    /// - Parameter level: the share of the bank that is full, in 0...1, or
    ///   nil when there is no level to show.
    public init(level: Double?) {
        self.level = level
    }

    public var body: some View {
        let count = theme.metrics.energyTickCount
        let lit = level.map { max(1, min(count, Int(($0 * Double(count)).rounded()))) }

        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 { Spacer(minLength: 1) }
                Capsule()
                    .fill(fill(for: index, lit: lit))
                    .frame(width: theme.metrics.energyTickWidth, height: theme.metrics.energyTickHeight)
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(for index: Int, lit: Int?) -> Color {
        guard let lit else {
            return theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)
        }
        if index < lit - 1 {
            return theme.colors.inkPrimary.color.opacity(theme.metrics.energyFullOpacity)
        }
        if index == lit - 1 {
            return theme.colors.accent.color
        }
        return theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)
    }
}

#Preview("Energy ticks") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaEnergyTicks(level: 0.42)
            SomaEnergyTicks(level: nil)
        }
        .padding()
    }
}
