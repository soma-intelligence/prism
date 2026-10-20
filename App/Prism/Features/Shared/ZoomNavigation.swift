//
//  ZoomNavigation.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The zoom a tile opens into: the tile grows into the page it leads to, and
/// the page shrinks back into the tile on the way out.
///
/// Each tab's stack owns one namespace and hands it down through the
/// environment, so a tile anywhere in the tab marks itself as a source by id
/// and the destination names the same id. The zoom is the system's own
/// (`.navigationTransition(.zoom)`), which also gives the interactive
/// pull-down to dismiss. Where the platform has no zoom (the Mac), the push is
/// the ordinary one.
extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

extension View {
    /// Marks this tile as where the page with `id` zooms out of.
    ///
    /// - Parameter cornerRadius: the tile's own corner, when it is not a
    ///   card's (an article's cover, say), so the zoom grows from its shape.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, cornerRadius: CGFloat? = nil) -> some View {
        modifier(ZoomSource(id: AnyHashable(id), cornerRadius: cornerRadius))
    }

    /// Makes this page zoom out of the tile marked with the same `id`.
    @ViewBuilder
    func zoomDestination(_ id: some Hashable) -> some View {
        modifier(ZoomDestination(id: AnyHashable(id)))
    }
}

private struct ZoomSource: ViewModifier {
    let id: AnyHashable
    let cornerRadius: CGFloat?
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.somaTheme) private var theme

    func body(content: Content) -> some View {
#if os(iOS)
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: cornerRadius ?? theme.metrics.cardCornerRadius, style: .continuous))
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct ZoomDestination: ViewModifier {
    let id: AnyHashable
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        // Every pushed page scrolls under the same bar as the tab pages, so it
        // takes the same top edge.
        zoomed(content.somaScrollEdgeFade())
    }

    @ViewBuilder
    private func zoomed(_ page: some View) -> some View {
#if os(iOS)
        if let namespace {
            page.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            page
        }
#else
        page
#endif
    }
}
