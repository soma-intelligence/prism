//
//  NotWiredPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A destination that exists so a control is not a dead end, and says plainly
/// that there is nothing behind it yet.
///
/// One page rather than four near identical ones: what differs is the copy, and
/// copy is an input.
///
/// This is the form a sheet presents, with the `NavigationStack` and the Done
/// button a sheet needs. A stack that pushes the same page takes
/// ``NotWiredContent`` instead: a pushed page that brings a stack of its own is a
/// stack inside a stack, and SwiftUI drops that push and traps on the next one
/// (`AnyNavigationPath.Error.comparisonTypeMismatch`).
struct NotWiredPage: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let message: LocalizedStringKey

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NotWiredContent(eyebrow: eyebrow, title: title, message: message)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// ``NotWiredPage`` without the stack and the Done button: the form a
/// navigation stack pushes, whose bar already carries the way back.
struct NotWiredContent: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let message: LocalizedStringKey

    var body: some View {
        PageScaffold(eyebrow: eyebrow, title: title) {
            NoteCard(title: "Nothing here yet", message: message)
        }
    }
}

/// The destinations the sidebar foot can open.
enum SidebarDestination: String, Identifiable {
    case search, help, settings, profile

    var id: String { rawValue }

    @ViewBuilder
    var page: some View {
        switch self {
        case .search:
            NotWiredPage(
                eyebrow: "Search",
                title: "Find anything",
                message: "Search runs over your own data once there is data to run over. It reads nothing from the network."
            )
        case .help:
            // The one help page, the website's, as Settings opens it.
            if let url = SettingsRoute.help.websiteURL {
                WebsiteSheet(link: WebsiteLink(title: String(localized: "Help"), url: url))
            }
        case .settings:
            SettingsSheet()
        case .profile:
            // The person's details live on one page, Settings' account page.
            SidebarAccountSheet()
        }
    }
}

/// Settings' account page on its own, for the sidebar's account row: the same
/// page and the same store, not a second form.
private struct SidebarAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AccountDetailsPage()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
