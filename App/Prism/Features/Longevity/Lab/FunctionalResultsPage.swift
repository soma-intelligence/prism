//
//  FunctionalResultsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Imaging and functional tests: one card per test with its latest values
/// against their bands and the reading before, a word with a clinician when
/// a result asks for one, the tests not added yet, and the way to add one.
///
/// A value no source bands (VO2 max, a mass, a wall thickness) reads against
/// the person's own earlier tests only.
struct FunctionalResultsPage: View {
    @State private var store = FunctionalResultStore.shared
    @State private var adding: FunctionalAddRequest?
    @State private var isTesting = false

    private var measures: MeasureSystem { GlobalSettings.shared.units.measures }
    private var sex: LabSex? { CardiometabolicProfileStore.shared.profile.sex }

    var body: some View {
        let kinds = store.kinds
        let latest = store.latest
        let care = FunctionalPageText.needingCare(store: store, sex: sex)

        TabPartScaffold(
            aspect: nil,
            eyebrow: latest.map { "\($0.date.labDay) · \($0.kind.title)" },
            title: FunctionalPageText.headline(tests: kinds.count, care: care.count),
            reason: FunctionalPageText.reason(tests: kinds.count, care: care),
            stats: kinds.isEmpty ? [] : [
                SomaStat("Tests", value: "\(kinds.count)"),
                SomaStat("Results", value: "\(store.results.count)"),
                SomaStat("To discuss", value: "\(care.count)"),
            ]
        ) {
            if !care.isEmpty {
                SomaActionCard(
                    eyebrow: "Worth a word with a clinician",
                    title: care.map(\.title).joined(separator: ", "),
                    detail: "These results sit where guidelines suggest talking them through with a doctor. Bring the report: a number alone is never a diagnosis."
                ) {
                    SomaOrb(aspect: .heart, scale: .mini)
                }
            }
            ForEach(kinds) { kind in
                if let result = store.latest(kind) {
                    LabBandCard(title: kind.title,
                                eyebrow: result.date.labDay,
                                aspect: .body,
                                items: FunctionalItems.items(result, previous: store.history(kind).dropLast().last,
                                                             measures: measures, sex: sex, route: .functionalKind(kind)))
                }
            }
            // The one test Soma runs itself: a walk or a step test, here
            // beside the reports a clinic sends.
            SomaActionCard(
                eyebrow: "Cardio fitness test",
                title: store.latest(.fieldVO2) == nil ? "Estimate your VO2 max with a walk" : "Run the cardio fitness test again",
                detail: "A mile, six minutes or three minutes on a step, guided on your iPhone. An estimate, not a lab test.",
                actionTitle: "Start",
                action: { isTesting = true }
            ) {
                SomaOrb(aspect: .heart, scale: .mini)
            }
            let missing = FunctionalTestKind.reported.filter { !kinds.contains($0) }
            if !missing.isEmpty {
                LabRowGroup(heading: kinds.isEmpty ? "The tests" : "Not added yet", rows: missing.map { kind in
                    LabRow(kind.title, detail: "Add", action: { adding = FunctionalAddRequest(kind: kind) })
                })
            }
            SomaActionCard(
                eyebrow: "Add a result",
                title: kinds.isEmpty ? "Had a scan or a test?" : "Have a newer result?",
                detail: "Import the report as a PDF or a photo, or type the values. Read on this phone, and you check each value before it is saved.",
                actionTitle: "Add",
                action: { adding = FunctionalAddRequest(kind: nil) }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
            LabFootnote("Bands from the WHO (bone density), AHA/ACC 2018 (calcium score), GOLD 2024 (spirometry) and EWGSOP2 (grip). Informational, never a diagnosis. For a result that worries you, ask a doctor.")
        }
        .labPageTitle(Text("Tests"))
        .sheet(item: $adding) { request in AddFunctionalResultSheet(kind: request.kind) }
        .cardioFitnessTest(isPresented: $isTesting)
    }
}

/// One test over every result: the headline value on a line, the latest
/// values against their bands, what the test means, and every result.
struct FunctionalKindPage: View {
    let kind: FunctionalTestKind

    @State private var store = FunctionalResultStore.shared
    @State private var adding: FunctionalAddRequest?
    @State private var isTesting = false

    private var measures: MeasureSystem { GlobalSettings.shared.units.measures }
    private var sex: LabSex? { CardiometabolicProfileStore.shared.profile.sex }

