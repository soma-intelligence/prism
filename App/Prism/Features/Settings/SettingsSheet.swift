//
//  SettingsSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The personal side of Soma: an account card and a quiet column of settings.
/// Every destination shares this sheet's navigation stack.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @AppStorage(AppearanceMode.storageKey) private var modeName = AppearanceMode.fallback.rawValue

    /// A `NavigationPath`, not `[SettingsRoute]`: the Vault pushes its own
    /// routes onto this stack.
    @State private var path = NavigationPath()
    @State private var reveal = DeveloperReveal()
    @State private var notifications = SomaNotifications.shared
    @State private var account = AccountSession.shared
    /// The page of the website open over the sheet, when a row leads there.
    @State private var website: WebsiteLink?

    var body: some View {
        NavigationStack(path: $path) {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        accountRow
                        summary
                    }
                    vaultRow
                    dayGroup
                    generalGroup
                    dataGroup
                    signOutGroup
                    supportGroup
                    developerGroup
                    footer
                }
                .padding(.horizontal, theme.metrics.pagePadding)
                .padding(.top, theme.metrics.cardSpacing)
                .padding(.bottom, theme.metrics.pagePadding)
                .frame(maxWidth: theme.metrics.settingsContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            // The bar's own title and nothing above the account: the sheet
            // opens on what a person came to change, not on a heading, a mark
            // and a line of copy that push the first row halfway down.
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            // The Vault's pages fade into the sheet's ground under the bar, as a
            // pushed page on a tab does.
            .navigationDestination(for: VaultRoute.self) { $0.page.somaScrollEdgeFade() }
            .navigationDestination(for: GlobalRoute.self) { $0.page }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .developerTools:
                    DeveloperToolsPage(reveal: reveal) { path.append($0) }
                case .about:
                    AboutPage(reveal: reveal) { open($0) }
                default:
                    route.page
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                    .accessibilityLabel("Close settings")
                }
            }
            .task { await notifications.apply() }
        }
        .somaTheme(settingsTheme)
        .presentationBackground(theme.colors.canvas.color)
        .sheet(item: $website) { WebsiteSheet(link: $0) }
    }

    private var settingsTheme: SomaTheme {
        var value = theme
        value.metrics.browseRowMinHeight = theme.metrics.settingsRowHeight
        value.metrics.browseGlyphSize = theme.metrics.settingsGlyphSize
        value.metrics.browseGroupCornerRadius = theme.metrics.cardCornerRadius
        value.metrics.browseSeparatorOpacity = theme.metrics.hairlineOpacity
        return value
    }

    /// One full card is the hit target, including the avatar and chevron.
    private var accountRow: some View {
        Button { path.append(SettingsRoute.account) } label: {
            SomaCard {
                HStack(spacing: theme.metrics.browseRowSpacing) {
                    ProfileAvatar(diameter: theme.metrics.minimumTapTarget)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text(SomaProfileStore.shared.profile.firstName ?? String(localized: "Your account"))
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        Text("Your details")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: theme.metrics.cardSpacing)

                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .medium))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
            }
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel("Account")
        .accessibilityValue(SomaProfileStore.shared.profile.firstName ?? "")
    }

    // MARK: The live summary

    /// Four small tiles under the account, each a live value that opens its
    /// page: Health, notifications, the day's status, the last read.
    private var summary: some View {
        let status = ActivityStatusStore.shared.current
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: theme.metrics.cardSpacing),
                      GridItem(.flexible(), spacing: theme.metrics.cardSpacing)],
            spacing: theme.metrics.cardSpacing
        ) {
            SettingsSummaryTile(symbol: "heart", isOn: health.status == .ready, label: String(localized: "Health"),
                                value: healthValue, caption: healthCaption) {
                path.append(SettingsRoute.healthAccess)
            }
            SettingsSummaryTile(symbol: notifications.isOn ? "bell" : "bell.slash", isOn: notifications.isOn,
                                label: String(localized: "Notifications"), value: notificationsValue,
                                caption: notificationsCaption) {
                path.append(SettingsRoute.notifications)
            }
            SettingsSummaryTile(symbol: status.symbol, label: String(localized: "Status"),
                                value: status.title, caption: nil) {
                path.append(GlobalRoute.activityStatus)
            }
            SettingsSummaryTile(symbol: "arrow.triangle.2.circlepath", label: String(localized: "Last sync"),
                                value: syncValue, caption: nil) {
                path.append(SettingsRoute.dataDiagnostics)
            }
        }
    }

    private var healthValue: String {
        health.status == .ready ? String(localized: "Connected") : String(localized: "Off")
    }

    private var healthCaption: String? {
        guard health.status == .ready, !health.readings.isEmpty else { return nil }
        return VaultWords.withData(health.readings.count)
    }

    private var notificationsValue: String {
        notifications.isOn ? String(localized: "On") : String(localized: "Off")
    }

    private var notificationsCaption: String? {
        guard notifications.isOn, let next = notifications.next else { return nil }
        return String(localized: "Next \(NotificationCenterSheet.when(next.1))")
    }

    private var syncValue: String {
        guard let date = notifications.lastSync else { return String(localized: "Never") }
        if Date().timeIntervalSince(date) < 60 { return String(localized: "Just now") }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    /// The Vault: every reading Apple Health holds, by type, with each record
    /// and where it came from. Second only to the account, because the sheet
    /// is the personal side of Soma and this is the person's data.
    private var vaultRow: some View {
        NavigationLink(value: VaultRoute.browser) {
            SomaCard {
                HStack(spacing: theme.metrics.browseRowSpacing) {
                    SettingsGlyph(symbol: "archivebox", scale: theme.metrics.minimumTapTarget / theme.metrics.browseGlyphColumn)

                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text("Vault")
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        Text("All your data, with its source")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }

                    Spacer(minLength: theme.metrics.cardSpacing)

                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .medium))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
            }
        }
        .buttonStyle(.somaGlassPress)
    }

    /// The day's state and what to do with it: the activity status, which
    /// changes how the scores read, the calendar, and a card to share. They sat
    /// in a strip under the orb on Today; here they sit with the person's own
    /// settings (owner, 2026-10-03).
    private var dayGroup: some View {
        section("Today") {
            SomaBrowseGroup(DayRow.allCases) { row in
                SettingsTileRow(
                    row.title,
                    symbol: row == .status ? ActivityStatusStore.shared.current.symbol : row.symbol,
                    detail: row == .status ? ActivityStatusStore.shared.current.title : nil
                ) {
                    path.append(row.route)
                }
            }
        }
    }

    private enum DayRow: String, CaseIterable, Identifiable {
        case status, calendar, share
        var id: String { rawValue }
        var title: String {
            switch self {
            case .status: String(localized: "Status")
            case .calendar: String(localized: "Calendar")
            case .share: String(localized: "Share a card")
            }
        }
        var symbol: String {
            switch self {
            case .status: "figure.run"
            case .calendar: "calendar"
            case .share: "square.and.arrow.up"
            }
        }
        var route: GlobalRoute {
            switch self {
            case .status: .activityStatus
            case .calendar: .calendar
            case .share: .shareStudio
            }
        }
    }

    private var generalGroup: some View {
        section("General") {
            SomaBrowseGroup([
                SettingsRow(.appearance, String(localized: "Appearance"), "circle.lefthalf.filled"),
                SettingsRow(.notifications, String(localized: "Notifications"), "bell"),
                SettingsRow(.language, String(localized: "Language and units"), "globe"),
                SettingsRow(.customization, String(localized: "Customization"), "slider.horizontal.3"),
                SettingsRow(.shortcuts, String(localized: "Shortcuts"), "plus.circle"),
                SettingsRow(.programs, String(localized: "Programs"), "calendar.badge.clock"),
            ]) { row in
                SettingsTileRow(row.title, symbol: row.symbol, detail: detail(row.route)) {
                    path.append(row.route)
                } trailing: {
                    if row.route == .appearance { currentIcon }
                }
            }
        }
    }

    private func detail(_ route: SettingsRoute) -> String? {
        switch route {
        case .appearance: appearanceTitle
        case .notifications: notificationsValue
        case .healthAccess: health.status == .ready ? String(localized: "Connected") : nil
        default: nil
        }
    }

    /// The icon on the home screen, small, at the Appearance row's edge.
    @ViewBuilder
    private var currentIcon: some View {
#if os(iOS)
        let side = theme.metrics.browseGlyphColumn * 0.8
        Image(AppIconChoice.current.preview)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: side * 0.225, style: .continuous))
            .accessibilityHidden(true)
