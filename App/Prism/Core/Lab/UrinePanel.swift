//
//  UrinePanel.swift
//  Prism
//
//  The stored shape of a urine test and the store that keeps them. Two kinds
//  land here: a lab report (read from a photo or a PDF, or typed, then
//  checked) and a home dipstick read by the camera (always approximate, and
//  checked pad by pad before it is saved).
//
//  Kept like the blood panels: one JSON file in Application Support/lab,
//  written atomically with complete file protection, never sent anywhere.
//

import Foundation
import Observation

/// One marker's value in a saved urine test, in the marker's storage unit.
nonisolated struct UrineValue: Codable, Sendable, Hashable, Identifiable {
    enum Source: String, Codable, Sendable { case extracted, manual, camera }

    var key: String
    var value: Double
    /// The unit the lab or the person wrote.
    var enteredUnit: String
    var source: Source
    var labRefLow: Double?
    var labRefHigh: Double?

    var id: String { key }

    var marker: UrineMarker? { UrineCatalog.marker(id: key) }

    var status: BloodMarker.RangeStatus { marker?.status(forStorage: value) ?? .unknown }

    var isOutside: Bool { status == .low || status == .high }

    /// "Trace", "1.020", "12 mg/g": the chart's word for a pad, the number
    /// and unit for the rest.
    var text: String {
        guard let marker else { return LabMath.format(value, decimals: LabMath.decimals(for: value)) ?? "-" }
        if marker.isPad, let step = marker.nearestStep(to: value), abs(step.value - value) < 0.0001 {
            return marker.unit.isEmpty || step.label.first?.isNumber != true ? step.label : "\(step.label) \(marker.unit)"
        }
        let decimals = marker.id == "specificGravity" ? 3 : LabMath.decimals(for: value)
        let number = LabMath.format(value, decimals: decimals) ?? "-"
        return marker.unit.isEmpty ? number : "\(number) \(marker.unit)"
    }
}

/// A confirmed urine test.
nonisolated struct UrinePanel: Codable, Identifiable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable {
        /// From a lab: read off the report and checked, or typed.
        case labReport
        /// A home strip read by the camera, then checked pad by pad.
        case dipstick
    }

    let id: UUID
    var sampledAt: Date?
    var createdAt: Date
    var kind: Kind
    var values: [UrineValue]

    init(id: UUID = UUID(), sampledAt: Date?, createdAt: Date, kind: Kind, values: [UrineValue]) {
        self.id = id
        self.sampledAt = sampledAt
        self.createdAt = createdAt
        self.kind = kind
        self.values = values
    }

    var date: Date { sampledAt ?? createdAt }

    /// A camera read colours, not chemistry: every dipstick panel is approximate.
    var isApproximate: Bool { kind == .dipstick }

    func value(_ key: String) -> UrineValue? { values.first { $0.key == key } }

    var flagged: [UrineValue] { values.filter(\.isOutside) }
}

@MainActor
@Observable
final class UrinePanelStore {
    static let shared: UrinePanelStore = {
        #if DEBUG
        if LabFixtures.isOn {
            let store = UrinePanelStore(url: nil)
            LabFixtures.urinePanels.forEach(store.save)
            return store
        }
        #endif
        return UrinePanelStore(url: LabFiles.url("urine-panels.json"))
    }()

    /// Newest first.
    private(set) var panels: [UrinePanel]
    private let url: URL?

    init(url: URL?) {
        self.url = url
        panels = (LabFiles.load([UrinePanel].self, from: url) ?? []).sorted { $0.date > $1.date }
    }

    var latest: UrinePanel? { panels.first }

    func save(_ panel: UrinePanel) {
        panels.removeAll { $0.id == panel.id }
        panels.append(panel)
        panels.sort { $0.date > $1.date }
        LabFiles.save(panels, to: url)
    }

    func delete(_ panel: UrinePanel) {
        panels.removeAll { $0.id == panel.id }
        LabFiles.save(panels, to: url)
    }

    /// Every urine test gone, the file with them.
    func eraseAll() {
        panels = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    /// The reading before the latest one, for "Negative in March".
    func previous(of key: String) -> (date: Date, value: UrineValue)? {
        let all = panels.compactMap { panel in panel.value(key).map { (date: panel.date, value: $0) } }
        return all.count >= 2 ? all[1] : nil
    }
}
