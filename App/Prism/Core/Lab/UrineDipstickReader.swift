//
//  UrineDipstickReader.swift
//  Prism
//
//  Reads a ten pad urine dipstick from a photo, on the device. The photo is
//  cropped to the camera's guide frame first, so the strip lies across it
//  with its white handle at the leading end; the reader then:
//
//  1. samples the handle, the strip's own white, and takes it as the light's
//     colour (white balance, von Kries: each channel divided by the white's,
//     in linear light);
//  2. samples the middle of each pad, a median per channel so a glint or a
//     shadow at the edge does not move it;
//  3. corrects each pad by the white, converts it to CIELAB, and picks the
//     chart step nearest in colour (CIE76 delta E).
//
//  The result is a colour match, not chemistry: lighting, timing, the brand's
//  own chart and the camera all move it. Every reading is marked approximate,
//  a match that is far from every step is marked unsure, and the person
//  checks each pad against their bottle before saving. Never a diagnosis.
//
//  The matching (`match`) and the colour maths are pure and isolated so they
//  can be tested on synthetic colours; the sampling reads a CGImage.
//

import Foundation
import CoreGraphics

/// A colour in sRGB, each channel 0 to 1.
nonisolated struct UrineRGB: Sendable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    /// The sRGB transfer curve undone (IEC 61966-2-1).
    var linear: (Double, Double, Double) {
        func f(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return (f(red), f(green), f(blue))
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(linear r: Double, _ g: Double, _ b: Double) {
        func f(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        self.init(red: f(r), green: f(g), blue: f(b))
    }

    /// CIELAB under D65.
    var lab: (l: Double, a: Double, b: Double) {
        let (r, g, b) = linear
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.0
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}

/// One pad as read: the step it matched, how far the colour was from it,
/// and the colour itself after the white balance.
nonisolated struct UrinePadReading: Sendable, Hashable, Identifiable {
    var markerID: String
    var stepIndex: Int
    var deltaE: Double
    var color: UrineRGB

    var id: String { markerID }

    /// Further than this from every step, the match is a guess.
    static let unsureDeltaE = 18.0

    var isUnsure: Bool { deltaE > Self.unsureDeltaE }
}

/// Where things sit on the guide frame, as fractions of its width and height.
/// The camera draws its overlay from the same numbers, so what the person
/// lines up is what the reader samples.
nonisolated struct UrineStripLayout: Sendable, Equatable {
    /// The white handle, at the leading end.
    var handle: ClosedRange<Double> = 0.03...0.20
    /// The run of pads.
    var pads: ClosedRange<Double> = 0.25...0.99
    var count = 10
    /// The share of a pad's pitch that is sampled.
    var sampleWidth = 0.45
    /// The band across the strip that is sampled.
    var sampleHeight: ClosedRange<Double> = 0.32...0.68

    static let standard = UrineStripLayout()

    /// The centre of pad `index`, from the handle.
    func centre(_ index: Int) -> Double {
        let pitch = (pads.upperBound - pads.lowerBound) / Double(count)
        return pads.lowerBound + pitch * (Double(index) + 0.5)
    }

    var pitch: Double { (pads.upperBound - pads.lowerBound) / Double(count) }
}

nonisolated enum UrineDipstickReader {
    // MARK: Colour maths

    /// CIE76: the straight distance in CIELAB.
    static func deltaE(_ a: UrineRGB, _ b: UrineRGB) -> Double {
        let p = a.lab, q = b.lab
        return ((p.l - q.l) * (p.l - q.l) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
    }

    /// A colour seen under the light that made `white` look as it does,
    /// brought back to what it would be under neutral light. Divides in
    /// linear light, channel by channel; a white too dark to trust leaves
    /// the colour as it was.
    static func whiteBalanced(_ color: UrineRGB, white: UrineRGB) -> UrineRGB {
        let (r, g, b) = color.linear
        let (wr, wg, wb) = white.linear
        guard min(wr, wg, wb) > 0.02 else { return color }
        return UrineRGB(linear: r / wr, g / wg, b / wb)
    }

    /// The chart step nearest a balanced pad colour, and how far it was.
    static func match(_ color: UrineRGB, steps: [UrineDipstickStep]) -> (index: Int, deltaE: Double)? {
        steps.indices.map { ($0, deltaE(color, steps[$0].rgb)) }.min { $0.1 < $1.1 }
    }

    /// Every pad matched from colours already sampled: `pads` in strip order
    /// from the handle, `white` from the handle.
    static func read(pads: [UrineRGB], white: UrineRGB, order: [String] = UrineCatalog.padOrder) -> [UrinePadReading] {
        zip(order, pads).compactMap { id, raw in
            guard let marker = UrineCatalog.marker(id: id) else { return nil }
            let balanced = whiteBalanced(raw, white: white)
            guard let hit = match(balanced, steps: marker.steps) else { return nil }
            return UrinePadReading(markerID: id, stepIndex: hit.index, deltaE: hit.deltaE, color: balanced)
        }
    }

    // MARK: Sampling

    /// The strip read from an image already cropped to the guide frame.
    /// `reversed` is for a brand whose pads run from the tip: the handle is
    /// still sampled at the leading end, the pads are assigned the other way.
    static func read(image: CGImage, layout: UrineStripLayout = .standard, reversed: Bool = false) -> [UrinePadReading]? {
        guard let bitmap = Bitmap(image) else { return nil }
        let white = bitmap.median(x: layout.handle, y: layout.sampleHeight, skipGlare: false)
        guard let white else { return nil }
        var pads: [UrineRGB] = []
        for index in 0..<layout.count {
            let centre = layout.centre(index)
            let half = layout.pitch * layout.sampleWidth / 2
            guard let colour = bitmap.median(x: (centre - half)...(centre + half), y: layout.sampleHeight, skipGlare: true) else { return nil }
            pads.append(colour)
        }
        let order = reversed ? Array(UrineCatalog.padOrder.reversed()) : UrineCatalog.padOrder
        return read(pads: pads, white: white, order: order).sorted {
            (UrineCatalog.padOrder.firstIndex(of: $0.markerID) ?? 0) < (UrineCatalog.padOrder.firstIndex(of: $1.markerID) ?? 0)
        }
    }

    /// An image drawn into eight bit RGBA at a size small enough to read fast.
    private struct Bitmap {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        init?(_ image: CGImage, maxWidth: Int = 800) {
            let scale = min(1, Double(maxWidth) / Double(max(image.width, 1)))
            let width = max(1, Int(Double(image.width) * scale))
            let height = max(1, Int(Double(image.height) * scale))
            self.width = width
            self.height = height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            pixels = buffer
        }

        /// The median colour of a box given in fractions, top left origin.
        /// With `skipGlare`, near white specks (a reflection on a wet pad)
        /// are left out when anything else is there.
        func median(x: ClosedRange<Double>, y: ClosedRange<Double>, skipGlare: Bool) -> UrineRGB? {
            let x0 = max(0, Int(x.lowerBound * Double(width))), x1 = min(width - 1, Int(x.upperBound * Double(width)))
            let y0 = max(0, Int(y.lowerBound * Double(height))), y1 = min(height - 1, Int(y.upperBound * Double(height)))
            guard x1 >= x0, y1 >= y0 else { return nil }
            var reds: [UInt8] = [], greens: [UInt8] = [], blues: [UInt8] = []
            var glare: [(UInt8, UInt8, UInt8)] = []
            for row in y0...y1 {
                for column in x0...x1 {
                    let i = (row * width + column) * 4
                    let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                    if skipGlare && min(r, g, b) > 245 { glare.append((r, g, b)); continue }
                    reds.append(r); greens.append(g); blues.append(b)
                }
            }
            if reds.isEmpty {
                reds = glare.map(\.0); greens = glare.map(\.1); blues = glare.map(\.2)
            }
            guard !reds.isEmpty else { return nil }
            func mid(_ values: [UInt8]) -> Double { Double(values.sorted()[values.count / 2]) / 255 }
            return UrineRGB(red: mid(reds), green: mid(greens), blue: mid(blues))
        }
    }
}
