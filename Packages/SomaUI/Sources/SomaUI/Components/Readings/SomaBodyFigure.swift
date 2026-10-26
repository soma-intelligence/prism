//
//  SomaBodyFigure.swift
//  SomaUI
//

import SwiftUI

/// One reading pinned to the body: its name, the value and unit, and a short
/// note under it, such as the usual range it is read against.
public struct SomaBodyCallout: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    /// The number as it should read, or nil for a dash.
    public let value: String?
    public let unit: String
    public let note: String?
    /// A dot before the note when the reading sits outside its usual range:
    /// good news or something to watch. Nil draws no dot.
    public let tone: SomaCueTone?

    public init(title: String, value: String?, unit: String, note: String? = nil, tone: SomaCueTone? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.note = note
        self.tone = tone
    }
}

/// The body with readings pinned to the organ they describe, as Neka lays out
/// its home: the heart's numbers on the heart, breathing on the chest, the
/// skin's temperature at the wrist where the watch reads it.
///
/// The figure is the vendored MuscleMap front art (see ``SomaMuscleMap``),
/// drawn in one grey a step off the canvas, without a face. A leader runs from
/// each pin to the readings it belongs to; the readings are measured as laid
/// out, so a larger text size moves the leader with them.
public struct SomaBodyFigure: View {
    /// Which readings, and so which crop of the figure and which pins.
    public enum Readings: Equatable, Sendable {
        /// Head to mid thigh, for last night: breathing and blood oxygen on
        /// the chest (top leading), the heart's readings (top trailing), the
        /// wrist's temperature (bottom leading).
        case overnight(chest: [SomaBodyCallout], heart: [SomaBodyCallout], wrist: [SomaBodyCallout])
        /// Head to feet, for the long run: a column of readings on the
        /// trailing side, each pinned to its site, top to bottom in the order
        /// given. Order them by their site's height so no two leaders cross.
        case longTerm([Pinned])
    }

    /// A reading and the place on the body it is about.
    public struct Pinned: Equatable, Sendable, Identifiable {
        public var id: String { callout.id }
        public let site: SomaBodySite
        public let callout: SomaBodyCallout

        public init(_ site: SomaBodySite, _ callout: SomaBodyCallout) {
            self.site = site
            self.callout = callout
        }
    }

    private let readings: Readings

    public init(_ readings: Readings) {
        self.readings = readings
    }

    public var body: some View {
        switch readings {
        case let .overnight(chest, heart, wrist):
            OvernightLayout(chest: chest, heart: heart, wrist: wrist)
        case let .longTerm(pins):
            LongTermLayout(pins: pins)
        }
    }
}

/// A place on the figure a reading is pinned to.
public enum SomaBodySite: Sendable, Equatable {
    /// The chest on the leading side: breathing, blood oxygen, VO2 max.
    case lungs
    /// The chest on the trailing side, under the heart's own lung.
    case trailingLung
    case heart
    /// The leading wrist, where the watch sits.
    case wrist
    /// The trailing arm's inner elbow, where blood is drawn.
    case innerElbow
    case belly

    /// The site in the art's own coordinates (the front figure spans x 53 to
    /// 675 and y 96 to 1340).
    var point: CGPoint {
        switch self {
        case .lungs: CGPoint(x: 312, y: 384)
        case .trailingLung: CGPoint(x: 452, y: 410)
        case .heart: CGPoint(x: 410, y: 372)
        case .wrist: CGPoint(x: 152, y: 698)
        case .innerElbow: CGPoint(x: 520, y: 498)
        case .belly: CGPoint(x: 364, y: 560)
        }
    }
}

// MARK: - Last night: three corners

private struct OvernightLayout: View {
    let chest: [SomaBodyCallout]
    let heart: [SomaBodyCallout]
    let wrist: [SomaBodyCallout]

    /// Head to mid thigh, with room beside the head for two groups and under
    /// the leading hand for one.
    private static let crop = CGRect(x: 40, y: 118, width: 650, height: 842)

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let crop = Self.crop

