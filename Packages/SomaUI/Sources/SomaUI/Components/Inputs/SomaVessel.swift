//
//  SomaVessel.swift
//  SomaUI
//

import SwiftUI

/// A glass that fills: the water sheet's control, the day's intake, and the
/// small glasses in a row.
///
/// The liquid wears an aspect's hue. `marks` draw a line at the top of each
/// pour, with its label beside the glass, so a day's glass reads as the drinks
/// that filled it.
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

    /// - Parameters:
    ///   - fill: how full, 0...1.
    ///   - aspect: whose hue the liquid wears.
    ///   - marks: the pours, bottom first.
    ///   - showsKnob: the knob on the surface, when a drag sets the fill.
    ///   - isGlyph: a small glass in a row: no bubbles, a thinner rim.
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
        let hue = theme.aspects[aspect].identity.color
        let stroke = isGlyph ? metrics.vesselStroke * 0.75 : metrics.vesselStroke

        GeometryReader { proxy in
            let size = proxy.size
            let glass = SomaVesselShape()
            let inset = stroke * 2.5
            let inner = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let surface = inner.maxY - inner.height * fill

            ZStack(alignment: .topLeading) {
                SomaVesselShape()
                    .inset(by: inset)
                    .fill(hue.opacity(fill > 0 ? 1 : 0))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: max(0, inner.height * fill + inset))
                    }

                if !isGlyph && fill > 0.08 {
                    bubbles(in: inner, surface: surface)
                }

                Path { path in
                    for mark in marks where mark.top < 0.999 {
                        let y = inner.maxY - inner.height * mark.top
                        path.move(to: CGPoint(x: inner.minX, y: y))
                        path.addLine(to: CGPoint(x: inner.maxX, y: y))
                    }
                }
                .stroke(colors.canvas.color.opacity(0.55), lineWidth: 1)
                .clipShape(SomaVesselShape().inset(by: inset))

                ForEach(marks) { mark in
                    Text(mark.label)
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize()
                        .position(x: size.width + metrics.cardSpacing * 2 + labelHalfWidth(mark.label), y: inner.maxY - inner.height * (mark.top + mark.bottom) / 2)
                }

                glass.stroke(colors.inkSecondary.color.opacity(0.8), lineWidth: stroke)

                if showsKnob {
                    SomaKnob()
                        .position(x: rimX(at: surface, in: size) , y: surface)
                }
            }
        }
        .aspectRatio(metrics.vesselWidth / metrics.vesselHeight, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The glass's right wall at a height, where the knob rides.
    private func rimX(at y: CGFloat, in size: CGSize) -> CGFloat {
        let taper = size.width * SomaVesselShape.taper
        let t = y / max(size.height, 1)
        return size.width - taper * t
    }

    /// Room for the label's centre: a rough half width, so the label sits
    /// just right of the glass rather than centred on its edge.
    private func labelHalfWidth(_ label: String) -> CGFloat {
        CGFloat(label.count) * theme.typography.captionValue.size * 0.3
    }

    private func bubbles(in inner: CGRect, surface: CGFloat) -> some View {
        let colors = theme.colors
        let depth = inner.maxY - surface
        let spots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [(0.42, 0.25, 0.018), (0.58, 0.5, 0.024), (0.3, 0.82, 0.03), (0.66, 0.9, 0.02)]
        return ForEach(spots.indices, id: \.self) { index in
            let spot = spots[index]
            Circle()
                .strokeBorder(colors.onOrb.color.opacity(0.45), lineWidth: 1)
                .frame(width: inner.width * spot.r * 2, height: inner.width * spot.r * 2)
                .position(x: inner.minX + inner.width * spot.x, y: surface + depth * spot.y)
        }
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
