//
//  SomaMoon.swift
//  SomaUI
//

import SwiftUI

/// A moon lit from the right: a rating that fills the way a moon waxes, from
/// a thin crescent to full.
///
/// Drawn as the moon itself rather than a coloured disc: chalky highlands,
/// the darker seas where they really lie, a limb that dims towards the edge,
/// and a soft terminator between day and night. The night side keeps a
/// little earthshine so the whole disc always reads.
public struct SomaMoon: View {
    private let lit: Double
    private let aspect: SomaAspect
    private let glows: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - lit: the share lit, 0 new to 1 full.
    ///   - aspect: kept for callers; the moon wears its own greys.
    ///   - glows: kept for callers; the moon carries no halo.
    public init(lit: Double, aspect: SomaAspect = .sleep, glows: Bool = false) {
        self.lit = min(max(lit, 0), 1)
        self.aspect = aspect
        self.glows = glows
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let day = colors.moonLit.color
        let mare = colors.moonMare.color
        let night = colors.moonNight.color
        let shine = metrics.moonEarthshine
        let softness = metrics.moonTerminatorSoftness
        let phase = lit
        let edge = colors.inkPrimary.color

        Canvas { context, size in
            let side = min(size.width, size.height)
            let disc = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let round = Path(ellipseIn: disc)
            context.clip(to: round)

            // Night: the whole disc in earthshine, its seas just showing.
            context.fill(round, with: .color(night))
            context.drawLayer { layer in
                layer.opacity = shine * 2
                Self.surface(in: &layer, disc: disc, mare: mare, light: day, showsCraters: false)
            }

            // Day: the lit face, cut by a softened terminator.
            if phase > 0.001 {
                context.drawLayer { layer in
                    layer.fill(round, with: .color(day))
                    Self.surface(in: &layer, disc: disc, mare: mare, light: day)
                    // The limb dims: the face turns away towards its edge.
                    layer.fill(round, with: .radialGradient(
                        Gradient(stops: [
                            .init(color: mare.opacity(0), location: 0.62),
                            .init(color: mare.opacity(0.35), location: 1),
                        ]),
                        center: CGPoint(x: disc.midX, y: disc.midY), startRadius: 0, endRadius: side / 2
                    ))
                    layer.blendMode = .destinationIn
                    layer.drawLayer { mask in
                        mask.addFilter(.blur(radius: max(0.4, side * softness)))
                        mask.fill(SomaMoonLight(lit: phase).path(in: disc), with: .color(day))
                    }
                }
            }
            // The edge against a light page, which a near white limb would
            // otherwise lose.
            context.stroke(round, with: .color(edge.opacity(metrics.hairlineOpacity * 0.6)), lineWidth: metrics.inputHairline)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The seas, where they lie on the near side, in units of the radius
    /// from the centre: centre x, centre y, half width, half height.
    private static let maria: [(Double, Double, Double, Double)] = [
        (-0.56, -0.02, 0.3, 0.46),   // Oceanus Procellarum
        (-0.26, -0.44, 0.28, 0.21),  // Imbrium
        (0.14, -0.37, 0.16, 0.15),   // Serenitatis
        (0.33, -0.08, 0.21, 0.17),   // Tranquillitatis
        (0.68, -0.3, 0.11, 0.1),     // Crisium
        (0.55, 0.2, 0.12, 0.17),     // Fecunditatis
        (0.33, 0.36, 0.08, 0.08),    // Nectaris
        (-0.2, 0.42, 0.19, 0.14),    // Nubium
        (-0.52, 0.45, 0.09, 0.09),   // Humorum
        (-0.1, -0.7, 0.3, 0.05),     // Frigoris
    ]

    /// The bright young craters, as centre x, centre y and radius.
    private static let craters: [(Double, Double, Double)] = [
        (-0.12, 0.72, 0.05),   // Tycho
        (-0.33, -0.12, 0.04),  // Copernicus
        (-0.62, -0.08, 0.025), // Kepler
        (-0.72, -0.32, 0.025), // Aristarchus
    ]

    private static func surface(in context: inout GraphicsContext, disc: CGRect, mare: Color, light: Color, showsCraters: Bool = true) {
        let r = disc.width / 2
        let place = { (x: Double, y: Double, w: Double, h: Double) in
            CGRect(x: disc.midX + CGFloat(x - w) * r, y: disc.midY + CGFloat(y - h) * r,
                   width: CGFloat(w * 2) * r, height: CGFloat(h * 2) * r)
        }
        // A broad, soft pass, then a tighter one: the seas have edges.
        // Each sea is a main basin and two smaller lobes off it, so no edge
        // reads as a drawn ellipse.
        for (blur, opacity) in [(0.08, 0.3), (0.035, 0.2)] {
            context.drawLayer { seas in
                seas.addFilter(.blur(radius: max(0.3, r * blur)))
                for (index, (x, y, w, h)) in maria.enumerated() {
                    let turn = Double(index) * 2.4
                    seas.fill(Path(ellipseIn: place(x, y, w * 0.85, h * 0.85)), with: .color(mare.opacity(opacity)))
                    for lobe in 0..<2 {
                        let angle = turn + Double(lobe) * 2.6
                        seas.fill(
                            Path(ellipseIn: place(x + cos(angle) * w * 0.45, y + sin(angle) * h * 0.45, w * 0.55, h * 0.5)),
                            with: .color(mare.opacity(opacity * 0.8))
                        )
                    }
                }
            }
        }
        guard showsCraters else { return }
        context.drawLayer { spots in
            spots.addFilter(.blur(radius: max(0.3, r * 0.02)))
            for (x, y, w) in craters {
                spots.fill(Path(ellipseIn: place(x, y, w, w)), with: .color(light.opacity(0.55)))
            }
        }
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
                            .padding(metrics.spaceXS)
                            .overlay {
                                if value == step {
                                    Circle().strokeBorder(colors.accent.color, lineWidth: metrics.inputHairline)
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
