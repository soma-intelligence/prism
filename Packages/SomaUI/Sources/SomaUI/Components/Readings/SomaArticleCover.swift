//
//  SomaArticleCover.swift
//  SomaUI
//

import SwiftUI

/// The picture over an article: its photograph when it has one, otherwise a
/// calm cover drawn from the topic's tone.
///
/// The generated cover is a soft wash of the topic's muted tone (a
/// ``SomaTrackTone``, the same calm family Track and Today use), a second
/// tone drifting in from one corner, hairline rings and the topic's line
/// glyph on a quiet disc. The article's own seed picks one of four
/// compositions (a ripple, a body in orbit, a sun on the horizon, two
/// ripples crossing) and where it sits, so a cover is the same every time it
/// draws and differs from its neighbour's, while a page of them stays one
/// family. While a photograph loads, or when it fails, the generated cover
/// stands in: the frame never shows a spinner or an empty box.
public struct SomaArticleCover: View {
    public enum Size: Sendable {
        /// The featured card on the library page.
        case feature
        /// A tile in the grid or on a shelf.
        case tile
        /// The square at the head of a row.
        case row
        /// The head of the reader page.
        case reader
    }

    /// The line glyph a generated cover carries.
    public enum Mark: Sendable, Hashable {
        case aspect(SomaAspect)
        case track(SomaTrackGlyph.Kind)
    }

    private let tone: SomaTrackTone
    private let mark: Mark
    private let seed: String
    private let imageURL: URL?
    private let asset: String?
    private let size: Size

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.somaPartIsCurrent) private var partIsCurrent
    @State private var fetchesPhoto = false

    /// - Parameters:
    ///   - tone: the topic's calm tone.
    ///   - mark: the topic's line glyph.
    ///   - seed: anything stable about the article, its slug say.
    ///   - imageURL: the photograph, when the article has one online.
    ///   - asset: the photograph in the app's asset catalog, which wins over
    ///     `imageURL`: it is there on the first frame and offline.
    public init(tone: SomaTrackTone, mark: Mark, seed: String, imageURL: URL? = nil, asset: String? = nil, size: Size) {
        self.tone = tone
        self.mark = mark
        self.seed = seed
        self.imageURL = imageURL
        self.asset = asset
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        frame
            .overlay { generated }
            .overlay {
                if let asset {
                    Image(asset).resizable().scaledToFill()
                } else if let imageURL, fetchesPhoto {
                    AsyncImage(url: imageURL, transaction: Transaction(animation: reduceMotion ? nil : .easeOut(duration: theme.motion.pressDuration * 2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
            // A cover in a tab's part kept aside fetches nothing until its
            // part comes on screen once; then it keeps its photograph.
            .onChange(of: partIsCurrent, initial: true) { _, current in
                if current { fetchesPhoto = true }
            }
    }

    @ViewBuilder
    private var frame: some View {
        let metrics = theme.metrics
        switch size {
        case .row:
            Color.clear.frame(width: metrics.articleRowCoverSide, height: metrics.articleRowCoverSide)
        case .feature:
            Color.clear.frame(height: metrics.articleFeatureCoverHeight).frame(maxWidth: .infinity)
        case .tile:
            Color.clear.frame(height: metrics.articleTileCoverHeight).frame(maxWidth: .infinity)
        case .reader:
            Color.clear.frame(height: metrics.articleReaderCoverHeight).frame(maxWidth: .infinity)
        }
    }

    private var generated: some View {
        let metrics = theme.metrics
        let art = SomaArticleCoverArt(seed: seed)
        let dark = colorScheme == .dark
        let wash = dark ? metrics.articleCoverWashDark : metrics.articleCoverWashLight
        let ink = tone.color
        let drift = art.drift(from: tone).color
        let ring = ink.opacity(metrics.articleCoverRingOpacity)
        let glyphSide = glyphSize(metrics)

        return GeometryReader { proxy in
            let box = proxy.size
            let side = max(box.width, box.height)
            ZStack {
                theme.colors.surface.color
                LinearGradient(colors: [ink.opacity(wash.top), ink.opacity(wash.bottom)],
                               startPoint: art.washStart, endPoint: art.washEnd)
                RadialGradient(colors: [drift.opacity(metrics.articleCoverDrift), drift.opacity(0)],
                               center: art.driftCorner, startRadius: 0, endRadius: side * 0.9)
                Canvas { context, canvas in
                    let side = max(canvas.width, canvas.height)
                    func point(_ unit: CGPoint) -> CGPoint {
                        CGPoint(x: unit.x * canvas.width, y: unit.y * canvas.height)
                    }
                    if let disc = art.disc {
                        var centre = point(disc.centre)
                        if let orbit = disc.orbit {
                            centre.x += cos(disc.angle) * orbit * side
                            centre.y += sin(disc.angle) * orbit * side
                        }
                        let radius = disc.radius * side
                        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                            width: radius * 2, height: radius * 2)),
                                     with: .color(ink.opacity(metrics.articleCoverDiscOpacity)))
                    }
                    for circle in art.rings {
                        let centre = point(circle.centre)
                        let radius = circle.radius * side
                        context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                              width: radius * 2, height: radius * 2)),
                                       with: .color(ring.opacity(circle.strength)),
                                       lineWidth: metrics.articleCoverRingWidth)
                    }
                }
                glyph(side: glyphSide, ink: ink)
                    .frame(width: glyphSide * metrics.articleCoverMedallion,
                           height: glyphSide * metrics.articleCoverMedallion)
                    .background(Circle().fill(theme.colors.surface.color.opacity(dark ? metrics.articleCoverMedallionDark : metrics.articleCoverMedallionLight)))
                    .position(x: art.glyph.x * box.width, y: art.glyph.y * box.height)
            }
        }
    }

    @ViewBuilder
    private func glyph(side: CGFloat, ink: Color) -> some View {
        let metrics = theme.metrics
        let stroke = StrokeStyle(lineWidth: side * metrics.aspectGlyphStroke / metrics.aspectGlyphGrid,
                                 lineCap: .round, lineJoin: .round)
        switch mark {
        case .aspect(let aspect):
            SomaAspectGlyphShape(aspect: aspect).stroke(ink, style: stroke).frame(width: side, height: side)
        case .track(let kind):
            SomaTrackGlyphShape(kind: kind).stroke(ink, style: stroke).frame(width: side, height: side)
        }
    }

    private var cornerRadius: CGFloat {
        let metrics = theme.metrics
        switch size {
        case .tile: return metrics.articleTileCornerRadius
        case .row: return metrics.articleRowCornerRadius
        case .feature, .reader: return metrics.articleCoverCornerRadius
        }
    }

    private func glyphSize(_ metrics: SomaMetrics) -> CGFloat {
        switch size {
        case .row: metrics.articleCoverGlyphRow
        case .tile: metrics.articleCoverGlyphTile
        case .feature, .reader: metrics.articleCoverGlyphFeature
        }
    }
}

