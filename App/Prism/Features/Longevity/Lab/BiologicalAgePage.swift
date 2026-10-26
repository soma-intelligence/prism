//
//  BiologicalAgePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Biological age: the half ring read against your calendar age, what moved
/// it, how sure it is and every marker behind it.
///
/// The blood panel feeds PhenoAge; Health feeds the rest (VO2 max, heart
/// rate variability, resting heart rate, sleep, steps, weight, body fat,
/// blood pressure). With neither, or without an age and a sex, the page says
/// which is missing and offers the one action that fills it.
struct BiologicalAgePage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var panels = BloodPanelStore.shared
    @State private var profile = CardiometabolicProfileStore.shared
    @State private var person = LabPerson()
    @State private var result: BiologicalAge.Result?
    @State private var blood: BloodAgeReading?
    @State private var isAdding = false
    @State private var isShowingConfidence = false
    @State private var isAskingSex = false

    var body: some View {
        let words = BiologicalAgeWords(result: result, blood: blood, person: person, panel: panels.latest)
        TabPartScaffold(aspect: nil, eyebrow: words.eyebrow, title: words.headline, reason: words.reason, stats: []) {
            SomaCard {
                LabAgeGauge(estimate: result?.estimatedAge, age: person.age.map(Double.init), caption: words.gaugeCaption)
            }
            if let result, !result.components.isEmpty {
                SomaChartCard(
                    eyebrow: "What moves it",
                    value: LabMath.signed(result.deltaYears, decimals: 0),
                    unit: "years against your age",
                    note: words.movesNote
                ) {
                    LabContributors(items: result.components
                        .sorted { abs($0.yearsDelta) > abs($1.yearsDelta) }
                        .map { .init(id: $0.id, label: $0.label, amount: $0.yearsDelta,
                                     text: LabMath.signed($0.yearsDelta, decimals: 1) ?? "-") })
                }
            }
            LabRowGroup(rows: rows)
            SomaActionCard(
                eyebrow: panels.latest == nil ? "First panel" : "Next panel",
                title: panels.latest == nil ? "Add a blood test" : "Add newer results",
                detail: "A panel sharpens biological age more than any other input.",
                actionTitle: "Add",
                action: { isAdding = true }
            ) {
                SomaObjectIcon(aspect: .body, size: .row)
            }
            LabFootnote("Wellness estimate, not a diagnosis.")
        }
        .labPageTitle(Text("Biological Age"))
        .task(id: panels.panels) { await load() }
        .sheet(isPresented: $isAdding) { AddBloodTestSheet() }
        .sheet(isPresented: $isShowingConfidence) { ConfidenceSheet(result: result, person: person) }
        .confirmationDialog("Sex, for the reference ranges", isPresented: $isAskingSex) {
            ForEach(LabSex.allCases) { sex in
                Button(sex.title) {
                    profile.setSex(sex)
                    Task { await load() }
                }
            }
        } message: {
        }
    }

    private var rows: [LabRow] {
        var rows: [LabRow] = []
        if person.sex == nil {
            rows.append(LabRow("Sex", detail: "-", action: { isAskingSex = true }))
        }
        rows.append(LabRow("How sure", detail: result.map { "give or take \(Int($0.confidence.spread))" } ?? "-",
                           action: { isShowingConfidence = true }))
        let count = panels.latest?.markers.count
        rows.append(LabRow("Every marker", detail: count.map { "\($0) in the panel" } ?? "No panel yet", route: .bloodPanel))
        return rows
    }

    private func load() async {
        let now = Date()
        guard let source = await health.prepare(LabReads.bioAgeMetrics) else {
            person = LabPerson(age: nil, sex: profile.profile.sex)
            return
        }
        person = LabPerson(age: await LabHealth.age(in: source), sex: profile.profile.sex ?? LabHealth.biologicalSex())
        let read = await LabReads.bioAgeInputs(from: source, person: person, panel: panels.latest,
                                               panels: panels.panels.count, now: now, calendar: .current)
        if person.age == nil { person.age = read.daily.ageYears.map { Int($0) } }
        var inputs = read.inputs
        // A lab VO2 max under a year old replaces the watch's estimate.
        inputs?.labVO2 = FunctionalResultStore.shared.labVO2
        inputs?.asOf = now
        result = inputs.flatMap(BiologicalAge.compute)
        if let panel = panels.latest, let age = person.age, let sex = person.sex {
            blood = BloodAgeReading.make(panel: panel, chronologicalAge: Double(age), sex: sex)
        } else {
            blood = nil
        }
    }
}

