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

    /// Whether the sheet is wide enough to keep the settings beside the page
    /// they open, the way Settings reads on an iPad: read off the sheet's own
    /// width, so the inner screen of a foldable on its side gets it too.
    @State private var widthClass = SomaWidthClass.compact
    /// What the pane shows while the Vault holds the column, on a roomy
    /// screen: the Vault's categories on the left and the one picked on the
    /// right, as Apple Health's Browse reads on an iPad. `nil` keeps the
    /// settings in the column.
    @State private var vaultPane: VaultRoute?

    var body: some View {
        // Both shapes drive the one `path`, so a sheet that crosses the line
        // (a foldable opening, a window resized) keeps the page it was on.
        Group {
            if widthClass == .regular {
                HStack(spacing: 0) {
                    NavigationStack {
                        if vaultPane != nil {
                            vaultColumn
                        } else {
                            column
                        }
                    }
                    .frame(width: theme.metrics.listPaneWidth)

                    Rectangle()
                        .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
                        .frame(width: 0.5)
                        .ignoresSafeArea()

                    NavigationStack(path: $path) {
                        withDestinations(SettingsPaneRest())
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    withDestinations(column)
                }
            }
        }
        .somaWidthClass($widthClass)
        .onChange(of: vaultPane) { _, route in
            guard let route else { return }
            path = NavigationPath()
            path.append(route)
        }
        .onChange(of: widthClass) { _, width in
            // Folded or narrowed with the Vault in the column: the stack
            // takes the browser back under the page it showed.
            guard width == .compact, let route = vaultPane else { return }
            vaultPane = nil
            path = NavigationPath()
            path.append(VaultRoute.browser)
            path.append(route)
        }
        .somaTheme(settingsTheme)
        .presentationBackground(theme.colors.canvas.color)
        // Roomy on an iPad, so the two panes have the width they need.
        .presentationSizing(.page)
        .sheet(item: $website) { WebsiteSheet(link: $0) }
    }

    /// The settings themselves: the account, the summary, and every group.
    private var column: some View {
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                VStack(spacing: theme.metrics.cardSpacing) {
                    accountRow
                    summary
                }
                VStack(spacing: theme.metrics.cardSpacing) {
                    vaultRow
                    recordRow
                    reportRow
                }
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
        .softScrollEdges()
        .background(theme.colors.canvas.color.ignoresSafeArea())
        // The bar's own title and nothing above the account: the sheet
        // opens on what a person came to change, not on a heading, a mark
        // and a line of copy that push the first row halfway down.
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inline)
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

    /// Every page the sheet opens. Beside the settings, the page a row opened
    /// is the first one on its side and carries no way back to the empty pane.
    private func withDestinations(_ root: some View) -> some View {
        let isPaneRoot = widthClass == .regular && path.count == 1
        return root
            .navigationDestination(for: VaultRoute.self) { route in
                route.page
                    .navigationBarBackButtonHidden(isPaneRoot)
                    // A large title in the pane sits flush on the divider:
                    // the pane names its page in the bar, as the column does.
                    .modifier(PaneTitle(isPane: widthClass == .regular))
            }
            .navigationDestination(for: GlobalRoute.self) { route in
                route.page.navigationBarBackButtonHidden(isPaneRoot)
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                Group {
                    switch route {
                    case .developerTools:
                        DeveloperToolsPage(reveal: reveal) { path.append($0) }
                    case .about:
                        AboutPage(reveal: reveal) { open($0) }
                    default:
                        route.page
                    }
                }
                .navigationBarBackButtonHidden(isPaneRoot)
            }
    }

    /// Opens a row's page from the settings column: pushed over the column on
    /// its own, or in place of whatever the pane beside it showed.
    private func show(_ route: some Hashable) {
        if widthClass == .regular { path = NavigationPath() }
        path.append(route)
    }

    private var settingsTheme: SomaTheme {
        var value = theme
        value.metrics.browseRowMinHeight = theme.metrics.settingsRowHeight
        value.metrics.browseGlyphSize = theme.metrics.settingsGlyphSize
        value.metrics.browseSeparatorOpacity = theme.metrics.hairlineOpacity
        return value
    }

    /// One full card is the hit target, including the avatar and chevron.
    private var accountRow: some View {
        Button { show(SettingsRoute.account) } label: {
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
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
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
                show(SettingsRoute.healthAccess)
            }
            SettingsSummaryTile(symbol: notifications.isOn ? "bell" : "bell.slash", isOn: notifications.isOn,
                                label: String(localized: "Notifications"), value: notificationsValue,
                                caption: notificationsCaption) {
                show(SettingsRoute.notifications)
            }
            SettingsSummaryTile(symbol: status.symbol, label: String(localized: "Status"),
                                value: status.title, caption: nil) {
                show(GlobalRoute.activityStatus)
            }
            SettingsSummaryTile(symbol: "arrow.triangle.2.circlepath", label: String(localized: "Last sync"),
                                value: syncValue, caption: nil) {
                show(SettingsRoute.dataDiagnostics)
            }
        }
    }

    private var healthValue: String {
        health.status == .ready ? String(localized: "Connected") : String(localized: "Off")
    }

    /// "6 measures": short enough to sit after "Health," on a half width
    /// tile without being cut.
    private var healthCaption: String? {
        guard health.status == .ready, !health.readings.isEmpty else { return nil }
        return VaultWords.measures(health.readings.count)
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
        cardRow(symbol: "archivebox", title: "Vault", detail: String(localized: "All your data, with its source")) {
            if widthClass == .regular {
                vaultPane = .category(BodyCatalog.categories[0])
            } else {
                show(VaultRoute.browser)
            }
        }
    }

    /// The Vault's categories in the settings column, with the way back to
    /// the settings where the bar puts a back button.
    private var vaultColumn: some View {
        BodyBrowserView()
            .environment(\.vaultPane, $vaultPane)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        vaultPane = nil
                        path = NavigationPath()
                    } label: {
                        Label("Settings", systemImage: "chevron.left")
                    }
                }
            }
    }

    /// The medical record, under the Vault: what the person keeps for a
    /// doctor, typed in by them rather than read from Health.
    private var recordRow: some View {
        let next = MedicalRecordStore.shared.upcoming().first
        return cardRow(symbol: "heart.text.clipboard", title: "Medical record",
                       detail: next.map { String(localized: "Next visit \(MedicalRecordPage.day($0.date)) at \(ScoreMath.clock($0.date))") }
                           ?? String(localized: "Conditions, allergies, vaccines, appointments")) {
            show(GlobalRoute.medicalRecord)
        }
    }

    /// The PDF for a visit, under the record it is mostly made of.
    private var reportRow: some View {
        cardRow(symbol: "doc.text", title: "Report for my doctor",
                detail: String(localized: "A PDF to share, made on this phone")) {
            show(GlobalRoute.doctorReport)
        }
    }

    /// A row of its own card under the account: the Vault, the record.
    private func cardRow(symbol: String, title: LocalizedStringKey, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SomaCard {
                HStack(spacing: theme.metrics.browseRowSpacing) {
                    // The glyph at the rows' size, centred in the avatar's
                    // width, so the title lines up with the account's above.
                    SettingsGlyph(symbol: symbol)
                        .frame(width: theme.metrics.minimumTapTarget)

                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text(title)
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        Text(detail)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }

                    Spacer(minLength: theme.metrics.cardSpacing)

                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
            }
        }
        .buttonStyle(.somaGlassPress)
    }

    /// What to do with the day: the calendar and a card to share. They sat
    /// in a strip under the orb on Today; here they sit with the person's own
    /// settings (owner, 2026-10-03). The activity status, which changes how
    /// the scores read, is the Status tile in the summary above, and only
    /// there: a row here repeated it a few points lower.
    private var dayGroup: some View {
        section("Today") {
            SomaBrowseGroup(DayRow.allCases) { row in
                SettingsTileRow(row.title, symbol: row.symbol) {
                    show(row.route)
                }
            }
        }
    }

    private enum DayRow: String, CaseIterable, Identifiable {
        case calendar, share
        var id: String { rawValue }
        var title: String {
            switch self {
            case .calendar: String(localized: "Calendar")
            case .share: String(localized: "Share a card")
            }
        }
        var symbol: String {
            switch self {
            case .calendar: "calendar"
            case .share: "square.and.arrow.up"
            }
        }
        var route: GlobalRoute {
            switch self {
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
                SettingsRow(.askModel, String(localized: "Ask Soma"), "sparkle"),
                SettingsRow(.shortcuts, String(localized: "Shortcuts"), "plus.circle"),
                SettingsRow(.programs, String(localized: "Programs"), "calendar.badge.clock"),
            ]) { row in
                SettingsTileRow(row.title, symbol: row.symbol, detail: detail(row.route)) {
                    show(row.route)
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
        case .askModel: AskProviderSettings.shared.effective.title
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
                SettingsRow(.deleteData, String(localized: "Close my account"), "person.crop.circle.badge.xmark"),
            ]) { row in
                SettingsTileRow(
                    row.title, symbol: row.symbol, detail: detail(row.route),
                    role: row.route == .deleteData ? .destructive : .standard
                ) {
                    show(row.route)
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
                SettingsTileRow(row.title, symbol: row.symbol) {
                    if row.route.websiteURL == nil { show(row.route) } else { open(row.route) }
                }
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
                    SettingsTileRow(row.title, symbol: row.symbol) { show(row.route) }
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
            .somaLitSurface()
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

/// The pane beside the settings before a row is chosen: the canvas and the
/// mark, quiet, rather than a page nobody asked for.
private struct SettingsPaneRest: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaMark(accessibilityLabel: "Soma", role: .caption)
            .opacity(theme.metrics.chartContextOpacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .accessibilityHidden(true)
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

/// The bar's inline title for a page shown in the settings pane.
private struct PaneTitle: ViewModifier {
    let isPane: Bool

    func body(content: Content) -> some View {
#if os(iOS)
        if isPane {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
#else
        content
#endif
    }
}