        BodyArt(crop: crop)
            .overlay(alignment: .topLeading) {
                CalloutGroup(callouts: chest, alignment: .leading)
                    .anchorPreference(key: CalloutBounds.self, value: .bounds) { [Corner.chest: $0] }
            }
            .overlay(alignment: .topTrailing) {
                CalloutGroup(callouts: heart, alignment: .trailing)
                    .anchorPreference(key: CalloutBounds.self, value: .bounds) { [Corner.heart: $0] }
            }
            .overlay(alignment: .bottomLeading) {
                CalloutGroup(callouts: wrist, alignment: .leading)
                    .anchorPreference(key: CalloutBounds.self, value: .bounds) { [Corner.wrist: $0] }
            }
            .overlayPreferenceValue(CalloutBounds.self) { bounds in
                GeometryReader { proxy in
                    let scale = proxy.size.width / crop.width
                    let place = { (site: SomaBodySite) in
                        CGPoint(x: (site.point.x - crop.minX) * scale, y: (site.point.y - crop.minY) * scale)
                    }
                    let gap = metrics.bodyLeaderGap
                    let lungs = place(.lungs), heartPin = place(.heart), wristPin = place(.wrist)

                    Path { path in
                        if let anchor = bounds[.chest] {
                            Leader.up(from: lungs, toward: proxy[anchor], gap: gap, leading: true, into: &path)
                        }
                        if let anchor = bounds[.heart] {
                            Leader.up(from: heartPin, toward: proxy[anchor], gap: gap, leading: false, into: &path)
                        }
                        if let anchor = bounds[.wrist] {
                            let rect = proxy[anchor]
                            if rect.minY - gap > wristPin.y {
                                path.move(to: wristPin)
                                path.addLine(to: CGPoint(x: wristPin.x, y: rect.minY - gap))
                            }
                        }
                    }
                    .stroke(theme.colors.inkSecondary.color.opacity(0.5), lineWidth: metrics.bodyLeaderWidth)

                    ForEach([lungs, heartPin, wristPin], id: \.x) { point in
                        BodyPin().position(point)
                    }
                }
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
    }

    private enum Corner: Hashable { case chest, heart, wrist }

    private struct CalloutBounds: PreferenceKey {
        static let defaultValue: [Corner: Anchor<CGRect>] = [:]
        static func reduce(value: inout [Corner: Anchor<CGRect>], nextValue: () -> [Corner: Anchor<CGRect>]) {
            value.merge(nextValue()) { $1 }
        }
    }
}

// MARK: - The long run: a column beside the figure

private struct LongTermLayout: View {
    let pins: [SomaBodyFigure.Pinned]

    /// Head to feet.
    private static let crop = CGRect(x: 40, y: 104, width: 650, height: 1246)

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let crop = Self.crop

