//
//  SomaMoon.swift
//  SomaUI
//

import SwiftUI

/// A moon lit from the right: a rating that fills the way a moon waxes, from
/// a thin crescent to full.
public struct SomaMoon: View {
    private let lit: Double
    private let aspect: SomaAspect
    private let glows: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - lit: the share lit, 0 new to 1 full.
    ///   - aspect: whose hue the light wears.
    ///   - glows: a halo round it, for the one big moon on a screen.
    public init(lit: Double, aspect: SomaAspect = .sleep, glows: Bool = false) {
        self.lit = min(max(lit, 0), 1)
        self.aspect = aspect
        self.glows = glows
    }

    public var body: some View {
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color

        ZStack {
            if glows {
                Circle()
                    .fill(hue.opacity(0.3))
                    .scaleEffect(1.25)
                    .blur(radius: theme.metrics.glowRadius)
            }
            Circle().fill(colors.surfaceRecessed.color)
            SomaMoonLight(lit: lit)
                .fill(LinearGradient(colors: [hue, hue.opacity(0.7)], startPoint: .topTrailing, endPoint: .bottomLeading))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The lit part of a moon: the right limb and the terminator, an ellipse
/// whose width follows the phase.
public struct SomaMoonLight: Shape {
    var lit: Double

    public init(lit: Double) { self.lit = lit }

    public var animatableData: Double {
        get { lit }
        set { lit = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard lit > 0.001 else { return Path() }
        let bulge = CGFloat(1 - 2 * lit) * radius
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
        path.addArc(center: centre, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        let steps = 48
        for index in 0...steps {
            let theta = Double.pi / 2 - Double.pi * Double(index) / Double(steps)
            path.addLine(to: CGPoint(x: centre.x + bulge * CGFloat(cos(theta)), y: centre.y + radius * CGFloat(sin(theta))))
        }
        path.closeSubpath()
        return path
    }
}

/// A row of moons, one a step, each more lit than the last: tap one to rate.
public struct SomaMoonScale: View {
    @Binding private var value: Int?
    private let count: Int
    private let aspect: SomaAspect
    private let low: String
    private let high: String

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - value: 1...count, or nil until chosen.
    ///   - low: the word under the first moon.
    ///   - high: the word under the last.
    public init(value: Binding<Int?>, count: Int = 10, aspect: SomaAspect = .sleep, low: String, high: String) {
        self._value = value
        self.count = max(2, count)
        self.aspect = aspect
        self.low = low
        self.high = high
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(spacing: metrics.cardSpacing) {
            HStack(spacing: 0) {
                ForEach(1...count, id: \.self) { step in
                    Button {
                        value = step
                    } label: {
                        SomaMoon(lit: Double(step) / Double(count), aspect: aspect)
                            .frame(width: metrics.moonRowDiameter, height: metrics.moonRowDiameter)
                            .padding(metrics.scoreLabelSpacing * 2)
                            .overlay {
                                if value == step {
                                    Circle().strokeBorder(colors.accent.color, lineWidth: 1.5)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPress)
                    .accessibilityLabel(Text("\(step) of \(count)"))
                    .accessibilityAddTraits(value == step ? .isSelected : [])
                }
            }
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .somaFont(theme.typography.tabLabel)
            .foregroundStyle(colors.inkSecondary.color)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}

#Preview("Moon") {
    @Previewable @State var rating: Int? = 7
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaMoon(lit: Double(rating ?? 0) / 10, glows: true).frame(width: 180)
            SomaMoonScale(value: $rating, low: "Drained", high: "Fully rested")
        }
        .padding()
    }
}
