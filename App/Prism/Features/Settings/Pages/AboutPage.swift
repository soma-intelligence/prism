//
//  AboutPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Everything about the app in one place: the version (the seven taps that
/// reveal the developer tools work here too), the legal pages, the work Soma
/// ships that others made, and the photographs behind the Landscape theme.
struct AboutPage: View {
    let reveal: DeveloperReveal
    /// Opens a route on the sheet: the website for Terms and Privacy, a push
    /// for the licences.
    let open: (SettingsRoute) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ListScaffold(eyebrow: "Settings", title: "About Soma") {
            Button { reveal.tap() } label: {
                HStack(spacing: theme.metrics.browseRowSpacing) {
                    SomaMark(accessibilityLabel: "Soma", role: .caption)
                        .accessibilityHidden(true)
                    Text("Soma")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    Spacer(minLength: theme.metrics.browseRowSpacing)
                    Text(SettingsSheet.versionLine)
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .padding(.horizontal, theme.metrics.browseRowPadding)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.browseRowMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                        .fill(theme.colors.surface.color)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(SettingsSheet.versionLine))
            .accessibilityHint(Text("Tap seven times to show developer tools"))

            SettingsSection("Legal") {
                SomaBrowseGroup([
                    SettingsRow(.terms, String(localized: "Terms"), "doc.plaintext"),
                    SettingsRow(.privacy, String(localized: "Privacy"), "hand.raised"),
                ]) { row in
                    SettingsTileRow(row.title, symbol: row.symbol) { open(row.route) }
                }
            }

            SettingsSection("Open source") {
                SomaBrowseGroup([SettingsItem(id: "muscle-figure")]) { _ in
                    SettingsTileRow("Muscle figure", symbol: "figure.strengthtraining.traditional",
                                    detail: "CC BY-SA 4.0") { open(.openSource) }
                }
            }

            SettingsSection("Photographs") {
                SomaBrowseGroup(PhotoCredit.all) { credit in
                    SettingsTileRow(credit.author, symbol: "photo",
                                    detail: credit.aspect) { openURL(credit.url) }
                }
            }

            SettingsFootnote("Landscape photographs from Unsplash, under the Unsplash licence. Thank you to everyone whose work Soma stands on.")
        }
    }
}

/// One photograph behind the Landscape theme, credited as Unsplash asks.
struct PhotoCredit: Identifiable, Hashable {
    let aspect: String
    let title: String
    let author: String
    let photoID: String

    var id: String { photoID }
    var url: URL { URL(string: "https://unsplash.com/photos/\(photoID)") ?? URL(filePath: "/") }

    static let all: [PhotoCredit] = [
        PhotoCredit(aspect: String(localized: "Sleep"), title: "Moss in a pool of light, dark forest", author: "Matthieu Lemarchal", photoID: "rCgw95aGmVs"),
        PhotoCredit(aspect: String(localized: "Mind"), title: "Light rays in a mossy redwood forest", author: "Landon Parenteau", photoID: "D0pMST46enU"),
        PhotoCredit(aspect: String(localized: "Body"), title: "Warm moss on the forest floor", author: "Erik Mclean", photoID: "Qk28DEeEKc8"),
        PhotoCredit(aspect: String(localized: "Heart"), title: "Sunrise through the trees", author: "Etienne Delorieux", photoID: "Nmd9UJLoCE4"),
        PhotoCredit(aspect: String(localized: "Gut"), title: "Fronds against the dark", author: "Mohamed Elwaid", photoID: "vcrRGVsivK0"),
        PhotoCredit(aspect: String(localized: "Activity"), title: "A ray of sunlight on a mossy path", author: "Sini Tiainen", photoID: "T2EvkDxqvMY"),
    ]
}

/// The open work Soma ships, credited as its licence asks: the muscle
/// figure on Body is rendered from Z-Anatomy, itself built on BodyParts3D,
/// and is shared on under the same licence.
struct OpenSourcePage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ListScaffold(eyebrow: "About Soma", title: "Open source") {
            SettingsSection("Muscle figure") {
                SomaBrowseGroup(FigureCredit.all) { credit in
                    SettingsTileRow(credit.title, symbol: credit.symbol, detail: credit.detail) {
                        openURL(credit.url)
                    }
                }
            }
            SomaCard {
                Text(Self.muscleFigureCredit)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// The credit line the figure's licence asks for, word for word as in
    /// `NOTICE.md` and beside the images in SomaUI.
    static let muscleFigureCredit = "Muscle illustrations rendered from Z-Anatomy, the libre 3D atlas of anatomy (CC BY-SA 4.0), based on BodyParts3D, The Database Center for Life Science (CC BY-SA 2.1 Japan). The illustrations are shared under CC BY-SA 4.0."
}

/// One link behind the muscle figure's credit.
struct FigureCredit: Identifiable, Hashable {
    let title: String
    let detail: String
    let symbol: String
    let url: URL

    var id: String { title }

    static let all: [FigureCredit] = [
        FigureCredit(title: "Z-Anatomy", detail: "CC BY-SA 4.0", symbol: "figure.stand",
                     url: URL(string: "https://github.com/Z-Anatomy/Models-of-human-anatomy") ?? URL(filePath: "/")),
        FigureCredit(title: "BodyParts3D", detail: "CC BY-SA 2.1 JP", symbol: "cube.transparent",
                     url: URL(string: "https://dbarchive.biosciencedbc.jp/en/bodyparts3d/") ?? URL(filePath: "/")),
        FigureCredit(title: String(localized: "Licence"), detail: "CC BY-SA 4.0", symbol: "doc.plaintext",
                     url: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/") ?? URL(filePath: "/")),
    ]
}

#Preview("About") {
    NavigationStack { AboutPage(reveal: DeveloperReveal()) { _ in } }
}
