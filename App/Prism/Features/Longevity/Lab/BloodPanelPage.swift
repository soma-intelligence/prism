//
//  BloodPanelPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The latest blood panel: how many markers sit in range, each against its
/// reference range with the reading before it, grouped the way a person
/// thinks about them, and the way to add the next one.
///
/// Panels are entered by the person (typed, or read from a photo or a PDF on
/// the device and checked) and kept on the phone. With none, the page says
/// so and the add card is the whole page.
struct BloodPanelPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var store = BloodPanelStore.shared
    @State private var profile = CardiometabolicProfileStore.shared
    @State private var bioAge: Double?
    @State private var isAdding = false

    var body: some View {
        let panel = store.latest
        let readings = panel?.markers.map(LabMath.reading) ?? []
        let outside = readings.filter(\.isOutside).count
        let ranged = readings.filter { $0.low != nil || $0.high != nil }.count

        TabPartScaffold(
            aspect: nil,
            eyebrow: panel.map { "\($0.date.labDay) · \(count($0.markers.count))" },
            title: headline(panel: panel, outside: outside, ranged: ranged),
            reason: reason(panel: panel),
            stats: panel == nil ? [] : [
                SomaStat("Biological age", value: bioAge.flatMap { LabMath.format($0, decimals: 0) }),
                SomaStat("In range", value: "\(ranged - outside)"),
                SomaStat("To watch", value: "\(outside)"),
            ]
        ) {
            if let panel {
                ForEach(BloodPanelGroup.groups(panel)) { group in
                    LabBandCard(title: group.title, eyebrow: group == BloodPanelGroup.groups(panel).first ? "Against the reference range" : nil,
                                aspect: group.aspect,
                                items: group.markers.map { value in
                                    LabBandItem(marker: value, previous: store.previous(of: value.key), route: .marker(value.key))
                                })
                }
                if store.panels.count > 1 {
                    LabRowGroup(heading: "Every panel", rows: store.panels.map { panel in
                        LabRow(panel.date.labDay, detail: count(panel.markers.count))
                    })
                }
            }
            SomaActionCard(
                eyebrow: "Add a panel",
                title: panel == nil ? "Have your results?" : "Have newer results?",
                detail: "Photograph the report. You check each value before it is saved.",
                actionTitle: "Add",
                action: { isAdding = true }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
            LabFootnote("Indicative adult ranges, not a diagnosis.")
        }
        .navigationTitle("Blood Panel")
        .sheet(isPresented: $isAdding) { AddBloodTestSheet() }
        .task(id: store.panels) { await loadAge() }
    }

    private func count(_ n: Int) -> String { n == 1 ? "one marker" : "\(n) markers" }

    private func headline(panel: BloodPanel?, outside: Int, ranged: Int) -> String {
        guard panel != nil else { return "No panel yet." }
        switch outside {
        case 0: return ranged == 0 ? "Your panel, as printed." : "Everything in range."
        case 1: return "\(ranged - 1) in range, one to watch."
        default: return "\(ranged - outside) in range, \(outside) to watch."
        }
    }

    private func reason(panel: BloodPanel?) -> String {
        guard let panel else {
            return "Add a blood test and each marker lands here against its range. Nine of them feed your biological age."
        }
        let flagged = panel.markers.filter { LabMath.reading($0).isOutside }
        if let first = flagged.first {
            let reading = LabMath.reading(first)
            let name = BloodMarkerCatalog.definition(for: first).name
            let range = reading.rangeText.map { ", \($0) is the range" } ?? ""
            return "\(name) sits at \(reading.text)\(range). Tap any marker to see it over time."
        }
        return "Every marker with a range sits inside it. Tap any marker to see it over time."
    }

    private func loadAge() async {
        guard let panel = store.latest else { bioAge = nil; return }
        let sex = profile.profile.sex ?? LabHealth.biologicalSex()
        guard let source = await health.prepare([LabMetric.dateOfBirth]),
              let age = await LabHealth.age(in: source), let sex else { bioAge = nil; return }
        bioAge = BloodAgeReading.make(panel: panel, chronologicalAge: Double(age), sex: sex)?.phenoAge
    }
}

/// The panel's markers in the groups a person reads them in.
struct BloodPanelGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let aspect: SomaAspect
    let markers: [BloodMarkerValue]

    private static let layout: [(id: String, title: String, aspect: SomaAspect, categories: [BloodMarkerCategory])] = [
        ("vessels", "Heart and vessels", .heart, [.lipids, .cardiovascular]),
        ("sugar", "Sugar and inflammation", .gut, [.metabolic, .inflammation]),
        ("vitamins", "Vitamins and hormones", .mind, [.vitamins, .minerals, .iron, .thyroid, .hormones]),
        ("organs", "Liver and kidneys", .body, [.liver, .kidney]),
        ("count", "Blood count and salts", .body, [.hematology, .electrolytes, .other]),
    ]

    static func groups(_ panel: BloodPanel) -> [BloodPanelGroup] {
        layout.compactMap { entry in
            let markers = panel.markers.filter { entry.categories.contains(BloodMarkerCatalog.definition(for: $0).category) }
            return markers.isEmpty ? nil : BloodPanelGroup(id: entry.id, title: entry.title, aspect: entry.aspect, markers: markers)
        }
    }
}

#Preview("Blood panel") {
    NavigationStack {
        BloodPanelPage()
    }
    .environment(HealthDashboard())
}
