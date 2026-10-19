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
enum SomaLandscapePhoto {
    static func image(for aspect: SomaAspect) -> Image? {
        let name = SomaBackdropStyle.photoName(for: aspect)
        #if canImport(UIKit)
        guard UIImage(named: name) != nil else { return nil }
        #elseif canImport(AppKit)
        guard NSImage(named: name) != nil else { return nil }
        #endif
        return Image(name)
    }
}
