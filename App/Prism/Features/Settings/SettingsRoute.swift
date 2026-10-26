//
//  SettingsRoute.swift
//  Prism
//

import SwiftUI

/// Everywhere the settings sheet can go.
///
/// Its own file rather than private to the sheet, because the pages behind
/// these cases are their own files too, and a route enum that only the sheet can
/// name forces every one of them through it.
///
/// A case exists for a row whether or not there is anything behind it yet. A row
/// that leads nowhere is worse than a row that leads to a page saying plainly
/// that nothing is wired: the first looks broken, the second is honest.
enum SettingsRoute: Hashable, Identifiable {
    case account
    case appearance
    case language
    case notifications
    /// What usual means: focus, ranges, goals, zones and how Soma answers.
    case customization
    /// Which model writes Ask's answers.
    case askModel
    /// What the plus in Ask's composer offers.
    case shortcuts
    case programs
    /// Every source, the sync, and what diagnostics may leave the device.
    case dataDiagnostics
    case healthAccess
    case exportData
    case deleteData
    /// Opens the website's help page in a sheet, from ``websiteURL``.
    case help
    case bugReport
    /// Everything about the app: version, legal, licences, credits. Built by
    /// ``SettingsSheet`` like the developer tools, since it carries the reveal.
    case about
    case openSource
    /// Opens the website's terms in a sheet, from ``websiteURL``: they are
    /// written once, on somalabs.me, and a copy here would drift.
    case terms
    /// Opens the website's privacy policy in a sheet, from ``websiteURL``.
    case privacy
    /// Built by ``SettingsSheet`` rather than here: the page needs the reveal
    /// object and a way to push onto the sheet's own stack, and a route enum
    /// that took dependencies would stop being a route enum.
    ///
    /// Its arm in ``page`` below is therefore never reached. It stays because
    /// the switch is exhaustive and removing the arm would not compile, not
    /// because anything shows it.
    case developerTools
    case componentGallery
    /// Presented full screen by ``DeveloperToolsPage`` rather than pushed, so
    /// this case names the row and never reaches ``page``. Capturing owns the
    /// camera and the radio while it is open, and a mode like that does not
    /// belong on a settings stack.
    case capture

    var id: Self { self }

    /// The page of the website a route opens rather than a page of its own.
    ///
    /// ``SettingsSheet`` presents it in ``WebsiteSheet``. Nil for every route
    /// the app draws itself.
    var websiteURL: URL? {
        switch self {
        case .terms: URL(string: "https://www.somalabs.me/legal/terms")
        case .privacy: URL(string: "https://www.somalabs.me/legal/privacy")
        case .help: URL(string: "https://www.somalabs.me/help")
        default: nil
        }
    }

    /// What the settings sheet pushes for each route.
    ///
    /// No arm may bring a `NavigationStack` of its own. These land on the
    /// sheet's stack, and a stack pushed onto a stack is one SwiftUI drops on
    /// the way in, then traps on at the next push with
    /// `AnyNavigationPath.Error.comparisonTypeMismatch`. That is why the arms
    /// name ``NotWiredContent`` rather than the sheet
    /// forms, and why ``ComponentPlayground`` carries no stack.
    @ViewBuilder
    var page: some View {
        switch self {
        case .account:
            AccountDetailsPage()
        case .appearance:
            AppearancePage()
        case .language:
            LanguageUnitsPage()
        case .notifications:
            NotificationsPage()
        case .customization:
            CustomizationPage()
        case .askModel:
            AskModelPage()
        case .shortcuts:
            ShortcutsPage()
        case .programs:
            ProgramsPage()
        case .dataDiagnostics:
            DataDiagnosticsPage()
        case .healthAccess:
            HealthAccessPage()
        case .exportData:
            ExportDataPage()
        case .deleteData:
            DeleteDataPage()
        case .bugReport:
            NotWiredContent(
                eyebrow: "Report",
                title: "Something is wrong",
                message: "A report needs somewhere to go, and there is no inbox behind this yet."
            )
        case .openSource:
            OpenSourcePage()
        case .terms, .privacy, .help:
            // Presented as a sheet by SettingsSheet. Pushed, it still shows
            // the website's page rather than a copy of it.
            if let websiteURL {
                WebsitePageView(url: websiteURL)
            }
        case .about:
            AboutPage(reveal: DeveloperReveal()) { _ in }
        case .developerTools:
            NotWiredContent(
                eyebrow: "Developer",
                title: "Developer tools",
                message: "The component gallery and the Health seeder land here."
            )
        case .componentGallery:
            ComponentPlayground()
        case .capture:
            NotWiredContent(
                eyebrow: "Capture",
                title: "Capture tools",
                message: "This should have opened full screen. Seeing this page means the developer tools stopped presenting it."
            )
        }
    }
}