    var body: some View {
        let history = store.history(kind)
        let latest = history.last
        let field = FunctionalCatalog.field(kind.headlineField, in: kind)
        let points = history.compactMap { result in result.values[kind.headlineField].map { LabPoint(date: result.date, value: $0) } }
        let note = latest.flatMap { result in result.values[kind.headlineField].flatMap { FunctionalAssessment.note(field: kind.headlineField, value: $0, sex: sex) } }

        TabPartScaffold(
            aspect: nil,
            eyebrow: latest.map { "\($0.date.labDay) · \(kind.title)" } ?? kind.title,
            title: latest == nil ? "No result yet." : field.flatMap { field in
                field.text(latest?.values[kind.headlineField], measures: measures).map { "\(field.name): \($0)" }
            } ?? kind.title,
            reason: note?.text ?? kind.summary,
            stats: []
        ) {
            if points.count >= 2 {
                SomaCard {
                    VStack(alignment: .leading, spacing: 0) {
                        LabEyebrow(field?.name ?? kind.title)
                        LabLineChart(points: points, aspect: .body, isFlagged: note?.isFlagged == true)
                    }
                }
            }
            if let latest {
                LabBandCard(title: "Latest", eyebrow: latest.note, aspect: .body,
                            items: FunctionalItems.items(latest, previous: history.dropLast().last, measures: measures, sex: sex, route: nil))
            }
            LabExplainCard(sections: FunctionalPageText.explainer(kind))
            if history.count > 1 {
                LabRowGroup(heading: "Every result", rows: history.reversed().map { result in
                    LabRow("\(result.date.labDay) \(result.date.formatted(.dateTime.year()))",
                           detail: field?.text(result.values[kind.headlineField], measures: measures))
                })
            }
            if kind == .fieldVO2 {
                SomaActionCard(
                    eyebrow: "Cardio fitness test",
                    title: "Run the test again",
                    detail: "The same test, a few weeks apart, shows the trend best.",
                    actionTitle: "Start",
                    action: { isTesting = true }
                ) {
                    SomaOrb(aspect: .heart, scale: .mini)
                }
            } else {
                SomaActionCard(
                    eyebrow: "Add a result",
                    title: latest == nil ? "Had this test?" : "Have a newer result?",
                    detail: "Import the report or type the values. You check each one before it is saved.",
                    actionTitle: "Add",
                    action: { adding = FunctionalAddRequest(kind: kind) }
                ) {
                    SomaOrb(aspect: .body, scale: .mini)
                }
            }
            LabFootnote("Informational, never a diagnosis. For a result that worries you, ask a doctor.")
        }
        .labPageTitle(Text(kind.title))
        .sheet(item: $adding) { request in AddFunctionalResultSheet(kind: request.kind) }
        .cardioFitnessTest(isPresented: $isTesting)
    }
}

/// Which test the add sheet opens on; nil lets the report decide.
struct FunctionalAddRequest: Identifiable {
    let id = UUID()
    var kind: FunctionalTestKind?
}

/// The band lines of one result.
enum FunctionalItems {
    @MainActor
    static func items(_ result: FunctionalResult, previous: FunctionalResult?, measures: MeasureSystem,
                      sex: LabSex?, route: LabRoute?) -> [LabBandItem] {
        result.kind.fields.compactMap { field -> LabBandItem? in
            guard let value = result.values[field.id] else { return nil }
            let note = FunctionalAssessment.note(field: field.id, value: value, sex: sex)
            var detail = note?.text ?? "Against your own tests"
            if let before = previous?.values[field.id], let date = previous?.date,
               let shown = field.text(before, measures: measures) {
                detail += " · \(shown) in \(date.formatted(.dateTime.month(.wide).year()))"
            }
            let (band, position) = rail(field: field.id, value: value, sex: sex)
            return LabBandItem(id: field.id, title: field.name, detail: detail, value: field.text(value, measures: measures),
                               band: band, position: position, isFlagged: note?.isFlagged == true, route: route,
                               bandWord: FunctionalAssessment.bandWord(field: field.id, value: value))
        }
    }