/// The page's words, from the result.
struct BiologicalAgeWords {
    let result: BiologicalAge.Result?
    let blood: BloodAgeReading?
    let person: LabPerson
    let panel: BloodPanel?

    var eyebrow: String {
        if let panel { return "Blood panel · \(panel.date.labDay)" }
        return "From Health"
    }

    var headline: String {
        guard let age = person.age else { return "Your age first." }
        guard person.sex != nil else { return "One answer first." }
        guard let result else { return "Not enough to read yet." }
        let delta = Int(result.deltaYears)
        if delta < 0 { return "Your body reads younger than \(age)." }
        if delta > 0 { return "Your body reads older than \(age)." }
        return "Your body reads your age."
    }

    var reason: String {
        guard person.age != nil else {
            return "Health has no date of birth. Add it in Health and the age this is read against appears."
        }
        guard person.sex != nil else {
            return "The reference ranges differ by sex, and Health does not say. Answer below and the estimate follows."
        }
        guard let result else {
            return "Two weeks of your watch or a blood panel is enough for a first estimate. A panel moves it most."
        }
        let estimate = LabMath.format(result.estimatedAge, decimals: 0) ?? "-"
        let strongest = result.components.max { abs($0.yearsDelta) < abs($1.yearsDelta) }
        var text = "\(result.components.count) inputs put you at \(estimate)."
        if let strongest {
            text += " \(strongest.label) moves it most, \(LabMath.signed(strongest.yearsDelta, decimals: 1) ?? "") years."
        }
        return text
    }

    var gaugeCaption: String? {
        guard let result else { return nil }
        let years = Int(abs(result.deltaYears))
        if years == 0 { return "Your age" }
        let unit = years == 1 ? "year" : "years"
        return result.deltaYears < 0 ? "\(years) \(unit) younger" : "\(years) \(unit) older"
    }

    var movesNote: String? {
        if let blood, let top = blood.movers.first {
            return "In the blood, \(top.key.displayName) moves it most: \(LabMath.signed(top.years, decimals: 1) ?? "") years."
        }
        return "Each input against people your age. The blood panel counts once you add one."
    }
}

/// How sure each estimate is: the band around it and what it rests on.
struct ConfidenceSheet: View {
    let result: BiologicalAge.Result?
    let person: LabPerson

    var body: some View {
        let spread = result?.confidence.spread
        LabSheet(
            eyebrow: "Biological age · \(result.flatMap { LabMath.format($0.estimatedAge, decimals: 0) } ?? "-")",
            title: "How sure it is",
            reason: reason
        ) {
            LabBandCard(title: "Each estimate, with its band", items: [
                LabBandItem(
                    id: "bio",
                    title: "Biological age",
                    detail: spread.map { "give or take \(Int($0)), \(basis)" } ?? "not enough yet",
                    value: result.flatMap { LabMath.format($0.estimatedAge, decimals: 0) },
                    band: result.map { band($0.estimatedAge, spread: $0.confidence.spread) },
                    position: result.map { position($0.estimatedAge) }
                ),
            ])
        }
    }

    private var basis: String {
        guard let result else { return "" }
        var parts: [String] = []
        if result.bloodPanels > 0 { parts.append(result.bloodPanels == 1 ? "one panel" : "\(result.bloodPanels) panels") }
        if result.coverageDays > 0 { parts.append("\(result.coverageDays) days of Health") }
        return parts.joined(separator: ", ")
    }

    private var reason: String {
        guard let result else {
            return "There is no estimate yet, so there is no band. Two weeks of your watch or a blood panel starts one."
        }
        return "Give or take \(Int(result.confidence.spread)) years. The band narrows with more days from your watch and with a second panel. Every estimate on Body carries one like it."
    }

    private func position(_ age: Double) -> Double { min(max((age - 20) / 60, 0), 1) }

    private func band(_ age: Double, spread: Double) -> ClosedRange<Double> {
        position(age - spread)...position(age + spread)
    }
}

#Preview("Biological age") {
    NavigationStack {
        BiologicalAgePage()
    }
    .environment(HealthDashboard())
}
