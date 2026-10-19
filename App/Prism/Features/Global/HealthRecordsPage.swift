//
//  HealthRecordsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Your clinic's records, by kind, through Apple Health.
///
/// Health records, opened from the chat drawer. Reading
/// them needs Apple's clinical records capability (`HKClinicalRecord`), which
/// this build is not signed for: the HealthKit entitlement carries no
/// `health-records` access. So the page lists the kinds a clinic sends and says
/// plainly that none can be read yet, instead of showing counts it does not
/// have. Blood panels typed in by hand live in Longevity > Body, and the last
/// one is offered here.
struct HealthRecordsPage: View {
    @Environment(\.somaTheme) private var theme

    private let kinds: [RecordKind] = [
        RecordKind(id: "labs", title: String(localized: "Lab results"), symbol: "testtube.2"),
        RecordKind(id: "vitals", title: String(localized: "Vital signs"), symbol: "waveform.path.ecg"),
        RecordKind(id: "vaccines", title: String(localized: "Vaccines"), symbol: "syringe"),
        RecordKind(id: "allergies", title: String(localized: "Allergies"), symbol: "allergens"),
        RecordKind(id: "conditions", title: String(localized: "Conditions"), symbol: "stethoscope"),
        RecordKind(id: "medications", title: String(localized: "Medications"), symbol: "pills"),
        RecordKind(id: "procedures", title: String(localized: "Procedures"), symbol: "cross.case"),
    ]

    var body: some View {
        ListScaffold(eyebrow: "Through Apple Health", title: "Your clinic\u{2019}s records, by kind.") {

            SomaBrowseGroup(kinds) { kind in
                SomaBrowseRow(symbol: kind.symbol, title: kind.title, detail: "-", opensSomething: false)
            }

            NoteCard(
                title: "Not connected yet",
                message: "Clinical records come into Apple Health from your clinic\u{2019}s patient portal, under Health > Browse > Health Records. Soma can\u{2019}t read them yet: this version is not signed for Apple\u{2019}s clinical records access. Until it is, each kind shows a dash."
            )

            latestPanel
        }
        .navigationTitle("Health records")
        .toolbarTitleDisplayMode(.inline)
    }

    /// The last blood panel typed into Soma, which is on this device already.
    @ViewBuilder
    private var latestPanel: some View {
        if let panel = BloodPanelStore.shared.latest {
            SettingsSection("Newest panel you added") {
                SomaBrowseGroup([SettingsItem(id: "panel")], hasGlyphs: false) { _ in
                    SettingsLine(
                        panel.date.formatted(.dateTime.day().month(.wide).year()),
                        detail: panel.markers.count == 1
                            ? String(localized: "1 marker")
                            : String(localized: "\(panel.markers.count) markers")
                    ) { EmptyView() }
                }
            }
        }
    }
}

private struct RecordKind: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

#Preview("Health records") {
    NavigationStack { HealthRecordsPage() }
}
