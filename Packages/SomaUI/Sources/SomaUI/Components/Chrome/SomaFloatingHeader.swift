//
//  SomaFloatingHeader.swift
//  SomaUI
//

import SwiftUI

/// Chrome pinned across the top of a page, with the content scrolling under it.
///
/// The page's own large title lives in the page and leaves the screen as it
/// scrolls; this smaller centred copy takes over. What the eye reads is a title
/// folding into the chrome, which is why the centred one is hidden until there
/// is something to fold.
///
/// The owner pins it with `.overlay(alignment: .top)` and drives `isScrolled`,
/// usually from `onScrollGeometryChange`.
public struct SomaFloatingHeader<Leading: View, Trailing: View>: View {
    private let title: LocalizedStringResource
    private let isScrolled: Bool
    private let revealsLeadingOnScroll: Bool
    private let leading: Leading
    private let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    public init(
        title: LocalizedStringResource,
        isScrolled: Bool,
        revealsLeadingOnScroll: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.isScrolled = isScrolled
        self.revealsLeadingOnScroll = revealsLeadingOnScroll
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            SomaHeaderBlur()

            ZStack {
                Text(title)
                    .somaFont(theme.typography.headerTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .opacity(isScrolled ? 1 : 0)

                SomaGlassContainer(spacing: 12) {
                    HStack {
                        // Removed while hidden, not faded: a glass shape keeps
                        // painting its capsule under `.opacity(0)` inside a
                        // container, so fading alone leaves a ghost on screen.
                        if !(revealsLeadingOnScroll && !isScrolled) {
                            leading.transition(.opacity)
                        }

                        Spacer()

                        trailing
                    }
                }
            }
            .padding(.horizontal, theme.metrics.spaceL)
            .padding(.top, theme.metrics.spaceS)
        }
        .animation(theme.motion.fade, value: isScrolled)
    }
}

public extension SomaFloatingHeader where Leading == EmptyView {
    /// A header with nothing on its leading side.
    init(
        title: LocalizedStringResource,
        isScrolled: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            isScrolled: isScrolled,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}
