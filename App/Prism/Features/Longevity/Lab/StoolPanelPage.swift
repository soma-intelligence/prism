//
//  StoolPanelPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The latest stool test: a positive stool blood test first, as a call to a
/// doctor and never a score shown alone; the lab markers against their bands;
/// the microbiome against the person's own earlier tests, since no healthy
/// value is agreed; every earlier test; and the way to add the next one.
struct StoolPanelPage: View {
    @State private var store = StoolPanelStore.shared
    @State private var isAdding = false

    var body: some View {
        let panel = store.latest
        let banded = panel?.values.filter { $0.flag != .noBand } ?? []
        let outside = panel?.flagged.count ?? 0

        TabPartScaffold(
            aspect: nil,
            eyebrow: panel.map { "\($0.date.labDay) · \(Self.kind($0))" },
            title: Self.headline(panel: panel),
            reason: Self.reason(panel: panel),
            stats: panel == nil ? [] : [
                SomaStat("Markers", value: "\(panel?.values.count ?? 0)"),
                SomaStat("Usual", value: banded.isEmpty ? nil : "\(banded.count - outside)"),
                SomaStat("To watch", value: banded.isEmpty ? nil : "\(outside)"),
            ]
        ) {
            if let panel {
                ForEach(panel.needingCare) { value in
                    SomaActionCard(
                        eyebrow: value.flag == .actNow ? "See a doctor about this result" : "Worth a word with a clinician",
                        title: "\(value.marker?.name ?? value.key): \(value.text)",
                        detail: value.advice
                    ) {
                        SomaOrb(aspect: .gut, scale: .mini)
                    }
                }
                let groups = StoolMarkerGroup.allCases.compactMap { group -> (StoolMarkerGroup, [StoolValue])? in
                    let values = panel.values.filter { $0.marker?.group == group }
                    return values.isEmpty ? nil : (group, values)
                }
                ForEach(groups, id: \.0) { group, values in
                    LabBandCard(title: group.title,
                                eyebrow: group == .microbiome ? "Against your own tests" : "Against the usual result",
                                aspect: .gut,
                                items: values.map { LabBandItem(stool: $0, previous: store.previous(of: $0.key)) })
                }
                if store.panels.count > 1 {
                    LabRowGroup(heading: "Every test", rows: store.panels.map { panel in
                        LabRow("\(panel.date.labDay), \(Self.kind(panel))",
                               detail: panel.flagged.isEmpty ? "\(panel.values.count) markers" : "\(panel.flagged.count) to watch")
                    })
                }
            }
            SomaActionCard(
                eyebrow: "Add a stool test",
                title: panel == nil ? "A lab report or a microbiome kit?" : "Have a newer test?",
                detail: "Photograph the report or import its PDF. You check each value before it is saved.",
                actionTitle: "Add",
                action: { isAdding = true }
            ) {
                SomaOrb(aspect: .gut, scale: .mini)
            }
            LabFootnote("Bands from NICE (calprotectin), the US Multi-Society Task Force (stool blood), HaPanEU (elastase) and the ACG (H. pylori). Diversity and bacteria have no agreed healthy value, so they read against your own tests. Informational, never a diagnosis. For a result that worries you, ask a doctor.")
        }
        .labPageTitle(Text("Gut"))
        .sheet(isPresented: $isAdding) { AddStoolTestSheet() }
    }

    static func kind(_ panel: StoolPanel) -> String {
        panel.kind == .microbiomeKit ? "microbiome kit" : "lab report"
    }

    /// Never a score alone when a result asks for a doctor.
    static func headline(panel: StoolPanel?) -> String {
        guard let panel else { return "No stool test yet." }
        if !panel.urgent.isEmpty { return "One result needs a doctor." }
        let banded = panel.values.filter { $0.flag != .noBand }
        if banded.isEmpty { return "Your microbiome, against your own tests." }
        switch panel.flagged.count {
        case 0: return "Everything at its usual result."
        case 1: return "One to watch."
        default: return "\(panel.flagged.count) to watch."
        }
    }

    static func reason(panel: StoolPanel?) -> String {
        guard let panel else {
            return "Add a lab report or a microbiome kit's results, and each marker lands here: inflammation, hidden blood, digestion and the bacteria you carry."
        }
        if let first = panel.needingCare.first, let advice = first.advice { return advice }
        if let first = panel.flagged.first, let marker = first.marker {
            return "\(marker.name) reads \(first.text) against a usual \(marker.usual.lowercased()). One reading is a snapshot: a repeat says more."
        }
        return "Diversity and bacteria vary widely between healthy people, so Soma shows how yours move from test to test."
    }
}

extension LabBandItem {
    /// A stool marker as a band line: a lab value on a rail against its
    /// band, a microbiome value with no band and its previous reading.
    init(stool value: StoolValue, previous: (date: Date, value: StoolValue)?) {
        let marker = value.marker
        var detail: String
        switch value.flag {
        case .noBand: detail = "No agreed range"
        default: detail = marker.map { "usual \($0.usual.lowercased())" } ?? "no usual result"
        }
        if let previous {
            detail += " · \(previous.value.text) in \(previous.date.formatted(.dateTime.month(.wide)))"
        }
        var band: ClosedRange<Double>?
        var position: Double?
        if let marker, !marker.isQualitative {
            let limits: (low: Double?, high: Double?) = switch marker.id {
            case "calprotectin": (nil, 50)
            case "elastase": (200, nil)
            default: (nil, nil)
            }
            if limits.low != nil || limits.high != nil {
                let domain = LabMath.domain(value: value.value, low: limits.low, high: limits.high)
                let span = max(domain.upperBound - domain.lowerBound, 0.000_1)
                func at(_ x: Double) -> Double { min(max((x - domain.lowerBound) / span, 0), 1) }
                band = at(limits.low ?? domain.lowerBound)...at(limits.high ?? domain.upperBound)
                position = at(value.value)
            }
        }
        self.init(id: value.key, title: marker?.name ?? value.key, detail: detail, value: value.text,
                  band: band, position: position, isFlagged: value.isOutside,
                  bandWord: value.flag == .borderline ? String(localized: "Borderline") : nil)
    }
}

#Preview("Gut") {
    NavigationStack {
        StoolPanelPage()
    }
}
