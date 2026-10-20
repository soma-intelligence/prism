//
//  SomaMuscleFigureArt.swift
//  SomaUI
//

import CoreGraphics
import Foundation
import ImageIO

/// One side of the rendered muscle figure, read once from the package's
/// `MuscleFigure` resources: the body's light and shade with its silhouette,
/// and one mask per muscle, each where it shows from this side.
///
/// The images are rendered from Z-Anatomy, the libre 3D atlas of anatomy
/// (CC BY-SA 4.0), based on BodyParts3D, The Database Center for Life
/// Science (CC BY-SA 2.1 Japan), and are shared under CC BY-SA 4.0; see
/// `Resources/MuscleFigure/NOTICE.txt`. `Soma_iOS/scripts/muscle-render`
/// makes them.
struct SomaMuscleFigureArt: @unchecked Sendable {
    enum Side: String, Sendable, CaseIterable {
        case front, back
    }

    /// Where one muscle shows on this side.
    struct Mask: @unchecked Sendable {
        let muscle: SomaMuscle
        /// White, its alpha the muscle's coverage.
        let image: CGImage
        /// Its place in the figure, in the figure's pixels.
        let frame: CGRect
        /// The coverage of each pixel, 0 to 255, row by row.
        let coverage: [UInt8]

        /// The coverage at a pixel of the figure, 0 off the mask.
        func coverage(at pixel: CGPoint) -> UInt8 {
            let x = Int(pixel.x - frame.minX)
            let y = Int(pixel.y - frame.minY)
            let width = Int(frame.width)
            guard x >= 0, y >= 0, x < width, y < Int(frame.height), coverage.count == width * Int(frame.height) else { return 0 }
            return coverage[y * width + x]
        }
    }

    let side: Side
    /// The body's light and shade as grey, its alpha the silhouette.
    let image: CGImage
    /// The figure's size in pixels.
    let size: CGSize
    /// Pixels to a point at the size the art was made for.
    let scale: CGFloat
    let masks: [Mask]

    static let front = load(.front)
    static let back = load(.back)

    static func of(_ side: Side) -> SomaMuscleFigureArt? {
        side == .front ? front : back
    }

    /// Width over height of one side, as `figure.json` sizes it (494 by
    /// 1200). A constant, so laying the map out never decodes the art.
    static let aspect: CGFloat = 494.0 / 1200.0

    /// Whether both sides have been decoded; until then a map draws its
    /// frame empty rather than decode on the main thread.
    @MainActor static private(set) var isReady = false

    /// Decodes both sides off the main thread, once. Safe to call from every
    /// map that appears: later calls return at once.
    static func prepare() async {
        if await MainActor.run(body: { isReady }) { return }
        await Task.detached(priority: .userInitiated) {
            _ = front
            _ = back
        }.value
        await MainActor.run { isReady = true }
    }

    /// Where the figure sits in a frame of `size`: scaled to fit and centred.
    func fit(in size: CGSize) -> CGRect {
        let scale = min(size.width / self.size.width, size.height / self.size.height)
        let width = self.size.width * scale
        let height = self.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The muscle under a point of a frame of `size`: the one that covers
    /// that pixel most, nil on the figure itself or off it.
    func muscle(at point: CGPoint, in size: CGSize) -> SomaMuscle? {
        let rect = fit(in: size)
        guard rect.width > 0, rect.contains(point) else { return nil }
        let pixel = CGPoint(
            x: (point.x - rect.minX) / rect.width * self.size.width,
            y: (point.y - rect.minY) / rect.height * self.size.height
        )
        var best: (muscle: SomaMuscle, coverage: UInt8)?
        for mask in masks {
            let coverage = mask.coverage(at: pixel)
            if coverage > (best?.coverage ?? 96) { best = (mask.muscle, coverage) }
        }
        return best?.muscle
    }

    // MARK: Loading

    private struct Manifest: Decodable {
        struct View: Decodable {
            let size: [Int]
            let masks: [String: [Int]]
        }

        let scale: Double
        let views: [String: View]
    }

    private static let folder = "MuscleFigure"

    private static func load(_ side: Side) -> SomaMuscleFigureArt? {
        guard let url = Bundle.module.url(forResource: "figure", withExtension: "json", subdirectory: folder),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let view = manifest.views[side.rawValue], view.size.count == 2,
              let image = png(named: "figure_\(side.rawValue)")
        else { return nil }
        var masks: [Mask] = []
        for muscle in SomaMuscle.allCases {
            guard let box = view.masks[muscle.rawValue], box.count == 4,
                  let mask = png(named: "mask_\(muscle.rawValue)_\(side.rawValue)"),
                  mask.width == box[2], mask.height == box[3]
            else { continue }
            masks.append(Mask(
                muscle: muscle,
                image: mask,
                frame: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]),
                coverage: alpha(of: mask)
            ))
        }
        return SomaMuscleFigureArt(
            side: side,
            image: image,
            size: CGSize(width: view.size[0], height: view.size[1]),
            scale: manifest.scale,
            masks: masks
        )
    }

    private static func png(named name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: folder),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    /// The image's alpha, one byte a pixel. Alpha is never colour managed,
    /// so drawing into an RGBA bitmap and keeping every fourth byte reads it
    /// exactly.
    private static func alpha(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
