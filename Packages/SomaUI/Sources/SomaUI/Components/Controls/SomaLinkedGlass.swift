//
//  SomaLinkedGlass.swift
//  SomaUI
//

import SwiftUI

/// A row of controls that share one continuous glass shape.
///
/// Not the same thing as one capsule holding several slots. Each member keeps
/// its own button and its own hit area; the material flows between them and the
/// outline closes around the pair, which is what reads as linked.
///
/// The namespace is handed to the content rather than pushed through the
/// environment. An environment value was tried first and the shapes stayed
/// apart: a member reads the environment inside its own modifier, and what it
/// read there did not reach the union. Passing it in is explicit and works.
///
/// ```swift
/// SomaLinkedGlass { glass in
///     Button { } label: { icon }
///         .somaLinked(in: glass)
///     Button { } label: { avatar }
///         .somaLinked(in: glass)
/// }
/// ```
public struct SomaLinkedGlass<Content: View>: View {
    private let spacing: CGFloat
    private let mergeDistance: CGFloat
    private let content: (Namespace.ID) -> Content

    @Namespace private var namespace

    /// - Parameters:
    ///   - spacing: the gap between the members, in layout.
    ///   - mergeDistance: how far apart two shapes still reach for each other.
    ///     This is the container's own spacing, which is a threshold and not a
    ///     gap: set it to the layout spacing and the shapes sit side by side
    ///     without ever joining. It has to be comfortably larger than the gap.
    public init(
        spacing: CGFloat = 6,
        mergeDistance: CGFloat = 28,
        @ViewBuilder content: @escaping (Namespace.ID) -> Content
    ) {
        self.spacing = spacing
        self.mergeDistance = mergeDistance
        self.content = content
    }

    public var body: some View {
        SomaGlassContainer(spacing: mergeDistance) {
            HStack(spacing: spacing) {
                content(namespace)
            }
        }
    }
}

public extension View {
    /// Joins this control to the other members of its ``SomaLinkedGlass``.
    ///
    /// The shape has to be the same across the members, or the join is a step
    /// rather than a curve.
    func somaLinked(
        in namespace: Namespace.ID,
        id: String = "linked",
        shape: some Shape = Capsule()
    ) -> some View {
        somaGlass(.regular, in: shape)
            .somaGlassUnion(id: id, namespace: namespace)
    }
}

#Preview("Linked Glass") {
    ZStack {
        SomaPreviewBackdrop()

        VStack(spacing: 24) {
            SomaLinkedGlass { glass in
                SomaIconLabel(symbol: "square.and.arrow.up").somaLinked(in: glass)
                SomaIconLabel(symbol: "person.fill").somaLinked(in: glass)
            }

            SomaLinkedGlass { glass in
                SomaIconLabel(symbol: "magnifyingglass").somaLinked(in: glass)
                SomaIconLabel(symbol: "questionmark.circle").somaLinked(in: glass)
                SomaIconLabel(symbol: "gearshape").somaLinked(in: glass)
            }
        }
    }
}