/// What a generated cover draws, placed from a seed so the same article
/// always gets the same picture. Positions are fractions of the cover's
/// width and height; radii are fractions of its longer side.
struct SomaArticleCoverArt: Equatable {
    enum Composition: CaseIterable, Equatable {
        /// Rings widening from one point, the glyph at their heart.
        case ripple
        /// One wide ring with a small body on it, the glyph at the centre.
        case orbit
        /// Rings rising from below the foot like a sun, its disc filled.
        case horizon
        /// Two ripples from two points, crossing.
        case crossing
    }

    struct Ring: Equatable {
        var centre: CGPoint
        var radius: Double
        /// Multiplies the ring opacity: outer rings fade.
        var strength: Double
    }

    struct Disc: Equatable {
        var centre: CGPoint
        var radius: Double
        /// Set when the disc rides a ring: it sits that far from `centre`
        /// (a fraction of the longer side, like a radius) at `angle`.
        var orbit: Double? = nil
        var angle: Double = 0
    }

    var composition: Composition
    var rings: [Ring]
    var disc: Disc?
    /// Where the glyph's disc sits.
    var glyph: CGPoint
    var washStart: UnitPoint
    var washEnd: UnitPoint
    /// The corner the second tone drifts in from.
    var driftCorner: UnitPoint
    /// Steps along ``SomaTrackTone/allCases`` to the second tone.
    var driftStep: Int

