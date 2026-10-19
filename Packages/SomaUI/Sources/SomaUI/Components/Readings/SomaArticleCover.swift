//
//  SomaArticleCover.swift
//  SomaUI
//

import SwiftUI

/// The picture over an article: its photograph when it has one, otherwise an
/// illustration generated from the topic's hue, the way Apple Health paints a
/// story card.
///
/// The generated cover is the hue's two stop gradient, a few soft rings placed
/// from the article's own seed (so a cover is the same every time it draws and
/// differs from its neighbour's) and the topic's glyph. While a photograph
/// loads, or when it fails, the generated cover stands in: the frame never
/// shows a spinner or an empty box.
public struct SomaArticleCover: View {
    public enum Size: Sendable {
        /// The featured card on the library page.
        case feature
        /// A tile in the grid.
        case tile
        /// The head of the reader page.
        case reader
    }

    private let hue: SomaHealthHue
    private let symbol: String
    private let seed: String
    private let imageURL: URL?
    private let asset: String?
    private let size: Size

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - hue: the topic's Health hue.
    ///   - symbol: the SF Symbol the topic is drawn with.
    ///   - seed: anything stable about the article, its slug say.
    ///   - imageURL: the photograph, when the article has one online.
    ///   - asset: the photograph in the app's asset catalog, which wins over
    ///     `imageURL`: it is there on the first frame and offline.
    public init(hue: SomaHealthHue, symbol: String, seed: String, imageURL: URL? = nil, asset: String? = nil, size: Size) {
        self.hue = hue
        self.symbol = symbol
        self.seed = seed
        self.imageURL = imageURL
        self.asset = asset
        self.size = size
    }

    public var body: some View {
        let metrics = theme.metrics
        let shape = RoundedRectangle(cornerRadius: cornerRadius(metrics), style: .continuous)

        Color.clear
            .frame(height: height(metrics))
            .frame(maxWidth: .infinity)
            .overlay { generated }
            .overlay {
                if let asset {
                    Image(asset).resizable().scaledToFill()
                } else if let imageURL {
                    AsyncImage(url: imageURL, transaction: Transaction(animation: reduceMotion ? nil : .easeOut(duration: theme.motion.pressDuration * 2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private var generated: some View {
        let metrics = theme.metrics
        let rings = SomaArticleCoverRings(seed: seed)
        // The cover keeps its hue on both grounds, so what is drawn on it
        // stays light on both, like the move written on an orb.
        let light = theme.colors.onOrb.color

        return ZStack {
            LinearGradient(colors: [hue.start.color, hue.end.color], startPoint: rings.gradientStart, endPoint: rings.gradientEnd)
            Canvas { context, canvasSize in
                let side = max(canvasSize.width, canvasSize.height)
                for ring in rings.rings {
                    let center = CGPoint(x: ring.x * canvasSize.width, y: ring.y * canvasSize.height)
                    let radius = ring.radius * side
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(light.opacity(metrics.articleCoverRingOpacity)),
                                   lineWidth: ring.width * side)
                }
            }
            Image(systemName: symbol)
                .font(.system(size: glyphSize(metrics), weight: .medium))
                .foregroundStyle(light.opacity(metrics.articleCoverGlyphOpacity))
        }
    }

    private func height(_ metrics: SomaMetrics) -> CGFloat {
        switch size {
        case .feature: metrics.articleFeatureCoverHeight
        case .tile: metrics.articleTileCoverHeight
        case .reader: metrics.articleReaderCoverHeight
        }
    }

    private func cornerRadius(_ metrics: SomaMetrics) -> CGFloat {
        size == .tile ? metrics.articleTileCornerRadius : metrics.articleCoverCornerRadius
    }

    private func glyphSize(_ metrics: SomaMetrics) -> CGFloat {
        size == .tile ? metrics.articleTileGlyphSize : metrics.articleFeatureGlyphSize
    }
}

/// Where a generated cover's rings sit, drawn from a seed so the same article
/// always gets the same picture. Proportions of the cover, not points.
struct SomaArticleCoverRings: Equatable {
    struct Ring: Equatable {
        var x: Double
        var y: Double
        var radius: Double
        var width: Double
    }

    var rings: [Ring]
    var gradientStart: UnitPoint
    var gradientEnd: UnitPoint

    init(seed: String) {
        // FNV-1a: `hashValue` is salted per launch, and a cover must not
        // change between two launches.
        var state: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
        func next() -> Double {
            // xorshift64*, enough for placing a few circles.
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return Double((state &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53)
        }

        let centerX = 0.2 + next() * 0.6
        let centerY = 0.2 + next() * 0.6
        var rings: [Ring] = []
        let count = 3 + Int(next() * 3)
        for index in 0..<count {
            rings.append(Ring(x: centerX, y: centerY,
                              radius: 0.16 + Double(index) * (0.12 + next() * 0.05),
                              width: 0.004 + next() * 0.01))
        }
        self.rings = rings
        let flip = next() < 0.5
        gradientStart = flip ? .topLeading : .topTrailing
        gradientEnd = flip ? .bottomTrailing : .bottomLeading
    }
}

#Preview("Covers") {
    ScrollView {
        VStack(spacing: 12) {
            SomaArticleCover(hue: .sleep, symbol: "moon.stars.fill", seed: "sleep-regularity", size: .feature)
            HStack(spacing: 12) {
                SomaArticleCover(hue: .heart, symbol: "heart.fill", seed: "resting-heart-rate", size: .tile)
                SomaArticleCover(hue: .mind, symbol: "wind", seed: "breathing", size: .tile)
            }
        }
        .padding()
    }
}
