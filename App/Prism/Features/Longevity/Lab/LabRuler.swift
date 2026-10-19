//
//  LabRuler.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A value set by sliding a ruler under a fixed needle: the value is the
/// control. Ticks every step, a longer tick and a number every whole unit
/// of `labelEvery`. VoiceOver adjusts it a step at a time.
struct LabRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 0.5
    var labelEvery = 1.0
    /// Points between two ticks.
    var spacing: CGFloat = 12

    @Environment(\.somaTheme) private var theme
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mid = width / 2
            Canvas { context, size in
                let visible = Int(width / spacing / 2) + 2
                let ink = theme.colors.inkSecondary.color
                // A canvas draws resolved text, so the role's font and
                // tracking are applied by hand rather than through somaFont.
                let role = theme.typography.caption
                let first = (value / step).rounded(.down) * step
                for index in -visible...visible {
                    let tick = first + Double(index) * step
                    guard range.contains(tick) else { continue }
                    let x = mid + CGFloat((tick - value) / step) * spacing
                    let isMajor = abs(tick / labelEvery - (tick / labelEvery).rounded()) < 0.001
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: isMajor ? size.height * 0.45 : size.height * 0.25))
                    context.stroke(line, with: .color(ink.opacity(isMajor ? 0.8 : 0.4)), lineWidth: 1)
                    if isMajor {
                        let label = Text(verbatim: LabMath.format(tick, decimals: labelEvery < 1 ? 1 : 0) ?? "")
                            .font(role.font)
                            .tracking(role.tracking)
                            .foregroundStyle(ink)
                        context.draw(label, at: CGPoint(x: x, y: size.height * 0.75))
                    }
                }
                var needle = Path()
                needle.move(to: CGPoint(x: mid, y: 0))
                needle.addLine(to: CGPoint(x: mid, y: size.height * 0.55))
                context.stroke(needle, with: .color(theme.colors.inkPrimary.color), lineWidth: 2)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let moved = start - Double(drag.translation.width / spacing) * step
                        value = min(max((moved / step).rounded() * step, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: theme.metrics.minimumTapTarget + 16)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(Text("Ruler"))
        .accessibilityValue(Text(LabMath.format(value, decimals: 1) ?? ""))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}
