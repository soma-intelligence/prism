//
//  SomaVessel.swift
//  SomaUI
//

import SwiftUI

/// A glass that fills: the water sheet's control, the day's intake, and the
/// small glasses in a row.
///
/// Drawn as a real tumbler seen from a little above: a thin rim, hairline
/// walls with a soft refraction down each side, a heavier foot, and water in
/// the aspect's hue that deepens towards the bottom. The surface is an
/// ellipse with a bright meniscus at its front edge; on the big glass it
/// breathes on a slow swell and a faint caustic drifts on the foot. Reduce
/// Motion holds the surface still. `marks` draw a line at the top of each
/// pour, with its label beside the glass, so a day's glass reads as the
/// drinks that filled it.
public struct SomaVessel: View {
    public struct Mark: Identifiable, Sendable {
        public var id: Int
        /// Where the pour ends, 0 at the foot of the glass to 1 at the rim.
        public var top: Double
        /// Where it began.
        public var bottom: Double
        public var label: String

        public init(id: Int, top: Double, bottom: Double, label: String) {
            self.id = id
            self.top = top
            self.bottom = bottom
            self.label = label
        }
    }

    private let fill: Double
    private let aspect: SomaAspect
    private let marks: [Mark]
    private let showsKnob: Bool
    private let isGlyph: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False while the glass is scrolled away or under another page, so its
    /// ripple stops drawing frames nobody sees.
    @State private var isOnScreen = true
    private var power = SomaPowerState.shared

    /// - Parameters:
    ///   - fill: how full, 0...1.
    ///   - aspect: whose hue the liquid wears.
    ///   - marks: the pours, bottom first.
    ///   - showsKnob: the knob on the surface, when a drag sets the fill.
    ///   - isGlyph: a small glass in a row: a still surface, no caustic.
    public init(fill: Double, aspect: SomaAspect = .mind, marks: [Mark] = [], showsKnob: Bool = false, isGlyph: Bool = false) {
        self.fill = min(max(fill, 0), 1)
        self.aspect = aspect
        self.marks = marks
        self.showsKnob = showsKnob
        self.isGlyph = isGlyph
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let moves = !isGlyph && !reduceMotion && fill > 0 && !power.isLowPower && isOnScreen

        GeometryReader { proxy in
            let size = proxy.size
            let geometry = SomaGlassGeometry(size: size, metrics: metrics)
            let surface = geometry.level(fill)

            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !moves)) { timeline in
                    let phase = moves ? timeline.date.timeIntervalSinceReferenceDate / metrics.vesselRipplePeriod * 2 * .pi : 0
                    Canvas { context, _ in
                        draw(in: &context, geometry: geometry, phase: phase)
                    }
                }

                ForEach(marks) { mark in
                    Text(mark.label)
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize()
                        .position(
                            x: size.width + metrics.spaceXL + labelHalfWidth(mark.label),
                            y: geometry.labelY(top: mark.top, bottom: mark.bottom)
                        )
                }

