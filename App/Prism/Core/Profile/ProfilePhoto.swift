//
//  ProfilePhoto.swift
//  Prism
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import SomaUI
import UniformTypeIdentifiers

/// The person's picture: any photo in, a centred square of 512 pixels out, as
/// a JPEG kept beside the profile. ImageIO only, so the same code runs on the
/// phone, the Mac and the headset.
nonisolated enum ProfilePhoto {
    static let side = 512
    static let quality = 0.85

    /// The square JPEG for `data`, or nil when it is not an image.
    static func prepare(_ data: Data, side: Int = ProfilePhoto.side) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // The thumbnail call applies the EXIF orientation, so a portrait
        // straight off the camera stands up.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 4,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let edge = min(image.width, image.height)
        let crop = CGRect(x: (image.width - edge) / 2, y: (image.height - edge) / 2, width: edge, height: edge)
        guard let square = image.cropping(to: crop) else { return nil }
        let out = min(side, edge)
        guard let context = CGContext(
            data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: out, height: out))
        guard let scaled = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The pixel size of an encoded image, for the tests.
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    static func image(_ data: Data?) -> Image? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    /// One or two letters from the first name, or nil without one.
    static func initials(_ name: String?) -> String? {
        guard let name else { return nil }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? nil : letters
    }
}

/// The person as every surface draws them: the photo in a circle, or their
/// initials, or the glyph.
struct ProfileAvatar: View {
    var diameter: CGFloat?
    var fillsPlaceholder = true

    @State private var store = SomaProfileStore.shared

    var body: some View {
        SomaAvatarFace(
            image: store.photoImage,
            initials: ProfilePhoto.initials(store.profile.firstName),
            shape: .circle,
            diameter: diameter,
            fillsPlaceholder: fillsPlaceholder
        )
    }
}
