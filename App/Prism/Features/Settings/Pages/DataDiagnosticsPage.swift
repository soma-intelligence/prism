//
//  DataDiagnosticsPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Sources and sync: where every number comes from, what this device holds,
/// a way to read Apple Health again, and what diagnostics may leave it.
///
/// Data hub and sync diagnostics. Each
/// source says what it gave, from the store it lives in; a source with nothing
/// behind it yet says so.
struct DataDiagnosticsPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var settings = GlobalSettings.shared
    @State private var onDevice: Int64?
    @State private var lastRead: Date?
    @State private var isReading = false

    var body: some View {
        @Bindable var settings = settings

        ListScaffold(eyebrow: "Data and diagnostics", title: "Sources and sync") {
            SettingsSection("Where your numbers come from") {
                SomaBrowseGroup([SettingsItem].items("health", "blood", "journal")) { item in
                    sourceRow(item.id)
                }
            }

            SettingsSection("Sync") {
                SomaBrowseGroup([SettingsItem].items("read", "account", "device"), hasGlyphs: false) { item in
                    syncRow(item.id)
                }

                Button {
                    Task { await readAgain() }
                } label: {
                    Text(isReading ? String(localized: "Reading Apple Health") : String(localized: "Read Apple Health again"))
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                        .background(Capsule().strokeBorder(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity * 2), lineWidth: 1))
                        .contentShape(.capsule)
                }
                .buttonStyle(.somaGlassPress)
                .disabled(isReading || !health.isAvailable)

            }

            SettingsSection("Diagnostics") {
                SomaBrowseGroup([SettingsItem].items("crash", "usage"), hasGlyphs: false) { item in
                    if item.id == "crash" {
                        SettingsLine("Share crash reports", detail: "What broke and where. Never a health value") {
                            SettingsSwitch(title: "Share crash reports", isOn: $settings.diagnostics.shareCrashReports)
                        }
                    } else {
                        SettingsLine("Share usage", detail: "Which pages open, and how fast they load") {
                            SettingsSwitch(title: "Share usage", isOn: $settings.diagnostics.shareUsage)
                        }
                    }
                }
                SettingsFootnote("No name, no health value, no location.")
            }
        }
        .task { await measure() }
    }

    @ViewBuilder
    private func sourceRow(_ id: String) -> some View {
        switch id {
        case "health":
            NavigationLink(value: SettingsRoute.healthAccess) {
                SomaBrowseRow(symbol: "heart.text.square", title: String(localized: "Apple Health"),
                              detail: String(localized: "\(HealthMetricCatalog.all.count) kinds"))
            }
            .buttonStyle(.plain)
        case "blood":
            SomaBrowseRow(symbol: "drop", title: String(localized: "Blood panels"),
                          detail: bloodDetail, opensSomething: false)
        default:
            SomaBrowseRow(symbol: "square.and.pencil", title: String(localized: "Journal"),
                          detail: journalDetail, opensSomething: false)
        }
    }

    @ViewBuilder
    private func syncRow(_ id: String) -> some View {
        switch id {
        case "read":
            SettingsLine("Last read from Apple Health") {
                valueText((lastRead ?? SomaNotifications.shared.lastSync).map { $0.formatted(date: .omitted, time: .shortened) } ?? readStatus)
            }
        case "account":
            SettingsLine("Your account copy", detail: "Soma keeps no copy off this device yet") {
                valueText("-")
            }
        default:
            SettingsLine("On this device") {
                valueText(onDevice.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "-")
            }
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .somaFont(theme.typography.rowValue)
            .foregroundStyle(theme.colors.inkSecondary.color)
    }

    private var readStatus: String {
        switch health.status {
        case .unavailable: String(localized: "Not on this device")
        case .loading: String(localized: "Reading")
        case .failed: String(localized: "Failed")
        default: "-"
        }
    }

    private var bloodDetail: String {
        guard let latest = BloodPanelStore.shared.latest else {
            return String(localized: "None added")
        }
        return latest.date.formatted(.dateTime.day().month(.wide))
    }

    private var journalDetail: String {
        let count = journal.loggedDays.count
        return count == 1 ? String(localized: "1 day logged") : String(localized: "\(count) days logged")
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

#Preview("Data and diagnostics") {
    NavigationStack { DataDiagnosticsPage() }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
