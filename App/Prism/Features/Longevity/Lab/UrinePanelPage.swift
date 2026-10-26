//
//  UrinePanelPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The latest urine test: how many markers sit at their usual result, each
/// on a rail against its range grouped the way a person reads them, every
/// earlier test, and the way to add the next one.
///
/// A dipstick read by the camera says "approximate" in the eyebrow and in
/// the footnote: it matched colours, it did not measure chemistry.
struct UrinePanelPage: View {
    @State private var store = UrinePanelStore.shared
    @State private var isAdding = false

    var body: some View {
        let panel = store.latest
        let outside = panel?.flagged.count ?? 0
        let ranged = panel?.values.filter { $0.status != .unknown }.count ?? 0

        TabPartScaffold(
            aspect: nil,
            eyebrow: panel.map { "\($0.date.labDay) · \(kind($0))" },
            title: headline(panel: panel, outside: outside),
            reason: reason(panel: panel),
            stats: panel == nil ? [] : [
                SomaStat("Markers", value: "\(panel?.values.count ?? 0)"),
                SomaStat("Usual", value: "\(ranged - outside)"),
                SomaStat("To watch", value: "\(outside)"),
            ]
        ) {
            if let panel {
                let groups = UrineMarkerGroup.allCases.compactMap { group -> (UrineMarkerGroup, [UrineValue])? in
                    let values = panel.values.filter { $0.marker?.group == group }
                    return values.isEmpty ? nil : (group, values)
                }
                ForEach(groups, id: \.0) { group, values in
                    LabBandCard(title: group.title,
                                eyebrow: group == groups.first?.0 ? (panel.isApproximate ? "Approximate, against the usual result" : "Against the usual result") : nil,
                                aspect: .body,
                                items: values.map { LabBandItem(urine: $0, previous: store.previous(of: $0.key)) })
                }
                if store.panels.count > 1 {
                    LabRowGroup(heading: "Every test", rows: store.panels.map { panel in
                        LabRow("\(panel.date.labDay), \(kind(panel))", detail: panel.flagged.isEmpty ? "all usual" : "\(panel.flagged.count) to watch")
                    })
                }
            }
            SomaActionCard(
                eyebrow: "Add a urine test",
                title: panel == nil ? "A lab report or a strip?" : "Have a newer test?",
                detail: "Photograph a lab report, or read a ten pad strip with the camera. You check each value before it is saved.",
                actionTitle: "Add",
                action: { isAdding = true }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
            LabFootnote(panel?.isApproximate == true
                        ? "A strip read by the camera is approximate: light, timing and the brand's chart all move it. Informational, never a diagnosis. For a result that worries you, ask a doctor or a pharmacist."
                        : "Indicative adult ranges, not a diagnosis. For a result that worries you, ask a doctor.")
        }
        .labPageTitle(Text("Urine"))
        .sheet(isPresented: $isAdding) { AddUrineTestSheet() }
    }

    private func kind(_ panel: UrinePanel) -> String {
        panel.kind == .dipstick ? "strip, approximate" : "lab report"
    }

    private func headline(panel: UrinePanel?, outside: Int) -> String {
        guard panel != nil else { return "No urine test yet." }
        switch outside {
        case 0: return "Everything at its usual result."
        case 1: return "One to watch."
        default: return "\(outside) to watch."
        }
    }

    private func reason(panel: UrinePanel?) -> String {
        guard let panel else {
            return "Add a lab report or read a home strip, and each marker lands here against its usual result: hydration, sugar, kidneys and signs of infection."
        }
        if let first = panel.flagged.first, let marker = first.marker {
            return "\(marker.name) reads \(first.text) against a usual \(marker.usual.lowercased()). One reading is a snapshot: a repeat, or a word with a doctor, says more."
        }
        return "Every marker sits at its usual result."
    }
}

extension LabBandItem {
    /// A urine marker as a band line. A pad sits on its chart, step by step,
    /// with the usual steps as the band; a lab value on a rail like blood.
    init(urine value: UrineValue, previous: (date: Date, value: UrineValue)?) {
        let marker = value.marker
        var detail = marker.map { "usual \($0.usual.lowercased())" } ?? "no usual result"
        if let previous {
            detail += " · \(previous.value.text) in \(previous.date.formatted(.dateTime.month(.wide)))"
        }
        var band: ClosedRange<Double>?
        var position: Double?
        if let marker, marker.isPad, marker.steps.contains(where: { abs($0.value - value.value) < 0.000_1 }) {
            let last = Double(max(marker.steps.count - 1, 1))
            let usual = marker.steps.indices.filter { marker.status(forStorage: marker.steps[$0].value) == .normal }
            if let lo = usual.first, let hi = usual.last {
                band = (Double(lo) / last)...(Double(hi) / last)
            }
            let nearest = marker.steps.indices.min { abs(marker.steps[$0].value - value.value) < abs(marker.steps[$1].value - value.value) }
            position = nearest.map { Double($0) / last }
        } else if let marker {
            let domain = LabMath.domain(value: value.value, low: marker.refLow, high: marker.refHigh)
            let span = max(domain.upperBound - domain.lowerBound, 0.000_1)
            func at(_ x: Double) -> Double { min(max((x - domain.lowerBound) / span, 0), 1) }
            if marker.refLow != nil || marker.refHigh != nil {
                band = at(marker.refLow ?? domain.lowerBound)...at(marker.refHigh ?? domain.upperBound)
            }
            position = at(value.value)
        }
        self.init(id: value.key, title: marker?.name ?? value.key, detail: detail, value: value.text,
                  band: band, position: position, isFlagged: value.isOutside)
    }
}

#Preview("Urine") {
    NavigationStack {
        UrinePanelPage()
    }
}