    /// The rail for a value a source bands, on a domain wide enough to show it.
    private static func rail(field: String, value: Double, sex: LabSex?) -> (ClosedRange<Double>?, Double?) {
        let limits: (low: Double?, high: Double?)
        switch field {
        case "tScore": limits = (-1, nil)
        case "fev1FvcRatio": limits = (FunctionalAssessment.obstructionRatio, nil)
        case "grip":
            guard let sex else { return (nil, nil) }
            limits = (sex == .male ? FunctionalAssessment.lowGripMale : FunctionalAssessment.lowGripFemale, nil)
        default: return (nil, nil)
        }
        // A T-score is signed, and `LabMath.domain` assumes a value above
        // zero: the T-score gets a fixed scale wide enough for any report.
        let domain = field == "tScore"
            ? min(-4, value - 0.5)...max(2, value + 0.5)
            : LabMath.domain(value: value, low: limits.low, high: limits.high)
        let span = max(domain.upperBound - domain.lowerBound, 0.000_1)
        func at(_ x: Double) -> Double { min(max((x - domain.lowerBound) / span, 0), 1) }
        return (at(limits.low ?? domain.lowerBound)...at(limits.high ?? domain.upperBound), at(value))
    }
}

/// The page's words, kept apart so the empty and the partial cases are testable.
enum FunctionalPageText {
    struct Care: Equatable {
        var kind: FunctionalTestKind
        var title: String
    }

    @MainActor
    static func needingCare(store: FunctionalResultStore, sex: LabSex?) -> [Care] {
        store.kinds.compactMap { kind in
            guard let result = store.latest(kind) else { return nil }
            let fields = kind.fields.filter { field in
                result.values[field.id].flatMap { FunctionalAssessment.note(field: field.id, value: $0, sex: sex) }?.needsClinician == true
            }
            return fields.isEmpty ? nil : Care(kind: kind, title: kind.title)
        }
    }

    static func headline(tests: Int, care: Int) -> String {
        guard tests > 0 else { return "No scan or test yet." }
        switch care {
        case 0: return tests == 1 ? "One test, nothing to discuss." : "\(tests) tests, nothing to discuss."
        case 1: return "One result to discuss."
        default: return "\(care) results to discuss."
        }
    }

    static func reason(tests: Int, care: [Care]) -> String {
        guard tests > 0 else {
            return "A DEXA scan, a lab VO2 max, a carotid ultrasound, a calcium score, spirometry or grip strength: add the report and each value lands here, against its band when a guideline gives one."
        }
        if care.isEmpty {
            return "Every banded value sits in its usual range. The rest read against your own earlier tests."
        }
        return "A result here is a snapshot. A clinician reads it with the rest of your history."
    }

    static func explainer(_ kind: FunctionalTestKind) -> [(heading: String, text: String)] {
        switch kind {
        case .dexa:
            [("What it means", "A low dose X-ray reads bone density as a T-score against a young adult: from -1 down to -2.5 is lower than usual, -2.5 or below is the osteoporosis range. The same scan weighs fat, lean mass and the fat around the organs."),
             ("What moves it", "Strength training, protein, vitamin D and calcium hold bone and lean mass. Visceral fat follows activity, sleep and diet.")]
        case .labVO2:
            [("What it means", "The most oxygen your body uses at full effort, measured at the mouth. A lab test is more exact than the watch's estimate, so Soma uses it for your biological age for a year."),
             ("What moves it", "Intervals and steady endurance work raise it; it drifts down with age and time off.")]
        case .carotidUltrasound:
            [("What it means", "Sound waves measure the inner wall of the neck arteries and look for plaque. Thickness has no single cut off: the report's percentile for your age says more."),
             ("What moves it", "Blood pressure, cholesterol, smoking and blood sugar over years.")]
        case .calciumScore:
            [("What it means", "A CT scan counts calcium in the heart's arteries. Zero means none was seen. From 100, guidelines favour a statin discussion with your doctor."),
             ("What moves it", "Calcium does not go away; the aim is to keep it from growing. Repeat scans are spaced years apart.")]
        case .spirometry:
            [("What it means", "How much air you can blow out in one second (FEV1) against all you can blow out (FVC). A ratio under 70% suggests the airways are narrowed and is worth a doctor's review."),
             ("What moves it", "Smoking, asthma, infections and fitness.")]
        case .fieldVO2:
            [("What it means", "An estimate of the most oxygen your body can use, from how far or how fast you walked, or how quickly your pulse settled after stepping. Expect it within about 5 mL/kg/min of a lab test. Soma keeps it apart from a lab VO2 max: your biological age goes on reading the watch's months of walks."),
             ("What moves it", "Intervals and steady endurance work raise it. Repeat the same test, at the same time of day, to compare.")]
        case .gripStrength:
            [("What it means", "Grip tracks whole body strength and, in large studies, how well people age. Under 27 kg for men or 16 kg for women is below the usual floor."),
             ("What moves it", "Any resistance training, and carrying heavy things.")]
        }
    }
}

#Preview("Tests") {
    NavigationStack {
        FunctionalResultsPage()
    }
}