        PinnedColumn(crop: crop, spacing: metrics.cardSpacing * 2, gap: metrics.bodyCalloutSpacing * 2) {
            BodyArt(crop: crop)
                .anchorPreference(key: Bounds.self, value: .bounds) { [Bounds.figure: $0] }
            ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                CalloutView(callout: pin.callout, alignment: .leading)
                    .anchorPreference(key: Bounds.self, value: .bounds) { [index: $0] }
                    .layoutValue(key: PinnedHeight.self, value: pin.site.point.y)
            }
        }
        .overlayPreferenceValue(Bounds.self) { bounds in
            GeometryReader { proxy in
                if let figureAnchor = bounds[Bounds.figure] {
                    let figure = proxy[figureAnchor]
                    let scale = figure.width / crop.width
                    let points = pins.map { pin in
                        CGPoint(x: figure.minX + (pin.site.point.x - crop.minX) * scale,
                                y: figure.minY + (pin.site.point.y - crop.minY) * scale)
                    }
                    let gap = metrics.bodyLeaderGap

                    Path { path in
                        for (index, point) in points.enumerated() {
                            guard let anchor = bounds[index] else { continue }
                            let rect = proxy[anchor]
                            // Across to just short of the column, level with
                            // the reading's value line, then into it.
                            let y = rect.minY + rect.height * 0.4
                            let elbow = CGPoint(x: rect.minX - gap * 3, y: y)
                            path.move(to: point)
                            path.addLine(to: elbow)
                            path.addLine(to: CGPoint(x: rect.minX - gap, y: y))
                        }
                    }
                    .stroke(theme.colors.inkSecondary.color.opacity(0.5), lineWidth: metrics.bodyLeaderWidth)

                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        BodyPin().position(point)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private struct Bounds: PreferenceKey {
        static let figure = -1
        static let defaultValue: [Int: Anchor<CGRect>] = [:]
        static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
            value.merge(nextValue()) { $1 }
        }
    }
}

/// The art's height a callout belongs at, in the art's own coordinates.
private struct PinnedHeight: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

/// The figure on the leading side and the readings in a column beside it,
/// each set level with its pin and pushed down only as far as it takes not to
/// touch the one above: short leaders, whatever the text size.
private struct PinnedColumn: Layout {
    let crop: CGRect
    let spacing: CGFloat
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 360
        let frames = place(width: width, subviews: subviews)
        let figure = frames.first ?? .zero
        let bottom = frames.dropFirst().map(\.maxY).max() ?? 0
        return CGSize(width: width, height: max(figure.height, bottom))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = place(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// Every subview's frame: the figure first, then each reading.
    private func place(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard let figure = subviews.first else { return [] }
        let readings = subviews.dropFirst()
        let column = min(width * 0.45, readings.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0)
        let figureWidth = max(0, width - spacing - column)
        let scale = figureWidth / crop.width
        let figureHeight = figure.sizeThatFits(ProposedViewSize(width: figureWidth, height: nil)).height

        var frames = [CGRect(x: 0, y: 0, width: figureWidth, height: figureHeight)]
        var bottom = -gap
        for reading in readings {
            let size = reading.sizeThatFits(ProposedViewSize(width: column, height: nil))
            let site = reading[PinnedHeight.self].map { ($0 - crop.minY) * scale } ?? bottom + gap
            let y = max(site - size.height * 0.4, bottom + gap, 0)
            frames.append(CGRect(x: figureWidth + spacing, y: y, width: column, height: size.height))
            bottom = y + size.height
        }
        return frames
    }
}

// MARK: - Parts

/// The front figure in one grey, cropped to `crop` (in the art's coordinates).
private struct BodyArt: View {
    let crop: CGRect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let ink = colors.canvas.color.mix(with: colors.inkSecondary.color, by: metrics.bodyFigureInk)
        let swell = StrokeStyle(lineWidth: metrics.bodyFigureSwell, lineJoin: .round)
        let crop = crop

        Canvas { context, size in
            let scale = size.width / crop.width
            context.translateBy(x: -crop.minX * scale, y: -crop.minY * scale)
            context.scaleBy(x: scale, y: scale)
            // Each part on its own: one path of all of them would cancel where
            // two parts drawn in opposite directions overlap.
            for part in MuscleArtFigure.front.parts {
                context.fill(part.path, with: .color(ink))
                context.stroke(part.path, with: .color(ink), style: swell)
            }
        }
        .aspectRatio(crop.width / crop.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A ring with a dot in it, on the canvas.
private struct BodyPin: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        ZStack {
            Circle().fill(colors.canvas.color)
            Circle().strokeBorder(colors.inkPrimary.color, lineWidth: metrics.bodyPinRingWidth)
            Circle().fill(colors.inkPrimary.color).frame(width: metrics.bodyPinCoreDiameter, height: metrics.bodyPinCoreDiameter)
        }
        .frame(width: metrics.bodyPinDiameter, height: metrics.bodyPinDiameter)
    }
}

/// Several readings stacked in one corner.
private struct CalloutGroup: View {
    let callouts: [SomaBodyCallout]
    let alignment: HorizontalAlignment

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: alignment, spacing: theme.metrics.bodyCalloutSpacing) {
            ForEach(callouts) { CalloutView(callout: $0, alignment: alignment) }
        }
        .frame(maxWidth: theme.metrics.bodyCalloutWidth, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// One reading: its name, the value and unit, and the note.
private struct CalloutView: View {
    let callout: SomaBodyCallout
    let alignment: HorizontalAlignment

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let metrics = theme.metrics

        VStack(alignment: alignment, spacing: 0) {
            Text(callout.title)
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                SomaNumber(callout.value, type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(callout.unit)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            if let note = callout.note {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let tone = callout.tone {
                        Circle()
                            .fill(tone.color(colors))
                            .frame(width: metrics.chartDotDiameter, height: metrics.chartDotDiameter)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    }
                    Text(note)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The leader from a pin up to a group of readings above it: a diagonal at
/// forty five degrees to just under the group, then along its foot.
private enum Leader {
    static func up(from pin: CGPoint, toward rect: CGRect, gap: CGFloat, leading: Bool, into path: inout Path) {
        let y = rect.maxY + gap
        guard y < pin.y - gap else { return }
        let rise = pin.y - y
        let elbowX = leading ? min(pin.x - rise, rect.maxX) : max(pin.x + rise, rect.minX)
        path.move(to: pin)
        path.addLine(to: CGPoint(x: elbowX, y: y))
        path.addLine(to: CGPoint(x: leading ? rect.minX : rect.maxX, y: y))
    }
}

#Preview("Body figure, last night") {
    ZStack {
        SomaPreviewBackdrop()
        SomaBodyFigure(.overnight(
            chest: [
                SomaBodyCallout(title: "Breathing", value: "14.2", unit: "/min", note: "Usual 13.6 to 15.0"),
                SomaBodyCallout(title: "Blood oxygen", value: "97", unit: "%", note: "Usual 95 to 98"),
            ],
            heart: [
                SomaBodyCallout(title: "Resting heart rate", value: "52", unit: "bpm", note: "Usual 51 to 56"),
                SomaBodyCallout(title: "HRV", value: "58", unit: "ms", note: "Above usual 44 to 56", tone: .good),
            ],
            wrist: [SomaBodyCallout(title: "Wrist temperature", value: "+0.12", unit: "°C", note: "Against your usual")]
        ))
        .padding(16)
    }
}

#Preview("Body figure, the long run") {
    ZStack {
        SomaPreviewBackdrop()
        SomaBodyFigure(.longTerm([
            .init(.heart, SomaBodyCallout(title: "Blood pressure", value: "118/76", unit: "mmHg", note: "Cuff, Oct 20")),
            .init(.trailingLung, SomaBodyCallout(title: "VO2 max", value: "46.8", unit: "ml/kg/min", note: "Watch, 90 days")),
            .init(.innerElbow, SomaBodyCallout(title: "Inflammation", value: "0.6", unit: "mg/L", note: "hs-CRP, Sept 12")),
            .init(.belly, SomaBodyCallout(title: "Weight", value: "74.2", unit: "kg", note: "Body fat 15.8 %")),
        ]))
        .padding(16)
    }
}
