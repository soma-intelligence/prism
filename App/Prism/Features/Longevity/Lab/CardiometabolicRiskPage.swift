//
//  CardiometabolicRiskPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Cardiometabolic risk: PREVENT's ten year estimate, what it is built from
/// against where each input should sit, what is still missing, and the one
/// lever with the most room.
///
/// Lipids and creatinine come from the blood panel, blood pressure, weight
/// and height from Health, age from Health, and four answers from the
/// person. Nothing missing is ever filled with an average: the page lists it.
struct CardiometabolicRiskPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var panels = BloodPanelStore.shared
    @State private var profile = CardiometabolicProfileStore.shared
    @State private var measurements = BodyMeasurementStore.shared
    @State private var person = LabPerson()
    @State private var pressures: [PressureReading] = []
    @State private var bmi: Double?
    @State private var waist: Double?
    @State private var height: Double?
    @State private var report: CardiometabolicRisk.Report?
    @State private var question: CardiometabolicProfile.Question?
    @State private var isAskingSex = false
    @State private var isAdding = false

    private static let inputCount = MissingRiskInput.allCases.count

    var body: some View {
        let items = builtFrom
        let flagged = items.filter(\.isFlagged).count
        let headline = report?.headline
        TabPartScaffold(
            aspect: nil,
            eyebrow: report?.panelDate.map { "Heart and metabolism · \($0.labDay)" } ?? "Heart and metabolism",
            title: title(headline, flagged: flagged),
            reason: reason(headline),
            stats: [
                SomaStat("10 year risk", value: headline?.percent.flatMap { LabMath.format($0, decimals: $0 < 10 ? 1 : 0) }, unit: "%"),
                SomaStat("Inputs", value: "\(Self.inputCount - (report?.missing.count ?? Self.inputCount)) of \(Self.inputCount)"),
                SomaStat("To watch", value: "\(flagged)"),
            ]
        ) {
            if !items.isEmpty {
                LabBandCard(title: "What the risk is built from", eyebrow: "Against where it should sit", aspect: .heart, items: items)
            }
            if let report, !report.missing.isEmpty {
                LabRowGroup(heading: missingHeading(report.missing.count), rows: report.missing.map(row))
            }
            if let report, report.inputs != nil {
                LabRowGroup(heading: "Every estimate", rows: report.estimates.map { estimate in
                    LabRow(estimateTitle(estimate), detail: estimate.percent.map { "\(SomaFormat.number($0, decimals: 1))%" } ?? refusal(estimate.refusal))
                })
            }
            lever
            LabFootnote("PREVENT (AHA, 2023). Wellness estimate, not a diagnosis.")
        }
        .labPageTitle(Text("Cardiometabolic Risk"))
        .task(id: panels.panels) { await load() }
        .onChange(of: profile.profile) { compute() }
        .sheet(isPresented: $isAdding) { AddBloodTestSheet() }
        .confirmationDialog(question?.prompt ?? "", isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
                            titleVisibility: .visible) {
            if let question {
                Button("Yes") { profile.answer(question, true) }
                Button("No") { profile.answer(question, false) }
            }
        }
        .confirmationDialog("Sex, for the model", isPresented: $isAskingSex) {
            ForEach(LabSex.allCases) { sex in
                Button(sex.title) { profile.setSex(sex); person.sex = sex; compute() }
            }
        } message: {
        }
    }

    // MARK: Rows

    private var builtFrom: [LabBandItem] {
        var items: [LabBandItem] = []
        let latest = panels.latest
        if let apoB = latest?.value("apoB") {
            items.append(LabBandItem(marker: apoB, previous: nil, route: .marker("apoB")))
        }
        if let pressure = pressures.last {
            let flagged = pressure.systolic >= 120 || pressure.diastolic >= 80
            let under = pressures.suffix(10).filter { $0.systolic < 120 && $0.diastolic < 80 }.count
            items.append(LabBandItem(
                id: "bp", title: "Blood pressure",
                detail: "under 120/80, \(under) of the last \(min(pressures.count, 10))",
                value: "\(Int(pressure.systolic))/\(Int(pressure.diastolic))",
                band: position(90, 90, 160)...position(120, 90, 160),
                position: position(pressure.systolic, 90, 160),
                isFlagged: flagged, route: .bloodPressure))
        }
        for key in ["hba1c", "crp", "ldl"] {
            if let value = latest?.value(key) {
                items.append(LabBandItem(marker: value, previous: nil, route: .marker(key)))
            }
        }
        if let waist {
            let limit = (height.map { $0 * 100 / 2 }) ?? 94
            items.append(LabBandItem(
                id: "waist", title: "Waist",
                detail: height == nil ? "under 94" : "under \(Int(limit)), half your height",
                value: "\(SomaFormat.number(waist)) cm",
                band: position(60, 60, 130)...position(limit, 60, 130),
                position: position(waist, 60, 130),
                isFlagged: waist > limit, route: .measurements))
        }
        return items
    }

    private func position(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max((v - lo) / (hi - lo), 0), 1) }

    private func row(_ missing: MissingRiskInput) -> LabRow {
        if let question = missing.question {
            return LabRow(question.title, detail: String(localized: "Add"), action: { self.question = question })
        }
        switch missing {
        case .sex: return LabRow(missing.title, detail: String(localized: "Add"), action: { isAskingSex = true })
        case .systolicBP: return LabRow(missing.title, detail: String(localized: "Add"), route: .bloodPressure)
        case .age: return LabRow(missing.title, detail: "In Health")
        default: return LabRow(missing.title, detail: "from a panel", action: { isAdding = true })
        }
    }

    private func missingHeading(_ count: Int) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        let number = count < words.count ? words[count] : "\(count)"
        return "\(number) \(count == 1 ? "input" : "inputs") missing"
    }

    @ViewBuilder
    private var lever: some View {
        if let driver = report?.drivers.first {
            SomaActionCard(
                eyebrow: "The lever",
                title: driver.label,
                detail: "Bringing it to its optimum takes \(SomaFormat.number(driver.deltaPercent, decimals: 1)) points off the ten year risk."
            ) {
                SomaObjectIcon(aspect: .heart, size: .row)
            }
        } else if let enhancer = report?.enhancers.filter({ $0.tier != .optimal }).max(by: { $0.tier < $1.tier }) {
            SomaActionCard(
                eyebrow: "The lever",
                title: "Bring \(enhancer.name) \(enhancer.lowerIsBetter ? "under" : "over") \(LabMath.format(enhancer.optimalBound, decimals: LabMath.decimals(for: enhancer.optimalBound)) ?? "")",
                detail: "It is the input with the most room to move. The next panel shows it.",
                actionTitle: "Add",
                action: { isAdding = true }
            ) {
                SomaObjectIcon(aspect: .heart, size: .row)
            }
        }
    }

    // MARK: Words

    private func title(_ headline: CardiometabolicRisk.Estimate?, flagged: Int) -> String {
        guard let tier = headline?.tier else {
            return report?.missing.isEmpty == false ? "A few inputs first." : "Outside what the model covers."
        }
        switch (tier, flagged) {
        case (.low, 0): return "Low, and nothing to watch."
        case (.low, 1): return "Low, with one lever left."
        case (.low, _): return "Low, with levers left."
        default: return "\(tier.title), with room to move."
        }
    }

    private func reason(_ headline: CardiometabolicRisk.Estimate?) -> String {
        guard let report else { return "Reading your panel and Health." }
        if let percent = headline?.percent {
            let text = "About \(SomaFormat.number(percent, decimals: 1)) in 100 people with your numbers have a heart attack or stroke in the next ten years."
            if let driver = report.drivers.first { return text + " \(driver.label) is the input with the most room to move." }
            return text
        }
        if !report.missing.isEmpty {
            return "The model needs \(report.missing.count) more \(report.missing.count == 1 ? "input" : "inputs"). Each one below says where it comes from."
        }
        return refusal(headline?.refusal)
    }

    private func estimateTitle(_ estimate: CardiometabolicRisk.Estimate) -> String {
        let outcome = switch estimate.outcome {
        case .ascvd: "Heart attack or stroke"
        case .totalCVD: "Any heart disease"
        case .heartFailure: "Heart failure"
        }
        return "\(outcome), \(estimate.horizon == .tenYear ? "10" : "30") years"
    }

    private func refusal(_ reason: PreventEquations.Ineligibility?) -> String {
        switch reason {
        case .ageOutsideValidatedRange: "outside the ages it covers"
        case .cholesterolOutsideValidatedRange: "cholesterol outside its range"
        case .systolicBPOutsideValidatedRange: "pressure outside its range"
        case .bodyMassIndexUnavailable: "needs weight and height"
        case .egfrOutsideValidatedRange: "kidney value outside its range"
        default: "not read yet"
        }
    }

    // MARK: Loading

    private func load() async {
        let now = Date()
        guard let source = await health.prepare([LabMetric.dateOfBirth, LabMetric.biologicalSex, LabMetric.systolic,
                                                 LabMetric.diastolic, LabMetric.bodyMass, LabMetric.height, LabMetric.waist]) else {
            person = LabPerson(age: nil, sex: profile.profile.sex)
            compute()
            return
        }
        person = LabPerson(age: await LabHealth.age(in: source), sex: profile.profile.sex ?? LabHealth.biologicalSex())
        pressures = await LabHealth.pressures(days: 90, now: now, calendar: .current, in: source)
        let mass = await LabHealth.points(LabMetric.bodyMass, days: 365, now: now, calendar: .current, in: source).last?.value
        height = await LabHealth.points(LabMetric.height, days: 3650, now: now, calendar: .current, in: source).last?.value
        bmi = LabMath.bmi(kilograms: mass, metres: height)
        let healthWaist = await LabHealth.points(LabMetric.waist, days: 365, now: now, calendar: .current, in: source).last
        let tapeWaist = measurements.entries.first { $0.values[.waist] != nil }
        if let tape = tapeWaist, tape.date >= (healthWaist?.date ?? .distantPast) {
            waist = tape.values[.waist]
        } else {
            waist = healthWaist.map { $0.value * 100 }
        }
        compute()
    }

    private func compute() {
        report = CardiometabolicRisk.report(
            panels: panels.panels,
            systolicBP: pressures.suffix(10).map(\.systolic).isEmpty ? nil : LabMath.mean(pressures.suffix(10).map(\.systolic)),
            ageYears: person.age.map(Double.init),
            sex: profile.profile.sex ?? person.sex,
            profile: profile.profile,
            bodyMassIndex: bmi
        )
    }
}

#Preview("Cardiometabolic risk") {
    NavigationStack {
        CardiometabolicRiskPage()
    }
    .environment(HealthDashboard())
}
