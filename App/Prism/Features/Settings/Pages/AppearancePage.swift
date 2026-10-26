//
//  AppearancePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Light or dark, and the app icon. Light and dark are a list with a mark
/// against the one in force, as the rest of Settings reads.
///
/// The theme picker (colour field or landscape behind each page) left with the
/// plain grounds of the redesign (owner, 2026-10-23).
struct AppearancePage: View {
    @AppStorage(AppearanceMode.storageKey) private var modeName = AppearanceMode.fallback.rawValue

    @Environment(\.somaTheme) private var theme

    var body: some View {
        ListScaffold(eyebrow: "Settings", title: "Appearance") {
            SettingsSection("Mode") {
                SomaBrowseGroup(AppearanceMode.allCases, hasGlyphs: false) { mode in
                    SomaBrowseRow(
                        title: mode.title,
                        opensSomething: false,
                        action: { modeName = mode.rawValue }
                    ) {
                        if mode.rawValue == modeName {
                            Image(systemName: "checkmark")
                                .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                                .foregroundStyle(theme.colors.inkPrimary.color)
                        }
                    }
                }
            }

#if os(iOS)
            AppIconPicker()
#endif
        }
    }
}

#if os(iOS)
/// The app icons a person can put on the home screen.
///
/// Each alternate is an app icon set in the asset catalog (`AppIcon-<name>`),
/// shipped through `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`, with a
/// small copy in `IconPreview` because an app icon set cannot be drawn as an
/// `Image`. Built from the Gradient designs in the logo library.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = "Default"
    case night = "Night"
    case graphite = "Graphite"
    case ocean = "Ocean"
    case midnight = "Midnight"
    case violet = "Violet"
    case mint = "Mint"
    case sunset = "Sunset"
    case aurora = "Aurora"

    var id: String { rawValue }

    /// The name `setAlternateIconName` takes; nil is the primary icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    var preview: String { "IconPreview-\(rawValue)" }

    var title: LocalizedStringResource {
        switch self {
        case .standard: "Default"
        case .night: "Night"
        case .graphite: "Graphite"
        case .ocean: "Ocean"
        case .midnight: "Midnight"
        case .violet: "Violet"
        case .mint: "Mint"
        case .sunset: "Sunset"
        case .aurora: "Aurora"
        }
    }

    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

/// A grid of icon tiles; the one in force carries a ring.
private struct AppIconPicker: View {
    @Environment(\.somaTheme) private var theme
    @State private var chosen = AppIconChoice.current

    var body: some View {
        let metrics = theme.metrics
        let tile = metrics.minimumTapTarget + metrics.cardSpacing

        VStack(alignment: .leading, spacing: metrics.browseHeadingSpacing) {
            Text("App icon")
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: tile), spacing: metrics.cardSpacing)],
                spacing: metrics.cardSpacing
            ) {
                ForEach(AppIconChoice.allCases) { choice in
                    Button { select(choice) } label: {
                        VStack(spacing: metrics.cardHeaderSpacing) {
                            Image(choice.preview)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: tile, height: tile)
                                .clipShape(.rect(cornerRadius: tile * 0.225, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                                        .strokeBorder(
                                            choice == chosen ? theme.colors.accent.color : theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity),
                                            lineWidth: choice == chosen ? 2 : 0.5
                                        )
                                }
                            Text(choice.title)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(choice == chosen ? theme.colors.inkPrimary.color : theme.colors.inkSecondary.color)
                        }
                    }
                    .buttonStyle(.somaGlassPress)
                    .accessibilityLabel(Text(choice.title))
                    .accessibilityAddTraits(choice == chosen ? .isSelected : [])
                }
            }
        }
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != chosen, UIApplication.shared.supportsAlternateIcons else { return }
        chosen = choice
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.iconName)
            } catch {
                chosen = AppIconChoice.current
            }
        }
    }
}
#endif

#Preview("Appearance") {
    AppearancePage()
}
