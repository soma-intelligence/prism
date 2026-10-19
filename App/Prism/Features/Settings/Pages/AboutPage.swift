//
//  AboutPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Everything about the app in one place: the version (the seven taps that
/// reveal the developer tools work here too), the legal pages, the code Soma
/// ships that others wrote, and the photographs behind the Landscape theme.
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
                SomaBrowseGroup([SettingsItem(id: "musclemap")]) { _ in
                    SettingsTileRow("MuscleMap", symbol: "figure.strengthtraining.traditional",
                                    detail: "MIT") { open(.openSource) }
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
        PhotoCredit(aspect: String(localized: "Sleep"), title: "Half Dome under moon in Yosemite", author: "Casey Horner", photoID: "mPnxwQBtUZE"),
        PhotoCredit(aspect: String(localized: "Mind"), title: "Lake reflection", author: "Thomas Grams", photoID: "1Q578d01zas"),
        PhotoCredit(aspect: String(localized: "Body"), title: "Sand dunes", author: "raouf bedrani", photoID: "oVWm9rQpbq0"),
        PhotoCredit(aspect: String(localized: "Heart"), title: "Calm water at golden hour", author: "Linus Nylund", photoID: "JP23z_-dA74"),
        PhotoCredit(aspect: String(localized: "Gut"), title: "Valley from a high point", author: "Nils Schirmer", photoID: "qWmUGrV8B54"),
        PhotoCredit(aspect: String(localized: "Activity"), title: "Mountain at sunrise", author: "Mario von Rotz", photoID: "HHYpIR68Eds"),
    ]
}

/// The licences of the code Soma ships that someone else wrote, in full, as
/// their terms ask.
struct OpenSourcePage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ListScaffold(eyebrow: "About Soma", title: "Open source") {
            SettingsSection("MuscleMap") {
                SomaBrowseGroup([SettingsItem(id: "source")]) { _ in
                    SettingsTileRow("Melih Colpan", symbol: "chevron.left.forwardslash.chevron.right", detail: "GitHub") {
                        if let url = URL(string: "https://github.com/melihcolpan/MuscleMap") { openURL(url) }
                    }
                }
            }
            SomaCard {
                Text(Self.muscleMapLicence)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// The MIT licence MuscleMap ships with, word for word.
    static let muscleMapLicence = """
    MIT License

    Copyright (c) 2026 Melih Colpan

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}

#Preview("About") {
    NavigationStack { AboutPage(reveal: DeveloperReveal()) { _ in } }
}
