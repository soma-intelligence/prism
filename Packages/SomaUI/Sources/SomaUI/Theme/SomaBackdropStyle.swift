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

/// Looks up an aspect's landscape photograph in the app's asset catalog,
/// decoded ahead of the frame that draws it.
///
/// A photograph straight from the catalog is decoded the first time it is
/// drawn, so the head of a page could open a frame without it and pop it in
/// a beat later. Here the decoded bitmap is kept (the last few, the
/// photographs are a few megabytes each once decoded) and a page that opens
/// before ``prepare(_:)`` finished decodes its photograph on the spot, so
/// its first frame is whole either way.
public enum SomaLandscapePhoto {
    /// Decodes the photographs of these aspects off the main thread, so the
    /// pages that show them open with them already drawn. Call it early,
    /// once the Landscape theme is known to be on.
    public static func prepare(_ aspects: [SomaAspect]) async {
        #if canImport(UIKit)
        for aspect in aspects {
            let name = SomaBackdropStyle.photoName(for: aspect)
            if await MainActor.run(body: { Store.shared.image(named: name) != nil }) { continue }
            guard let decoded = await UIImage(named: name)?.byPreparingForDisplay() else { continue }
            await MainActor.run { Store.shared.keep(decoded, named: name) }
        }
        #endif
    }

    @MainActor
    static func image(for aspect: SomaAspect) -> Image? {
        let name = SomaBackdropStyle.photoName(for: aspect)
        #if canImport(UIKit)
        if let kept = Store.shared.image(named: name) { return Image(uiImage: kept) }
        guard let photo = UIImage(named: name) else { return nil }
        let decoded = photo.preparingForDisplay() ?? photo
        Store.shared.keep(decoded, named: name)
        return Image(uiImage: decoded)
        #elseif canImport(AppKit)
        guard NSImage(named: name) != nil else { return nil }
        return Image(name)
        #else
        return nil
        #endif
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
