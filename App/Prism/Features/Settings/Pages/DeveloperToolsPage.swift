//
//  DeveloperToolsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the seven taps open.
///
/// One page holding the tools rather than fifteen rows in the settings root.
/// They sit on their own page so that reading past them is never the cost of
/// coming to the settings root to change the language.
///
/// It ships in Release builds. Nothing here is dangerous to a person who found
/// it: a gallery of components, a seeder that exists only in a debug build on
/// a Simulator, and the switch that puts the section away again.
struct DeveloperToolsPage: View {
    let reveal: DeveloperReveal
    /// Pushes a route onto the sheet's own stack, so this page does not carry a
    /// second navigation stack inside the first.
    let open: (SettingsRoute) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss


    @AppStorage(OnboardingFlow.completedKey) private var hasOnboarded = true

    var body: some View {
        ListScaffold(eyebrow: "Developer", title: "Tools") {

            SomaBrowseSection("Design", items: [
                SettingsRow(.componentGallery, "Component gallery", "square.grid.2x2"),
            ]) { row in
                SomaBrowseRow(symbol: row.symbol, title: row.title) { open(row.route) }
            }

            // Five seconds after the tap, so the app can be put away to see it
            // arrive the way a reminder does. Shown in the app too.
            SomaBrowseSection("Notifications", items: [SettingsItem(id: "test")]) { _ in
                SomaBrowseRow(symbol: "bell.badge", title: "Send a test in 5 seconds") {
                    Task { await SomaNotifications.shared.sendTest() }
                }
            }

            // Clears the first run's flag: the settings sheet goes, and the
            // shell puts onboarding back in place of the tabs.
            SomaBrowseSection("Onboarding", items: [OnboardingReplayRow()]) { row in
                SomaBrowseRow(symbol: row.symbol, title: row.title) {
                    dismiss()
                    hasOnboarded = false
                }
            }

#if DEBUG && targetEnvironment(simulator)
#if canImport(HealthKit)
            VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
                SomaBrowseHeading("Health")
                HealthSeedCard()
            }
#endif
#endif

            VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
                SomaBrowseHeading("This section")

                SomaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.explanation)
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            reveal.hide()
                            dismiss()
                        } label: {
                            Text("Hide developer tools")
                                .somaFont(theme.typography.title)
                                .foregroundStyle(theme.colors.danger.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPress)
                    }
                }
            }
        }
    }

    private static let explanation: LocalizedStringKey = """
    Hiding puts the Developer section away and leaves everything else alone. \
    Seven taps on the version number at the foot of Settings brings it back.
    """
}

#Preview("Developer tools") {
    DeveloperToolsPage(reveal: DeveloperReveal()) { _ in }
}
