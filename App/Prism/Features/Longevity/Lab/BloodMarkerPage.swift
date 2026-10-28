//
//  BloodMarkerPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// One blood marker over every panel: the latest value against its range,
/// the line through each reading, what it means and what moves it, and the
/// markers and pages next to it.
struct BloodMarkerPage: View {
    let markerID: String

    @State private var store = BloodPanelStore.shared
    @State private var isAdding = false

    var body: some View {
        let history = store.history(of: markerID)
        let definition = history.last.map { BloodMarkerCatalog.definition(for: $0.value) }
            ?? BloodMarkerCatalog.marker(id: markerID)
            ?? BloodMarkerCatalog.custom(id: markerID, name: markerID, unit: "")
        let latest = history.last.map { LabMath.reading($0.value) }
        let points = history.map { LabPoint(date: $0.date, value: LabMath.reading($0.value).value) }
        let notes = BloodMarkerNotes.notes(for: markerID)

        TabPartScaffold(
            aspect: nil,
            eyebrow: history.last.map { "Blood panel · \($0.date.labDay)" },
            title: headline(latest: latest, points: points),
            reason: reason(definition: definition, latest: latest, points: points),
            stats: []
        ) {
            SomaChartCard(
                eyebrow: definition.name,
                value: latest.flatMap { LabMath.format($0.value, decimals: LabMath.decimals(for: $0.value)) },
                unit: latest?.unit,
                note: points.count >= 2 ? "\(points.count) panels so far." : (points.isEmpty ? "No panel carries it yet." : "One panel so far. The next one draws the line.")
            ) {
                if !points.isEmpty {
                    LabLineChart(points: points,
                                 band: band(latest),
                                 aspect: .heart,
                                 isFlagged: latest?.isOutside ?? false,
                                 reference: latest?.high ?? latest?.low)
                }
            }
            if let notes {
                LabExplainCard(sections: [("What it means", notes.means), ("What moves it", notes.moves)])
            }
            SomaActionCard(
                eyebrow: "When to retest",
                title: "With the next panel",
                detail: notes?.retest ?? "Most markers move over eight to twelve weeks, not days.",
                actionTitle: "Add",
                action: { isAdding = true }
            ) {
                SomaObjectIcon(aspect: .heart, size: .row)
            }
            LabRowGroup(rows: related)
        }
        .labPageTitle(Text(definition.name))
        .sheet(isPresented: $isAdding) { AddBloodTestSheet() }
    }

    private var related: [LabRow] {
        var rows: [LabRow] = BloodMarkerNotes.related(markerID).compactMap { id in
            guard let marker = BloodMarkerCatalog.marker(id: id) else { return nil }
            let value = store.latest?.value(id).map { LabMath.reading($0).text }
            return LabRow(marker.name, detail: value, route: .marker(id))
        }
        if BloodMarkerCatalog.marker(id: markerID)?.category == .lipids || markerID == "hba1c" || markerID == "crp" {
            rows.append(LabRow("Cardiometabolic risk", route: .risk))
        }
        rows.append(LabRow("The whole panel", route: .bloodPanel))
        return rows
    }

    private func band(_ reading: LabMath.MarkerReading?) -> ClosedRange<Double>? {
        guard let reading, reading.low != nil || reading.high != nil else { return nil }
        let low = reading.low ?? 0
        let high = reading.high ?? reading.value * 1.5
        return low...high
    }

    private func headline(latest: LabMath.MarkerReading?, points: [LabPoint]) -> String {
        guard let latest else { return "Not measured yet." }
        let falling = points.count >= 2 && points[points.count - 1].value < points[points.count - 2].value
        let rising = points.count >= 2 && points[points.count - 1].value > points[points.count - 2].value
        switch latest.status {
        case .high: return falling ? "Above the line, and falling." : "Above the line."
        case .low: return rising ? "Below the line, and rising." : "Below the line."
        case .normal: return "In range."
        case .unknown: return "As the lab printed it."
        }
    }

    private func reason(definition: BloodMarker, latest: LabMath.MarkerReading?, points: [LabPoint]) -> String {
        guard let latest else { return "Add a panel that carries \(definition.name) and it lands here with its range." }
        var text = "\(definition.name) reads \(latest.text)"
        if points.count >= 2, let first = points.first {
            let from = SomaFormat.number(first.value, decimals: LabMath.decimals(for: first.value))
            text += ", from \(from) on \(first.date.labDay)"
        }
        text += "."
        if let range = latest.rangeText { text += " The range is \(range)." }
        return text
    }
}

/// What a marker means and what moves it, for the markers a person asks
/// about most. Written for Soma.
enum BloodMarkerNotes {
    struct Notes {
        var means: String
        var moves: String
        var retest: String?
    }

    static func notes(for id: String) -> Notes? {
        switch id {
        case "apoB":
            Notes(means: "Each particle that carries cholesterol into an artery wall wears one ApoB. The number is a count of them, and it says more than LDL alone.",
                  moves: "Soluble fibre, fewer saturated fats and steady zone 2. It moves slowly: a change shows after eight to twelve weeks.",
                  retest: "Ten weeks after a change is when ApoB shows it.")
        case "ldl":
            Notes(means: "The cholesterol carried in LDL particles. Useful, and read best beside ApoB.",
                  moves: "Saturated fat, soluble fibre, weight and, when prescribed, a statin.")
        case "hdl":
            Notes(means: "Cholesterol travelling back to the liver. Low HDL often travels with high triglycerides.",
                  moves: "Regular aerobic exercise and less refined sugar raise it slowly.")
        case "triglycerides":
            Notes(means: "Fat carried in the blood after meals and made from spare sugar.",
                  moves: "Less alcohol and refined sugar, more movement after meals. It answers within weeks.")
        case "hba1c":
            Notes(means: "The share of haemoglobin with sugar stuck to it: an average of the last three months.",
                  moves: "Walking after meals, fibre first, sleep. It needs three months to show a change.",
                  retest: "Three months after a change is when HbA1c shows it.")
        case "glucose":
            Notes(means: "Sugar in the blood after a night without food.",
                  moves: "Sleep, the evening meal’s size and timing, and muscle that takes sugar up.")
        case "crp":
            Notes(means: "A protein the liver makes when there is inflammation anywhere in the body.",
                  moves: "A cold or a hard session raises it for days. Sleep, fibre and less visceral fat lower it over weeks.")
        case "vitaminD":
            Notes(means: "The stored form of vitamin D, made in the skin under the sun.",
                  moves: "Midday sun on bare skin and, through winter, a supplement.")
        case "ferritin":
            Notes(means: "The body’s iron store. Low leaves you tired; high can mean inflammation.",
                  moves: "Iron in food, blood loss and inflammation.")
        case "tsh":
            Notes(means: "The signal the brain sends the thyroid. High means the thyroid is being pushed.",
                  moves: "Mostly the thyroid itself. Retest before reading anything into one value.")
        case "lpA":
            Notes(means: "A particle set by your genes. One measure in a lifetime is usually enough.",
                  moves: "Very little. Knowing it matters because it raises the weight of everything else.")
        default:
            nil
        }
    }

    static func related(_ id: String) -> [String] {
        switch id {
        case "apoB": ["ldl", "lpA"]
        case "ldl": ["apoB", "hdl"]
        case "hdl": ["triglycerides", "ldl"]
        case "triglycerides": ["hdl", "hba1c"]
        case "hba1c": ["glucose", "insulin"]
        case "glucose": ["hba1c", "insulin"]
        case "crp": ["ferritin"]
        default: []
        }
    }
}