#endif
    }

    private var appearanceTitle: String {
        (AppearanceMode(storedName: modeName) ?? .fallback).title
    }

    private var dataGroup: some View {
        section("Data") {
            SomaBrowseGroup([
                SettingsRow(.healthAccess, String(localized: "Health access"), "heart.text.square"),
                SettingsRow(.dataDiagnostics, String(localized: "Data and diagnostics"), "arrow.triangle.2.circlepath"),
                SettingsRow(.exportData, String(localized: "Export my data"), "square.and.arrow.up"),
                // With no account there is nothing online: the row erases
                // what is on the phone, and says so.
                SettingsRow(.deleteData, account.isSignedIn ? String(localized: "Delete my data")
                                                            : String(localized: "Erase data on this iPhone"), "trash"),
            ]) { row in
                SettingsTileRow(
                    row.title, symbol: row.symbol, detail: detail(row.route),
                    role: row.route == .deleteData ? .destructive : .standard
                ) {
                    path.append(row.route)
                }
            }
        }
    }

    /// Sign out sits on the sheet itself as well as on the account page, so it
    /// is found without knowing it hides behind the account card. Nothing
    /// shows while nobody is signed in.
    @ViewBuilder
    private var signOutGroup: some View {
        if account.isSignedIn {
            section("Account") {
                AccountSignOutRow()
                    .padding(.horizontal, theme.metrics.browseRowPadding)
            }
        }
    }

    private var supportGroup: some View {
        section("Support") {
            SomaBrowseGroup([
                SettingsRow(.help, String(localized: "Get help"), "questionmark.circle"),
                SettingsRow(.bugReport, String(localized: "Report a bug"), "ladybug"),
                SettingsRow(.about, String(localized: "About Soma"), "info.circle"),
            ]) { row in
                SettingsTileRow(row.title, symbol: row.symbol) { open(row.route) }
            }
            if let url = IMessageBeta.url {
                SomaBrowseGroup([IMessageBeta.Row()]) { _ in
                    SettingsTileRow(String(localized: "Chat on iMessage"), symbol: "message", detail: "Beta") {
                        openURL(url)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .padding(.leading, theme.metrics.browseRowPadding)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// Pushes a route's page, or opens the website over the sheet when the
    /// website is where that page lives.
    private func open(_ route: SettingsRoute) {
        if let url = route.websiteURL {
            website = WebsiteLink(title: Self.websiteTitle(route), url: url)
        } else {
            path.append(route)
        }
    }

    private static func websiteTitle(_ route: SettingsRoute) -> String {
        switch route {
        case .terms: String(localized: "Terms")
        case .privacy: String(localized: "Privacy")
        case .help: String(localized: "Help")
        default: "Soma"
        }
    }

    /// Only someone who knows the gesture finds it. One row rather than
    /// fifteen inline.
    @ViewBuilder
    private var developerGroup: some View {
        if reveal.isRevealed {
            section("Developer") {
                SomaBrowseGroup([SettingsRow(.developerTools, String(localized: "Developer tools"), "hammer")]) { row in
                    SettingsTileRow(row.title, symbol: row.symbol) { path.append(row.route) }
                }
            }
        }
    }

    private var footer: some View {
        Button { reveal.tap() } label: {
            HStack(spacing: theme.metrics.identityDotSpacing) {
                SomaMark(accessibilityLabel: "Soma", role: .caption)
                    .accessibilityHidden(true)
                Text(Self.versionLine)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.versionLine))
        .accessibilityHint(Text("Tap seven times to show developer tools"))
    }

    /// Version and build, read from the bundle rather than written down.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }
}

/// One live value under the account: a neutral card, the glyph in ink, the
/// value large and what it is under it, and a state dot where there is a
/// state. The whole tile opens the page behind it.
struct SettingsSummaryTile: View {
    let symbol: String
    var isOn: Bool?
    let label: String
    let value: String
    let caption: String?
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        Button(action: action) {
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                HStack(alignment: .center) {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.settingsGlyphSize, weight: .regular))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    if let isOn { SettingsStateDot(isOn: isOn) }
                }
                .padding(.bottom, metrics.cardHeaderSpacing)
                Text(value)
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption.map { "\(label), \($0)" } ?? label)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .lineLimit(1)
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.colors.surface.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text([value, caption].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// One row of the settings list: where it goes, what it says, what it wears.
///
/// `Identifiable` because ``SomaBrowseGroup`` is data driven: it owns where the
/// separators go, and it can only do that over a collection it can identify.
struct SettingsRow: Identifiable, Hashable {
    let route: SettingsRoute
    let title: String
    let symbol: String

    var id: SettingsRoute { route }

    init(_ route: SettingsRoute, _ title: String, _ symbol: String) {
        self.route = route
        self.title = title
        self.symbol = symbol
    }
}

#Preview("Settings") {
    SettingsSheet()
        .environment(AppRouter())
        .environment(HealthDashboard())
}

/// The beta link to talk to Soma in Messages.
///
/// The row appears only once ``address`` is set: the Apple ID email or phone
/// number the Soma relay listens on. Until then the build ships without it.
enum IMessageBeta {
    /// Set to the bot's address to show the row, e.g. "ask@somalabs.me".
    static let address: String? = nil

    static var url: URL? {
        guard let address, !address.isEmpty else { return nil }
        return URL(string: "imessage:\(address)") ?? URL(string: "sms:\(address)")
    }

    struct Row: Identifiable {
        var id: String { "imessage" }
    }
}
