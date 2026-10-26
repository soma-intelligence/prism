//
//  SomaBackdropStyle.swift
//  SomaUI
//

import SwiftUI

/// What sits behind the head of a page: the aspect's drifting colour field, or
/// a landscape photograph for that aspect.
///
/// The two app themes differ only here (owner, 2026-10-03): Standard keeps the
/// gradient, Landscape swaps it for photography and leaves every colour, type
/// and measure as it is.
public enum SomaBackdropStyle: String, CaseIterable, Sendable, Identifiable {
    case gradient
    case landscape

    public var id: String { rawValue }

    public var title: LocalizedStringResource {
        switch self {
        case .gradient: "Standard"
        case .landscape: "Landscape"
        }
    }

    /// The asset name of an aspect's photograph in the app's catalog.
    public static func photoName(for aspect: SomaAspect) -> String {
        "Landscape-\(aspect.rawValue)"
    }
}

public extension EnvironmentValues {
    @Entry var somaBackdropStyle: SomaBackdropStyle = .gradient
}

/// Looks up an aspect's landscape photograph in the app's asset catalog.
///
/// The photographs ship at 1600 by 2400 pixels, fifteen megabytes each once
/// decoded, and the backdrop shows the top of one across the width of the
/// page. So each is decoded once, off the main actor, at the width it is
/// drawn, and kept: a page that opens again draws it at once.
@MainActor
enum SomaLandscapePhoto {
    private static var exists: [String: Bool] = [:]
    private static var decoded: [String: Image] = [:]

    /// Whether the catalog holds a photograph for this aspect. Asked once.
    static func hasPhoto(for aspect: SomaAspect) -> Bool {
        let name = SomaBackdropStyle.photoName(for: aspect)
        if let known = exists[name] { return known }
        #if canImport(UIKit)
        let found = UIImage(named: name) != nil
        #elseif canImport(AppKit)
        let found = NSImage(named: name) != nil
        #else
        let found = false
        #endif
        exists[name] = found
        return found
    }

    /// The photograph already decoded for this aspect at this width, if any.
    static func cached(for aspect: SomaAspect, pixelWidth: Int) -> Image? {
        #if canImport(UIKit)
        decoded[key(aspect, pixelWidth)]
        #else
        hasPhoto(for: aspect) ? Image(SomaBackdropStyle.photoName(for: aspect)) : nil
        #endif
    }

    /// Decodes the photograph at `pixelWidth`, or at its own size when that is
    /// smaller, without holding the main actor while it does.
    static func load(for aspect: SomaAspect, pixelWidth: Int) async -> Image? {
        if let image = cached(for: aspect, pixelWidth: pixelWidth) { return image }
        guard hasPhoto(for: aspect) else { return nil }
        let name = SomaBackdropStyle.photoName(for: aspect)
        #if canImport(UIKit)
        guard let source = UIImage(named: name) else { return nil }
        let width = min(CGFloat(pixelWidth), source.size.width * source.scale)
        let size = CGSize(width: width, height: width * source.size.height / max(source.size.width, 1))
        let thumbnail = await source.byPreparingThumbnail(ofSize: size) ?? source
        let image = Image(uiImage: thumbnail)
        decoded[key(aspect, pixelWidth)] = image
        return image
        #else
        return Image(name)
        #endif
    }

    private static func key(_ aspect: SomaAspect, _ pixelWidth: Int) -> String {
        "\(aspect.rawValue)@\(pixelWidth)"
    }

    #if canImport(UIKit)
    /// The decoded photographs, the most recent few.
    @MainActor
    private final class Store {
        static let shared = Store()
        private let cache: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 3
            return cache
        }()

        func image(named name: String) -> UIImage? { cache.object(forKey: name as NSString) }
        func keep(_ image: UIImage, named name: String) { cache.setObject(image, forKey: name as NSString) }
    }
    #endif
}
