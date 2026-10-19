//
//  WebsitePage.swift
//  Prism
//

import SwiftUI
import WebKit
import SomaUI

/// A page of the website, drawn inside the app.
///
/// For what the website already says, and says once: the terms and the
/// privacy policy are written on somalabs.me, and a copy inside the app would
/// drift from them within a week. So the app shows the page itself rather
/// than a rewrite of it. It draws the page without the site's own top bar:
/// the sheet already carries a title and a way out.
///
/// No `NavigationStack` of its own: pushed onto the settings stack it takes
/// that stack's bar, and ``WebsiteSheet`` brings one when it is presented.
struct WebsitePageView: View {
    let url: URL

    @Environment(\.somaTheme) private var theme
    @State private var page = WebPage(configuration: WebsitePageView.embedded)
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        WebView(page)
            .overlay {
                if failed {
                    unreachable
                } else if page.isLoading {
                    ProgressView()
                }
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .task(id: attempt) { await load() }
    }

    private func load() async {
        failed = false
        do {
            for try await _ in page.load(URLRequest(url: url)) {}
        } catch is CancellationError {
            // The page went away before it finished: nothing to say.
        } catch {
            failed = true
        }
    }

    /// Said plainly, so a lost connection never answers with a blank sheet.
    private var unreachable: some View {
        VStack(spacing: 12) {
            Text("somalabs.me could not be reached")
                .somaFont(theme.typography.title)
                .foregroundStyle(theme.colors.inkPrimary.color)

            Text("Offline")
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .multilineTextAlignment(.center)

            Button("Try again") { attempt += 1 }
                .somaFont(theme.typography.body)
                .tint(theme.colors.accent.color)
        }
        .padding(theme.metrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.canvas.color)
    }

    /// The website without its navigation bar, and without the room the page
    /// leaves above its title for that bar.
    ///
    /// Injected as a style at document start, so the bar never paints and then
    /// vanishes. The bar is the page header, the one fixed `header`; the title
    /// band is the `header` inside `main`.
    private static var embedded: WebPage.Configuration {
        let configuration = WebPage.Configuration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            const style = document.createElement('style');
            style.textContent = 'header.fixed { display: none !important; } main header { padding-top: 2.5rem !important; }';
            document.documentElement.appendChild(style);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        return configuration
    }
}

/// ``WebsitePageView`` presented over the settings, with a title and a way out.
///
/// A sheet rather than a push: the page belongs to the website, not to the
/// settings stack, and Done returns the person to the row they tapped.
struct WebsiteSheet: View {
    let link: WebsiteLink

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebsitePageView(url: link.url)
                .navigationTitle(link.title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// A page of the website and the name the app gives it.
struct WebsiteLink: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: URL { url }
}

#Preview("Website sheet") {
    WebsiteSheet(link: WebsiteLink(title: "Terms", url: URL(string: "https://www.somalabs.me/legal/terms")!))
}