    init(seed: String) {
        var random = SeededRandom(seed)
        let composition = Composition.allCases[Int(random.next() * Double(Composition.allCases.count)) % Composition.allCases.count]
        self.composition = composition

        func ripple(at centre: CGPoint, count: Int, from first: Double, step: Double) -> [Ring] {
            (0..<count).map { index in
                Ring(centre: centre, radius: first + Double(index) * step,
                     strength: 1 - Double(index) / Double(count + 1))
            }
        }

        switch composition {
        case .ripple:
            let centre = CGPoint(x: 0.25 + random.next() * 0.5, y: 0.3 + random.next() * 0.4)
            rings = ripple(at: centre, count: 4 + Int(random.next() * 3), from: 0.13, step: 0.085 + random.next() * 0.04)
            disc = nil
            glyph = centre
        case .orbit:
            let centre = CGPoint(x: 0.35 + random.next() * 0.3, y: 0.42 + random.next() * 0.16)
            let radius = 0.27 + random.next() * 0.08
            let angle = random.next() * 2 * .pi
            rings = [Ring(centre: centre, radius: radius, strength: 1),
                     Ring(centre: centre, radius: radius * 0.62, strength: 0.6),
                     Ring(centre: centre, radius: radius * 1.42, strength: 0.45)]
            disc = Disc(centre: centre, radius: 0.035 + random.next() * 0.02, orbit: radius, angle: angle)
            glyph = centre
        case .horizon:
            let centre = CGPoint(x: 0.3 + random.next() * 0.4, y: 1.05)
            rings = ripple(at: centre, count: 4 + Int(random.next() * 2), from: 0.24, step: 0.1)
            disc = Disc(centre: centre, radius: 0.2)
            glyph = CGPoint(x: centre.x, y: 0.42)
        case .crossing:
            let left = CGPoint(x: 0.15 + random.next() * 0.2, y: 0.25 + random.next() * 0.5)
            let right = CGPoint(x: 0.65 + random.next() * 0.2, y: 0.25 + random.next() * 0.5)
            rings = ripple(at: left, count: 4, from: 0.1, step: 0.09) + ripple(at: right, count: 4, from: 0.1, step: 0.09)
            disc = nil
            glyph = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        }

        let corners: [UnitPoint] = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]
        let turn = Int(random.next() * 4) % 4
        washStart = corners[turn]
        washEnd = corners[(turn + 2) % 4]
        driftCorner = corners[(turn + 1 + Int(random.next() * 2) * 2) % 4]
        driftStep = 1 + Int(random.next() * Double(SomaTrackTone.allCases.count - 2))
    }

    /// The second tone, a few steps along the family from `tone`; never the
    /// tone itself.
    func drift(from tone: SomaTrackTone) -> SomaTrackTone {
        let all = SomaTrackTone.allCases
        let start = all.firstIndex(of: tone) ?? 0
        return all[(start + driftStep) % all.count]
    }
}

/// FNV-1a then xorshift64*: `hashValue` is salted per launch, and a cover
/// must not change between two launches.
struct SeededRandom {
    private var state: UInt64

    init(_ seed: String) {
        var state: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
        self.state = state == 0 ? 0x9E37_79B9_7F4A_7C15 : state
    }

    /// The next number in 0 ..< 1.
    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return Double((state &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(UInt64(1) << 53)
    }
}

#Preview("Covers") {
    ScrollView {
        VStack(spacing: 12) {
            SomaArticleCover(tone: .dusk, mark: .aspect(.sleep), seed: "sleep-regularity", size: .feature)
            HStack(spacing: 12) {
                SomaArticleCover(tone: .rose, mark: .aspect(.heart), seed: "resting-heart-rate", size: .tile)
                SomaArticleCover(tone: .sage, mark: .aspect(.mind), seed: "breathing", size: .tile)
            }
            HStack(spacing: 12) {
                SomaArticleCover(tone: .tide, mark: .track(.breathe), seed: "recovery-days", size: .tile)
                SomaArticleCover(tone: .sand, mark: .aspect(.gut), seed: "fibre", size: .tile)
            }
            HStack(spacing: 12) {
                SomaArticleCover(tone: .moss, mark: .aspect(.activity), seed: "zone-2", size: .row)
                SomaArticleCover(tone: .clay, mark: .aspect(.body), seed: "strength", size: .row)
                SomaArticleCover(tone: .dusk, mark: .aspect(.sleep), seed: "naps", size: .row)
            }
        }
        .padding()
    }
}
