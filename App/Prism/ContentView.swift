//
//  ContentView.swift
//  Prism
//

import SwiftUI
import SwiftData
import SomaUI

/// The app's shell: the pages under the system's own bottom chrome.
///
/// One `TabView` serves every context. On a phone it draws the native Liquid
/// Glass tab bar, three tabs in one capsule and Ask, the Soma mark, in its own
/// disc at the trailing edge; scrolling down minimizes the bar, all
/// system-owned glass and motion. On a roomy screen and on the Mac the same
/// `TabView` becomes the system sidebar, Ask among its rows, and its foot
/// carries the app wide controls.
struct ContentView: View {
    @State private var destination: SidebarDestination?
    @Environment(AppRouter.self) private var router
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    /// Set when the first run finishes; Developer tools clears it to replay.
    @AppStorage(OnboardingFlow.completedKey) private var hasOnboarded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The first run stands in for the tabs rather than covering them, so
        // no tab's `.task` puts Health's sheet up before its own step does.
        Group {
            if hasOnboarded {
                shell
            } else {
                OnboardingFlow { hasOnboarded = true }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : theme.motion.tabEntrance, value: hasOnboarded)
        .environment(SomaProfileStore.shared)
    }

    private var shell: some View {
        tabs
            .tabViewStyle(.sidebarAdaptable)
            .tabViewSidebarBottomBar {
                SidebarFooter(shareText: TodayShareText.make(from: health)) { destination = $0 }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .modifier(NativeTabChrome())
            .tint(theme.colors.accent.color)
            .sheet(item: $destination) { $0.page }
            .globalIntentRouting()
            .somaDeepLinks()
            // Soma asks: once per window when the app becomes active, and
            // whenever a reminder or a screen opens it.
            .checkInPrompt()
    }

    /// Copy and symbols live at the call site, never inside the chrome.
    ///
    /// Three tabs: Pulse is the day, Longevity is months and years, Track is
    /// what you log and do. Their glyphs are Soma's own custom symbols in the
    /// asset catalog (the sun on its path, the infinity whose far loop grows,
    /// the tally of five), because a tab item renders an image and a title,
    /// never an arbitrary view.
    ///
    /// Ask is a tab with the `.prominent` role, which is what detaches it into
    /// its own disc at the end of the bar. The role says the destination matters
    /// most; it is still a destination, so it opens a page and not a sheet. Its
    /// glyph is the Soma mark.
    private var tabs: some View {
        @Bindable var router = router

        return TabView(selection: $router.selection) {
            Tab("Pulse", image: "soma.pulse", value: "pulse") { PulsePage().somaTabEntrance(isActive: router.selection == "pulse") }
            Tab("Longevity", image: "soma.longevity", value: "longevity") { LongevityPage().somaTabEntrance(isActive: router.selection == "longevity") }
            Tab("Track", image: "soma.track", value: "track") { TrackPage().somaTabEntrance(isActive: router.selection == "track") }
            Tab("Ask Soma", image: "soma.mark", value: "ask", role: .prominent) { AskPage().somaTabEntrance(isActive: router.selection == "ask") }
        }
    }
}

/// The native bottom chrome: the system tab bar minimizing on scroll-down.
///
/// iPhone and iPad only: the `.onScrollDown` behaviour is unavailable elsewhere.
/// The Mac and the headset draw the sidebar instead, so there is nothing to
/// stand in for there.
private struct NativeTabChrome: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.tabBarMinimizeBehavior(.onScrollDown)
#else
        content
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
        .environment(HealthDashboard())
        .environment(AppRouter())
        .environment(JournalStore(url: nil))
}