                if showsKnob {
                    SomaKnob()
                        .position(x: geometry.wallX(at: surface, right: true), y: surface)
                }
            }
        }
        .aspectRatio(metrics.vesselWidth / metrics.vesselHeight, contentMode: .fit)
        .somaOnScreen($isOnScreen)
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, geometry g: SomaGlassGeometry, phase: Double) {
        let metrics = theme.metrics
        let colors = theme.colors
        let ink = colors.inkPrimary.color
        let light = colors.onOrb.color
        let hue = theme.aspects[aspect].identity.color
        let line = metrics.inputHairline

        // The glass's own body: barely there, a pane of clear glass.
        context.fill(g.body, with: .color(ink.opacity(metrics.vesselBodyOpacity)))

        // The foot: a thick disc of glass, heavier than the walls.
        context.fill(g.foot, with: .color(ink.opacity(metrics.vesselFootOpacity)))

        // The water.
        if fill > 0.001 {
            let surface = g.level(fill)
            let water = g.water(to: surface, phase: phase, ripple: isGlyph ? 0 : metrics.vesselRipple)
            context.fill(
                water.volume,
                with: .linearGradient(
                    Gradient(colors: [hue.opacity(metrics.vesselWaterTop), hue.opacity(metrics.vesselWaterDeep)]),
                    startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: g.innerFloor)
                )
            )
            // The top face catches the sky: lighter than the body under it.
            context.fill(water.face, with: .color(light.opacity(0.14)))
            context.fill(water.face, with: .color(hue.opacity(0.12)))
            context.stroke(water.back, with: .color(hue.opacity(0.55)), lineWidth: line * 0.75)
            context.stroke(water.front, with: .color(light.opacity(0.85)), lineWidth: line)

            // A caustic: light gathered by the surface, resting on the foot.
            if !isGlyph {
                let drift = CGFloat(sin(phase * 0.5)) * g.width * 0.04
                var caustic = context
                caustic.addFilter(.blur(radius: g.width * 0.04))
                caustic.fill(
                    Path(ellipseIn: CGRect(x: g.centre - g.floorHalf * 0.55 + drift, y: g.innerFloor - g.rimDepth * 0.5,
                                           width: g.floorHalf * 1.1, height: g.rimDepth * 0.8)),
                    with: .color(light.opacity(0.32))
                )
            }

            // The pours, each a line on the front of the water.
            for mark in marks where mark.top < 0.999 {
                context.stroke(g.frontArc(at: g.level(mark.top), inset: g.wall), with: .color(light.opacity(0.4)), lineWidth: line)
            }
        }

        // Refraction: a soft band of light down the left wall, a thinner one
        // on the right, as a real tumbler throws them. Blurred, and faded
        // towards the rim and the foot, where the curve turns them away.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(0.6, g.width * 0.012)))
            layer.fill(g.band(from: 0.1, to: 0.17), with: .color(light.opacity(0.42)))
            layer.fill(g.band(from: 0.87, to: 0.9), with: .color(light.opacity(0.26)))
            layer.blendMode = .destinationIn
            layer.fill(
                Path(CGRect(x: 0, y: g.rimY, width: g.width, height: g.baseY - g.rimY)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: light.opacity(0), location: 0),
                        .init(color: light, location: 0.25),
                        .init(color: light, location: 0.7),
                        .init(color: light.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: g.rimY), endPoint: CGPoint(x: 0, y: g.baseY)
                )
            )
        }

        // The walls, the foot's edge and the rim: one hairline.
        context.stroke(g.walls, with: .color(ink.opacity(metrics.vesselWallOpacity)), lineWidth: line)
        context.stroke(g.footEdge, with: .color(ink.opacity(metrics.vesselWallOpacity * 0.35)), lineWidth: line)
        context.stroke(g.rim, with: .color(ink.opacity(metrics.vesselWallOpacity)), lineWidth: line)
        context.stroke(g.rimFront, with: .color(light.opacity(0.55)), lineWidth: line * 0.75)
    }

    /// Room for the label's centre: a rough half width, so the label sits
    /// just right of the glass rather than centred on its edge.
    private func labelHalfWidth(_ label: String) -> CGFloat {
        CGFloat(label.count) * theme.typography.captionValue.size * 0.3
    }
}

/// Where everything on a tumbler sits, for a frame: the rim, the walls, the
/// foot and the water's level for a fill.
struct SomaGlassGeometry {
    let width: CGFloat
    let centre: CGFloat
    /// Half the rim's ellipse, top to bottom.
    let rimDepth: CGFloat
    let rimY: CGFloat
    let baseY: CGFloat
    let topHalf: CGFloat
    let floorHalf: CGFloat
    /// The top of the foot, inside, where water can reach.
    let innerFloor: CGFloat
    let wall: CGFloat

    init(size: CGSize, metrics: SomaMetrics) {
        width = size.width
        centre = size.width / 2
        let line = metrics.inputHairline
        topHalf = size.width / 2 - line
        floorHalf = topHalf * (1 - 2 * SomaVesselShape.taper)
        rimDepth = size.width * metrics.vesselRimDepth
        rimY = rimDepth + line
        baseY = size.height - rimDepth * 0.85 - line
        innerFloor = baseY - size.height * metrics.vesselFootDepth
        wall = size.width * metrics.vesselWallDepth
    }

    /// The half width of the glass at a height.
    func half(at y: CGFloat) -> CGFloat {
        let t = (y - rimY) / max(baseY - rimY, 1)
        return topHalf + (floorHalf - topHalf) * min(max(t, 0), 1)
    }

    /// The ellipse's depth at a height: the rim opens widest, the foot least.
    func depth(at y: CGFloat) -> CGFloat {
        rimDepth * half(at: y) / max(topHalf, 1)
    }

