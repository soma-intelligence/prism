//
//  TabPageChrome.swift
//  Prism
//

import SwiftUI
import SomaUI

/// One part of a tab, as the segmented control in its top bar offers it.
///
/// Copy lives with the section, never in the chrome: each page names its own
/// parts, and the chrome only lays them out.
protocol PageSection: Hashable, CaseIterable where AllCases == [Self] {
    var title: LocalizedStringResource { get }
}

extension View {
    /// The top bar every tab page carries: the account on the leading edge, the
    /// page's parts in the middle, notifications on the trailing edge.
    func tabPageChrome<Section: PageSection>(
        title: LocalizedStringResource,
        section: Binding<Section>
    ) -> some View {
        modifier(TabPageChrome(title: title) {
            SomaSegmentedControl(
                segments: Section.allCases.map { SomaSegment(id: $0, title: $0.title) },
                selection: section
            )
        })
    }

    /// The same top bar for a page in one piece. Its title takes the middle.
    func tabPageChrome(title: LocalizedStringResource) -> some View {
        modifier(TabPageChrome(title: title) { EmptyView() })
    }
}

/// The navigation bar's own toolbar, not an overlay drawn over the page.
///
/// The bar is the system's, so the page scrolls under it with the system's edge
/// effect, the account and the bell are the system's glass buttons, and a page
/// pushed onto the stack gets the system's back button in their place. Only the
/// segmented control in the middle is Soma's, and it brings its own glass, so the
/// shared background the toolbar would lay behind it is switched off.
///
/// The account button lives here on a phone only. Where there is a sidebar, the
/// account row already sits at its foot, and a second door into the same room
/// says the same thing twice.
private struct TabPageChrome<Switcher: View>: ViewModifier {
    let title: LocalizedStringResource
    let switcher: Switcher

    @Environment(\.somaTheme) private var theme
    @State private var isShowingSettings = false
    @State private var isShowingNotifications = false

#if os(macOS)
    private var hasSidebar: Bool { true }
#else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var hasSidebar: Bool { sizeClass == .regular }
#endif

    init(title: LocalizedStringResource, @ViewBuilder switcher: () -> Switcher) {
        self.title = title
        self.switcher = switcher()
    }

    func body(content: Content) -> some View {
        content
            // Still set where the control takes the middle: it names the window
            // on a Mac and the page to VoiceOver.
            .navigationTitle(Text(title))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if !hasSidebar {
                    ToolbarItem(placement: .navigation) {
                        // No picture yet, so the button shows a glyph. An
                        // invented face would be worse than an empty one. A bare
                        // symbol rather than `SomaAvatarFace`: the bar sizes its
                        // own glyphs, so this disc matches the bell's, where a
                        // drawn face grows the glass around it.
                        Button { isShowingSettings = true } label: {
                            if let photo = SomaProfileStore.shared.photoImage {
                                photo
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: theme.metrics.browseGlyphColumn, height: theme.metrics.browseGlyphColumn)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(theme.colors.inkPrimary.color)
                            }
                        }
                        .accessibilityLabel("Profile")
                    }
                }

                if Switcher.self != EmptyView.self {
                    ToolbarItem(placement: .principal) { switcher }
#if !os(visionOS)
                        // Liquid Glass only: visionOS has no shared background to hide.
                        .sharedBackgroundVisibility(.hidden)
#endif
                }

                ToolbarItem(placement: .primaryAction) {
                    Button { isShowingNotifications = true } label: {
                        Image(systemName: "bell.and.waveform")
                            .foregroundStyle(theme.colors.inkPrimary.color)
                            .overlay(alignment: .topTrailing) {
                                if SomaNotifications.shared.unreadCount > 0 {
                                    Circle()
                                        .fill(theme.colors.accent.color)
                                        .frame(width: theme.metrics.chartDotDiameter, height: theme.metrics.chartDotDiameter)
                                }
                            }
                    }
                    .accessibilityLabel("Notifications")
                    .accessibilityValue(SomaNotifications.shared.unreadCount > 0 ? "Unread" : "")
                }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsSheet() }
            .sheet(isPresented: $isShowingNotifications) { NotificationCenterSheet() }
    }
}
