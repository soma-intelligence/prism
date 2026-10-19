//
//  AppearancePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The theme, light or dark, and the app icon.
///
/// The theme only changes what sits behind the head of a page (owner,
/// 2026-10-03): the aspect's colour field, or a landscape photograph. Light
/// and dark are a list with a mark against the one in force, as the rest of
/// Settings reads.
struct AppearancePage: View {
    @AppStorage(AppearanceMode.storageKey) private var modeName = AppearanceMode.fallback.rawValue
    @AppStorage("theme.backdrop") private var backdrop = SomaBackdropStyle.gradient.rawValue

    @Environment(\.somaTheme) private var theme

    var body: some View {
        ListScaffold(eyebrow: "Settings", title: "Appearance") {
            SettingsSection("Theme") {
                HStack(spacing: theme.metrics.cardSpacing) {
                    ForEach(SomaBackdropStyle.allCases) { style in
                        ThemeTile(style: style, isChosen: style.rawValue == backdrop) {
                            backdrop = style.rawValue
                        }
                    }
                }
            }

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
                                .foregroundStyle(theme.colors.accent.color)
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

/// One theme as a small picture of itself: the Mind aspect's colour field for
/// Standard, its photograph for Landscape.
private struct ThemeTile: View {
    let style: SomaBackdropStyle
    let isChosen: Bool
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let radius = metrics.cardCornerRadius
        Button(action: action) {
            VStack(spacing: metrics.cardHeaderSpacing) {
                swatch
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.minimumTapTarget * 2)
                    .clipShape(.rect(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                isChosen ? theme.colors.accent.color : theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity),
                                lineWidth: isChosen ? 2 : 0.5
                            )
                    }
                Text(style.title)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(isChosen ? theme.colors.inkPrimary.color : theme.colors.inkSecondary.color)
            }
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(style.title))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    @ViewBuilder
    private var swatch: some View {
        let gradient = LinearGradient(
            colors: theme.aspects[.mind].orb.stops.map(\.color),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        if style == .landscape, Self.hasPhoto {
            Image(SomaBackdropStyle.photoName(for: .mind))
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(gradient)
        }
    }

    private static var hasPhoto: Bool {
#if canImport(UIKit)
        UIImage(named: SomaBackdropStyle.photoName(for: .mind)) != nil
#else
        NSImage(named: SomaBackdropStyle.photoName(for: .mind)) != nil
#endif
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
                .textCase(.uppercase)
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