    func wallX(at y: CGFloat, right: Bool) -> CGFloat {
        centre + (right ? 1 : -1) * half(at: y)
    }

    /// The water's surface for a fill, 0 on the foot to 1 just under the rim.
    func level(_ fill: Double) -> CGFloat {
        let top = rimY + rimDepth * 0.6
        return innerFloor - (innerFloor - top) * CGFloat(min(max(fill, 0), 1))
    }

    private func ellipsePoint(_ y: CGFloat, inset: CGFloat, _ angle: Double) -> CGPoint {
        let a = half(at: y) - inset
        let b = depth(at: y) * a / max(half(at: y), 1)
        return CGPoint(x: centre + a * CGFloat(cos(angle)), y: y + b * CGFloat(sin(angle)))
    }

    /// Half an ellipse across the glass at a height: the front half when
    /// `front`, the back half otherwise, drawn left to right unless
    /// `leftward`. `ripple` lifts each point by its share of the way across.
    func arc(at y: CGFloat, inset: CGFloat = 0, front: Bool, leftward: Bool = false, ripple: (Double) -> CGFloat = { _ in 0 }) -> Path {
        Path { path in
            let steps = 48
            for index in 0...steps {
                let step = Double(index) / Double(steps)
                let share = leftward ? 1 - step : step
                let angle = front ? .pi - .pi * share : .pi + .pi * share
                var p = ellipsePoint(y, inset: inset, angle)
                p.y += ripple(share)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    /// Where a pour's label sits: between its two lines where they cross
    /// the front of the glass.
    func labelY(top: Double, bottom: Double) -> CGFloat {
        let mid = (level(top) + level(bottom)) / 2
        return mid + depth(at: mid)
    }

    func frontArc(at y: CGFloat, inset: CGFloat) -> Path { arc(at: y, inset: inset, front: true) }

    var rim: Path { Path(ellipseIn: CGRect(x: centre - topHalf, y: rimY - rimDepth, width: topHalf * 2, height: rimDepth * 2)) }
    var rimFront: Path { arc(at: rimY, inset: wall * 0.5, front: true) }

    var walls: Path {
        Path { path in
            path.move(to: CGPoint(x: centre - topHalf, y: rimY))
            path.addLine(to: CGPoint(x: centre - floorHalf, y: baseY))
            path.move(to: CGPoint(x: centre + topHalf, y: rimY))
            path.addLine(to: CGPoint(x: centre + floorHalf, y: baseY))
            path.addPath(arc(at: baseY, front: true))
        }
    }

    /// The whole glass seen from the side: rim's back edge to foot's front.
    var body: Path {
        var path = arc(at: rimY, front: false)
        path.addLine(to: CGPoint(x: centre + floorHalf, y: baseY))
        continueLine(&path, arc(at: baseY, front: true, leftward: true))
        path.closeSubpath()
        return path
    }

    /// Adds a path's points to another as lines, so it carries on the same
    /// outline rather than starting a new one.
    func continueLine(_ path: inout Path, _ more: Path) {
        more.forEach { element in
            switch element {
            case .move(let p), .line(let p): path.addLine(to: p)
            case .quadCurve(let p, _), .curve(let p, _, _): path.addLine(to: p)
            case .closeSubpath: break
            }
        }
    }

    /// The foot: the solid glass between the outer base and the inner floor.
    var foot: Path {
        var path = arc(at: innerFloor, inset: wall * 0.6, front: false)
        path.addLine(to: CGPoint(x: centre + half(at: baseY), y: baseY))
        continueLine(&path, arc(at: baseY, front: true, leftward: true))
        path.closeSubpath()
        return path
    }

    var footEdge: Path { arc(at: innerFloor, inset: wall * 0.6, front: true) }

    /// A band down the glass between two shares of its width, rim to foot.
    func band(from: CGFloat, to: CGFloat) -> Path {
        Path { path in
            let top = rimY + rimDepth
            let bottom = baseY - depth(at: baseY) * 0.2
            let x = { (y: CGFloat, share: CGFloat) in self.centre - self.half(at: y) + self.half(at: y) * 2 * share }
            path.move(to: CGPoint(x: x(top, from), y: top))
            path.addLine(to: CGPoint(x: x(top, to), y: top))
            path.addLine(to: CGPoint(x: x(bottom, to), y: bottom))
            path.addLine(to: CGPoint(x: x(bottom, from), y: bottom))
            path.closeSubpath()
        }
    }

    struct Water {
        var volume: Path
        var face: Path
        var front: Path
        var back: Path
    }

    /// The water up to a surface: its volume, its top face, and the face's
    /// front and back edges, with a slow swell along it.
    func water(to surface: CGFloat, phase: Double, ripple: CGFloat) -> Water {
        let swell: (Double) -> CGFloat = { share in
            ripple * CGFloat(sin(share * 2 * .pi * 1.3 + phase) * 0.7 + sin(share * 2 * .pi * 0.6 - phase * 0.8) * 0.3)
        }
        let inset = wall
        let front = arc(at: surface, inset: inset, front: true, ripple: swell)
        let backSwell: (Double) -> CGFloat = { share in swell(1 - share) }
        let back = arc(at: surface, inset: inset, front: false, ripple: backSwell)

        var face = back
        continueLine(&face, arc(at: surface, inset: inset, front: true, leftward: true, ripple: swell))
        face.closeSubpath()

        var volume = back
        volume.addLine(to: CGPoint(x: centre + half(at: innerFloor) - inset, y: innerFloor))
        continueLine(&volume, arc(at: innerFloor, inset: inset, front: true, leftward: true))
        volume.closeSubpath()
        return Water(volume: volume, face: face, front: front, back: back)
    }
}

/// A tumbler: wider at the rim than at the foot, with a rounded base.
public struct SomaVesselShape: InsettableShape {
    /// How far each wall leans in over the height, as a share of the width.
    static let taper: CGFloat = 0.12
    private var inset: CGFloat = 0

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let lean = r.width * Self.taper
        let radius = min(r.width * 0.12, r.height * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + lean, y: r.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: r.minX + lean + radius, y: r.maxY), control: CGPoint(x: r.minX + lean, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - lean - radius, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.maxX - lean, y: r.maxY - radius), control: CGPoint(x: r.maxX - lean, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return path
    }

    public func inset(by amount: CGFloat) -> SomaVesselShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The glass as a control: drag up to pour, down to empty, snapping to a
/// step with a tick at each one.
public struct SomaVesselInput: View {
    @Binding private var value: Double
    private let capacity: Double
    private let step: Double
    private let aspect: SomaAspect
    private let label: String

    @Environment(\.somaTheme) private var theme
    @State private var dragStart: Double?

    /// - Parameters:
    ///   - value: millilitres, or whatever the glass counts.
    ///   - capacity: what a full glass holds.
    ///   - step: one detent.
    ///   - label: what VoiceOver calls it.
    public init(value: Binding<Double>, capacity: Double, step: Double, aspect: SomaAspect = .mind, label: String) {
        self._value = value
        self.capacity = capacity
        self.step = step
        self.aspect = aspect
        self.label = label
    }

    public var body: some View {
        GeometryReader { proxy in
            SomaVessel(fill: capacity > 0 ? value / capacity : 0, aspect: aspect, showsKnob: true)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(.rect)
                .somaClaimsSwipe()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let start = dragStart ?? value
                            if dragStart == nil { dragStart = value }
                            let delta = -drag.translation.height / max(proxy.size.height, 1) * capacity
                            value = snapped(start + delta)
                        }
                        .onEnded { _ in dragStart = nil }
                )
        }
        .aspectRatio(theme.metrics.vesselWidth / theme.metrics.vesselHeight, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(Int(value.rounded()))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snapped(value + step)
            case .decrement: value = snapped(value - step)
            @unknown default: break
            }
        }
    }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, 0), capacity)
        guard step > 0 else { return clamped }
        return min(capacity, (clamped / step).rounded() * step)
    }
}

#Preview("Vessel") {
    @Previewable @State var ml = 250.0
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaVesselInput(value: $ml, capacity: 500, step: 50, label: "Water")
                .frame(height: 250)
            HStack(spacing: 12) {
                ForEach([1.0, 1, 0.6, 0], id: \.self) { SomaVessel(fill: $0, isGlyph: true).frame(height: 36) }
            }
            SomaVessel(fill: 0.7, marks: [.init(id: 0, top: 0.3, bottom: 0, label: "07:30  400 ml"), .init(id: 1, top: 0.7, bottom: 0.3, label: "13:00  500 ml")])
                .frame(height: 220)
                .padding(.trailing, 120)
        }
    }
}
