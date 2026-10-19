//
//  SomaGlass.swift
//  SomaUI
//

import SwiftUI

/// The glass Soma draws: the system's regular Liquid Glass, tinted or not.
///
/// A mirror of `Glass` with two things left out on purpose. There is no
/// `interactive()`: Soma's glass is inert chrome, an interactive shape under a
/// button swallows its tap, and press feedback is ``SomaGlassPressStyle``.
/// And there is no platform at the call site: visionOS has no Liquid Glass, so
/// `somaGlass(_:in:)` draws a material there instead, and a view written once
/// builds for the phone, the Mac and the headset alike.
///
/// This file is the only one that names the system's glass. `GlassGuardTests`
/// fails on a direct call anywhere else, in the package and in the app.
public struct SomaGlass: Sendable, Equatable {
    let tintColor: Color?

    /// The standard glass.
    public static let regular = SomaGlass(tintColor: nil)

    /// The same glass carrying a colour.
    public func tint(_ color: Color?) -> SomaGlass {
        SomaGlass(tintColor: color)
    }
}

/// How a glass shape arrives and leaves inside its ``SomaGlassContainer``.
///
/// A mirror of `GlassEffectTransition`. visionOS has no container to morph in,
/// so there it changes nothing.
public enum SomaGlassTransition: Sendable {
    /// The shape travels from where it was and stretches into where it lands.
    case matchedGeometry
    /// The shape materialises where it lands.
    case materialize
    /// The shape has no transition of its own.
    case identity
}

/// Glass shapes that sample one backdrop and blend when they come close.
///
/// A `GlassEffectContainer` on iOS and macOS. Its `spacing` is a merge
/// threshold, not a gap: shapes nearer each other than that reach across and
/// join. visionOS has nothing to merge, so there the content stands as it is,
/// each shape on its own material.
public struct SomaGlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
#if os(visionOS)
        content
#else
        GlassEffectContainer(spacing: spacing) { content }
#endif
    }
}

public extension View {
    /// Lays Soma's glass behind this view, in a shape.
    ///
    /// On iOS and macOS this is `glassEffect(_:in:)` with the same glass and the
    /// same shape, so nothing there looks any different for going through it.
    /// visionOS has no Liquid Glass: there the shape is filled with the regular
    /// material and the tint is laid over it. The window is already the
    /// headset's glass, and what sits inside a window is a material, which
    /// keeps glass off glass on that platform too.
    func somaGlass(_ glass: SomaGlass = .regular, in shape: some Shape = Capsule()) -> some View {
#if os(visionOS)
        background {
            shape.fill(.regularMaterial)
                .overlay {
                    if let tint = glass.tintColor { shape.fill(tint) }
                }
        }
#else
        glassEffect(glass.system, in: shape)
#endif
    }

    /// Names this glass shape inside its ``SomaGlassContainer``.
    ///
    /// A shape that leaves one place and appears at another under the same name
    /// is morphed between the two rather than faded out and in. visionOS has no
    /// morph, so the name changes nothing there.
    func somaGlassID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View {
#if os(visionOS)
        self
#else
        glassEffectID(id, in: namespace)
#endif
    }

    /// Joins this glass shape to the others under the same id, so the material
    /// flows between them as one shape. On visionOS each keeps its own.
    func somaGlassUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View {
#if os(visionOS)
        self
#else
        glassEffectUnion(id: id, namespace: namespace)
#endif
    }

    /// How this glass shape arrives and leaves inside its container.
    func somaGlassTransition(_ transition: SomaGlassTransition) -> some View {
#if os(visionOS)
        self
#else
        glassEffectTransition(transition.system)
#endif
    }
}

#if !os(visionOS)
private extension SomaGlass {
    /// The system glass this one stands for.
    var system: Glass {
        guard let tintColor else { return .regular }
        return .regular.tint(tintColor)
    }
}

private extension SomaGlassTransition {
    var system: GlassEffectTransition {
        switch self {
        case .matchedGeometry: .matchedGeometry
        case .materialize: .materialize
        case .identity: .identity
        }
    }
}
#endif
