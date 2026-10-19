//
//  PrismApp.swift
//  Prism
//

import SwiftUI
import SwiftData
import SomaUI

@main
struct PrismApp: App {
    /// Light, dark, or the phone's own setting: the one thing about the app's
    /// look a person can change.
    ///
    /// The name is stored rather than the scheme, and a name that no longer
    /// reads falls back to following the phone rather than refusing to draw.
    @AppStorage(AppearanceMode.storageKey) private var modeName = AppearanceMode.fallback.rawValue

    private var mode: AppearanceMode {
        AppearanceMode(storedName: modeName) ?? .fallback
    }

    /// One Health reader for the whole app: the permission sheet is shown once,
    /// and every page reads the same loaded values. Launched with
    /// `-health.empty YES`, it reads an empty store that never asks, which is
    /// how the UI tests keep that sheet off the app. The phone's own motion
    /// reader rides along, asked for in the same moment as Health.
    @State private var health: HealthDashboard

    /// Which tab is showing, so a sheet can send someone to one.
    @State private var router = AppRouter()

    /// The Journal's record, read by Track and by Mind's rituals.
    @State private var journal = JournalStore()

    /// The notification delegate goes in before anything else, so a tap that
    /// cold launches the app follows its link. The one router hands check-in
    /// taps to "Soma asks" and every other link to its page.
    init() {
        let health = HealthDashboard(
            source: HealthDashboard.launchSource(),
            motion: PhoneMotion(source: PhoneMotion.launchSource())
        )
        _health = State(initialValue: health)
        SomaNotificationRouter.install()
        CloudBackground.register()
        #if os(iOS)
        // Before the Health observers start: a wake reuses this dashboard.
        WidgetRefresh.adopt(health: health)
        WidgetRefresh.register()
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @AppStorage("theme.backdrop") private var backdrop = SomaBackdropStyle.gradient.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .somaTheme(.standard)
                // Standard or Landscape: the one thing the two themes change
                // is what sits behind the head of a page.
                .environment(\.somaBackdropStyle, SomaBackdropStyle(rawValue: backdrop) ?? .gradient)
                #if os(iOS)
                .scrollIndicators(.hidden)
                #endif
                // At the root, where it reaches the window: the sheets
                // presented in that window inherit the same scheme.
                .preferredColorScheme(mode.colorScheme)
                .environment(health)
                .environment(router)
                .environment(journal)
                .somaCloud(health: health, journal: journal)
                .somaWidgets(health: health)
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        // A 900x450 default window crops the page grid to two columns and clips
        // the last card.
        .defaultSize(width: 1040, height: 760)
        #endif
    }
}
