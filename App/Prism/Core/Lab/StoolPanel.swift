//
//  StoolPanel.swift
//  Prism
//
//  The stored shape of a stool test and the store that keeps them. Two kinds
//  land here: a clinical lab report (calprotectin, hidden blood, elastase,
//  H. pylori) and a microbiome kit's report (diversity and taxa), both read
//  from a photo or a PDF, or typed, then checked value by value.
//
//  Kept like the blood and urine panels: one JSON file in Application
//  Support/lab, written atomically with complete file protection, never sent
//  anywhere.
//

import Foundation
import Observation

/// One marker's value in a saved stool test, in the marker's storage unit.
nonisolated struct StoolValue: Codable, Sendable, Hashable, Identifiable {
    enum Source: String, Codable, Sendable { case extracted, manual }

    var key: String
    var value: Double
    /// The unit the lab or the person wrote.
    var enteredUnit: String
    var source: Source

    var id: String { key }

    var marker: StoolMarker? { StoolCatalog.marker(id: key) }

    var flag: LabFlag { marker?.flag(value: value) ?? .noBand }

    var isOutside: Bool { flag.isOutside }

    /// What to do about it, when the result needs care.
    var advice: String? { marker?.advice(value: value) }

    /// "Positive", "85 µg/g", "3.82", "2.4%".
    var text: String {
        guard let marker else { return LabMath.format(value, decimals: LabMath.decimals(for: value)) ?? "-" }
        if marker.isQualitative { return value >= 0.5 ? "Positive" : "Negative" }
        let number = LabMath.format(value, decimals: LabMath.decimals(for: value)) ?? "-"
        if marker.unit.isEmpty { return number }
        return marker.unit == "%" ? "\(number)%" : "\(number) \(marker.unit)"
    }
}

/// A confirmed stool test.
nonisolated struct StoolPanel: Codable, Identifiable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable {
        /// A clinical lab's report.
        case labReport
        /// A microbiome kit's report: diversity and taxa.
        case microbiomeKit
    }

    let id: UUID
    var sampledAt: Date?
    var createdAt: Date
    var kind: Kind
    var values: [StoolValue]

    init(id: UUID = UUID(), sampledAt: Date?, createdAt: Date, kind: Kind, values: [StoolValue]) {
        self.id = id
        self.sampledAt = sampledAt
        self.createdAt = createdAt
        self.kind = kind
        self.values = values
    }

    var date: Date { sampledAt ?? createdAt }

    func value(_ key: String) -> StoolValue? { values.first { $0.key == key } }

    /// Every value outside its band, borderline included.
    var flagged: [StoolValue] { values.filter(\.isOutside) }

    /// The values worth a word with a clinician.
    var needingCare: [StoolValue] { values.filter { $0.flag.needsClinician } }

    /// The values that ask for a doctor soon (a positive FIT).
    var urgent: [StoolValue] { values.filter { $0.flag == .actNow } }

    /// A kit's report holds only microbiome markers.
    static func kind(for values: [StoolValue]) -> Kind {
        values.allSatisfy { $0.marker?.group == .microbiome } && !values.isEmpty ? .microbiomeKit : .labReport
    }
}

@MainActor
@Observable
final class StoolPanelStore {
    static let shared: StoolPanelStore = {
        #if DEBUG
        if LabFixtures.isOn {
            let store = StoolPanelStore(url: nil)
            LabFixtures.stoolPanels.forEach(store.save)
            return store
        }
        #endif
        return StoolPanelStore(url: LabFiles.url("stool-panels.json"))
    }()

    /// Newest first.
    private(set) var panels: [StoolPanel]
    private let url: URL?

    init(url: URL?) {
        self.url = url
        panels = (LabFiles.load([StoolPanel].self, from: url) ?? []).sorted { $0.date > $1.date }
    }

    var latest: StoolPanel? { panels.first }

    func save(_ panel: StoolPanel) {
        panels.removeAll { $0.id == panel.id }
        panels.append(panel)
        panels.sort { $0.date > $1.date }
        LabFiles.save(panels, to: url)
    }

    func delete(_ panel: StoolPanel) {
        panels.removeAll { $0.id == panel.id }
        LabFiles.save(panels, to: url)
    }

    /// Every reading of one marker, oldest first: diversity and taxa read
    /// against these, never against a population band.
    func history(of key: String) -> [(date: Date, value: StoolValue)] {
        panels.compactMap { panel in panel.value(key).map { (panel.date, $0) } }.sorted { $0.date < $1.date }
    }

    /// The reading before the latest one, for "3.4 in June".
    func previous(of key: String) -> (date: Date, value: StoolValue)? {
        let all = history(of: key)
        return all.count >= 2 ? all[all.count - 2] : nil
    }
}
