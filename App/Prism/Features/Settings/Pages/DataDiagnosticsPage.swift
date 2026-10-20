//
//  DataDiagnosticsPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Sources and sync, in as few words as the facts allow (owner, 2026-10-20:
/// the page said far too much). The head reads like a metric page: when
/// Apple Health was last read, large, with one line on whether it is on and
/// a way to read it again. Then each source on one line with what it feeds
/// under its name and where it stands on the trailing edge (a dot and a
/// word; when one is off, the line under it says why). Then what this device
/// holds, and the two diagnostics switches by name alone. The explanations
/// wait behind the info control.
struct DataDiagnosticsPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var settings = GlobalSettings.shared
    @State private var onDevice: Int64?
    @State private var lastRead: Date?
    @State private var isReading = false
    @State private var showsInfo = false

    var body: some View {
        @Bindable var settings = settings
        let metrics = theme.metrics
        let head = SourcesSyncWords.head(health.status)

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    let read = SourcesSyncWords.lastRead(lastRead ?? SomaNotifications.shared.lastSync)
                    SomaMetricHero(
                        caption: String(localized: "Last read"),
                        value: read.value,
                        unit: read.unit,
                        meaning: head.text,
                        tone: head.tone
                    )
                    readAgain
                }
                .padding(.top, metrics.scoreHeroTopPadding)

                SettingsSection("Sources") {
                    SomaBrowseGroup([SettingsItem].items("health", "motion", "blood", "journal")) { item in
                        sourceRow(item.id)
                    }
                }

                SettingsSection("On this device") {
                    SomaBrowseGroup([SettingsItem].items("device", "account"), hasGlyphs: false) { item in
                        if item.id == "device" {
                            SettingsLine(String(localized: "Stored")) {
                                valueText(onDevice.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "-")
                            }
                        } else {
                            SettingsLine(String(localized: "Copy elsewhere")) {
                                valueText(String(localized: "None"))
                            }
                        }
                    }
                }

                SettingsSection("Diagnostics") {
                    SomaBrowseGroup([SettingsItem].items("crash", "usage"), hasGlyphs: false) { item in
                        if item.id == "crash" {
                            SettingsLine(String(localized: "Crash reports")) {
                                SettingsSwitch(title: String(localized: "Share crash reports"), isOn: $settings.diagnostics.shareCrashReports)
                            }
                        } else {
                            SettingsLine(String(localized: "Usage")) {
                                SettingsSwitch(title: String(localized: "Share usage"), isOn: $settings.diagnostics.shareUsage)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle("Sources and sync")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsInfo = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(Text("About sources and sync"))
            }
        }
        .sheet(isPresented: $showsInfo) {
            SomaInfoSheet(title: String(localized: "Sources and sync"), sections: SourcesSyncWords.about)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await measure() }
    }

    /// Reads Apple Health again: a quiet capsule under the head, its glyph
    /// giving way to a spinner while the read runs.
    private var readAgain: some View {
        Button {
            Task { await readAgain() }
        } label: {
            HStack(spacing: theme.metrics.browseRowSpacing / 2) {
                if isReading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                }
                Text(isReading ? String(localized: "Reading") : String(localized: "Read again"))
                    .somaFont(theme.typography.callout)
            }
            .foregroundStyle(theme.colors.inkPrimary.color)
            .padding(.horizontal, theme.metrics.quietPillPadding)
            .frame(minHeight: theme.metrics.quietPillHeight)
            .background(Capsule().fill(theme.colors.surface.color))
            .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .disabled(isReading || !health.isAvailable)
        .accessibilityLabel(Text("Read Apple Health again"))
    }

    @ViewBuilder
    private func sourceRow(_ id: String) -> some View {
        switch id {
        case "health":
            NavigationLink(value: SettingsRoute.healthAccess) {
                SourceRow(symbol: "heart", title: String(localized: "Apple Health"),
                          line: SourcesSyncWords.health(health.status), opensSomething: true)
            }
            .buttonStyle(.plain)
        case "motion":
            SourceRow(symbol: "figure.walk", title: String(localized: "iPhone motion"),
                      line: SourcesSyncWords.motion(health.motion.authorization))
        case "blood":
            SourceRow(symbol: "drop", title: String(localized: "Blood panels"),
                      line: SourcesSyncWords.blood(BloodPanelStore.shared.latest?.date))
        default:
            SourceRow(symbol: "square.and.pencil", title: String(localized: "Journal"),
                      line: SourcesSyncWords.journal(days: journal.loggedDays.count))
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .somaFont(theme.typography.rowValue)
            .foregroundStyle(theme.colors.inkSecondary.color)
    }

    private func readAgain() async {
        isReading = true
        await health.loadToday(force: true)
        lastRead = Date()
        isReading = false
        await measure()
    }

    /// What Soma keeps in its own folder on this device.
    private func measure() async {
        onDevice = await Task.detached(priority: .utility) {
            DataDiagnosticsPage.folderSize()
        }.value
    }

    nonisolated static func folderSize() -> Int64? {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let files = manager.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// One source: its glyph, its name with what it feeds (or, when off, why)
/// under it, and where it stands on the trailing edge as a dot and a word.
private struct SourceRow: View {
    let symbol: String
    let title: String
    let line: SourcesSyncWords.Line
    var opensSomething = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        SettingsTileLine(title, symbol: symbol, detail: line.hint) {
            HStack(spacing: metrics.browseRowSpacing / 2) {
                if line.tone != .neutral {
                    Circle()
                        .fill(line.tone.color(colors))
                        .frame(width: metrics.metricMeaningDot, height: metrics.metricMeaningDot)
                        .accessibilityHidden(true)
                }
                Text(line.value)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
                if opensSomething {
                    Image(systemName: "chevron.right")
                        .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(colors.inkSecondary.color)
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(.rect)
    }
}

/// The words of the sources and sync page, short, and kept out of the view so
/// they can be tested.
enum SourcesSyncWords {
    /// A source's line: where it stands, the tone of its dot, and the line
    /// under its name (what it feeds, or why it is off).
    struct Line: Equatable, Sendable {
        var value: String
        var tone: SomaCueTone
        var hint: String
    }

    /// The meaning under the last read: whether Apple Health is on.
    static func head(_ status: HealthDashboard.Status) -> (text: String, tone: SomaCueTone) {
        switch status {
        case .ready: (String(localized: "Apple Health is on"), .good)
        case .loading: (String(localized: "Reading Apple Health"), .neutral)
        case .idle: (String(localized: "Apple Health is off"), .watch)
        case .unavailable: (String(localized: "No Apple Health on this device"), .watch)
        case .failed: (String(localized: "Apple Health could not be read"), .watch)
        }
    }

    /// The last read as a time today, "Yesterday", or a date; a dash before
    /// the first. A twelve hour clock's "PM" is set apart as the unit, so the
    /// large digits stand alone the way a metric's number does.
    static func lastRead(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> (value: String, unit: String?) {
        guard let date else { return ("-", nil) }
        guard calendar.isDate(date, inSameDayAs: now) else {
            return (VaultWords.day(date, now: now, calendar: calendar), nil)
        }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .current,
                                                   calendar: calendar, timeZone: calendar.timeZone))
        let parts = time.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count == 2, parts[0].contains(where: \.isNumber), !parts[1].contains(where: \.isNumber) {
            return (parts[0], parts[1])
        }
        return (time, nil)
    }

    static func health(_ status: HealthDashboard.Status) -> Line {
        let feeds = String(localized: "Heart, sleep, activity, body")
        return switch status {
        case .ready: Line(value: String(localized: "On"), tone: .good, hint: feeds)
        case .loading: Line(value: String(localized: "Reading"), tone: .neutral, hint: feeds)
        case .idle: Line(value: String(localized: "Off"), tone: .watch, hint: String(localized: "Not allowed yet"))
        case .unavailable: Line(value: String(localized: "Off"), tone: .watch, hint: String(localized: "Not on this device"))
        case .failed: Line(value: String(localized: "Error"), tone: .watch, hint: String(localized: "Could not be read"))
        }
    }

    static func motion(_ authorization: MotionAuthorization) -> Line {
        switch authorization {
        case .authorized:
            Line(value: String(localized: "On"), tone: .good, hint: String(localized: "Steps when no watch is worn"))
        case .notDetermined:
            Line(value: String(localized: "Not asked"), tone: .neutral, hint: String(localized: "Asked with Apple Health"))
        case .denied:
            Line(value: String(localized: "Off"), tone: .watch, hint: String(localized: "Off in Settings, Motion & Fitness"))
        case .restricted:
            Line(value: String(localized: "Off"), tone: .watch, hint: String(localized: "Restricted on this device"))
        case .unavailable:
            Line(value: String(localized: "Off"), tone: .neutral, hint: String(localized: "No step counter here"))
        }
    }

    static func blood(_ latest: Date?) -> Line {
        let hint = String(localized: "Biomarkers you add")
        guard let latest else { return Line(value: String(localized: "None"), tone: .neutral, hint: hint) }
        return Line(value: latest.formatted(.dateTime.day().month(.abbreviated)), tone: .neutral, hint: hint)
    }

    static func journal(days: Int) -> Line {
        let hint = String(localized: "Mood and habits you log")
        let value = switch days {
        case 0: String(localized: "None")
        case 1: String(localized: "1 day")
        default: String(localized: "\(days) days")
        }
        return Line(value: value, tone: .neutral, hint: hint)
    }

    /// What the info control explains, once.
    static let about: [SomaInfoSection] = [
        SomaInfoSection(
            String(localized: "Sources"),
            body: String(localized: "Most of what Soma shows comes from Apple Health. A watch, a ring or a scale writes into Health and Soma reads it there; Health access lists them. When no watch is worn, the iPhone counts steps itself. Blood panels and the Journal are what you add.")
        ),
        SomaInfoSection(
            String(localized: "Sync"),
            body: String(localized: "Soma reads Apple Health when it opens and when you pull to refresh. Everything stays on this device: there is no copy anywhere else yet.")
        ),
        SomaInfoSection(
            String(localized: "Diagnostics"),
            body: String(localized: "Crash reports say what broke and where. Usage says which pages open and how fast they load. Neither carries your name, a health value or a location, and both are off until you turn them on.")
        ),
    ]
}

#Preview("Sources and sync") {
    NavigationStack { DataDiagnosticsPage() }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
