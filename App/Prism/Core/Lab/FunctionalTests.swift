//
//  FunctionalTests.swift
//  Prism
//
//  Imaging and functional tests a person brings back from a clinic: a DEXA
//  scan, a VO2 max measured in a lab, a carotid ultrasound, a coronary
//  calcium score, spirometry and grip strength. Each test names the values
//  its report prints, the unit each is stored in, the units accepted on
//  entry with the factor into storage, and the labels a report uses.
//
//  A mass is always stored in kilograms and shown in the person's measures
//  (Settings, Language and units). A value that was not measured is absent,
//  and shown as a dash.
//
//  The bands below are informational, never a diagnosis; a result that
//  needs care points to a clinician. Sources:
//  Calcium score: Grundy SM et al. 2018 AHA/ACC Guideline on the Management
//  of Blood Cholesterol, Circulation 2019;139:e1082-e1143 (CAC 0, 1 to 99,
//  100 to 399, 400 and over; from 100 a statin is favoured).
//  T-score: WHO Technical Report Series 843, 1994 (normal at -1 or above,
//  osteopenia between -1 and -2.5, osteoporosis at -2.5 or below).
//  FEV1/FVC: GOLD 2024 report (a ratio under 0.70 after a bronchodilator
//  confirms airflow limitation).
//  Grip strength: Cruz-Jentoft AJ et al. EWGSOP2, Age Ageing 2019;48:16-31
//  (low under 27 kg for men, under 16 kg for women).
//  Carotid plaque: Stein JH et al. ASE consensus statement, J Am Soc
//  Echocardiogr 2008;21:93-111 (plaque present, or a thickness at or above
//  the 75th percentile for age, sex and race, reads as higher risk; there is
//  no absolute thickness band, so the page compares a person with their own
//  scans and with the report's percentile).
//

import Foundation
import Observation

/// The six tests the Lab keeps, and the cardio fitness test run in the app.
///
/// `fieldVO2` is the app's own walk or step test (``CardioFitnessTest``): an
/// estimate from a submaximal field test, kept apart from `labVO2` so the
/// biological age's rule (a lab VO2 max under a year old replaces the
/// watch's estimate) never treats a field estimate as a measurement. Its
/// standard error, about 5 mL/kg/min, is no smaller than the watch's, and
/// the watch averages months of walks where the test is one afternoon. A
/// field test saved to Health joins the watch's series there instead.
nonisolated enum FunctionalTestKind: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case dexa, labVO2, carotidUltrasound, calciumScore, spirometry, gripStrength, fieldVO2

    var id: String { rawValue }

    /// The tests a clinic's report brings back, which the report reader and
    /// the add sheet offer. The field test is run in the app, never typed.
    static var reported: [FunctionalTestKind] { allCases.filter { $0 != .fieldVO2 } }

    var title: String {
        switch self {
        case .dexa: "DEXA scan"
        case .labVO2: "VO2 max, lab test"
        case .carotidUltrasound: "Carotid ultrasound"
        case .calciumScore: "Calcium score"
        case .spirometry: "Spirometry"
        case .gripStrength: "Grip strength"
        case .fieldVO2: "VO2 max, field test"
        }
    }

    var symbol: String {
        switch self {
        case .dexa: "figure.stand"
        case .labVO2: "lungs.fill"
        case .carotidUltrasound: "waveform.path.ecg"
        case .calciumScore: "heart.circle"
        case .spirometry: "wind"
        case .gripStrength: "hand.raised.fill"
        case .fieldVO2: "figure.walk.motion"
        }
    }

    /// What the test measures, in a line.
    var summary: String {
        switch self {
        case .dexa: "Bone density, body fat, lean and visceral mass."
        case .labVO2: "The most oxygen you use at full effort, on a treadmill or a bike with a mask."
        case .carotidUltrasound: "The neck arteries' wall thickness, and any plaque."
        case .calciumScore: "Calcium in the heart's arteries, from a CT scan."
        case .spirometry: "How much air you blow out, and how fast."
        case .gripStrength: "Your strongest squeeze on a dynamometer."
        case .fieldVO2: "An estimate from a timed walk or step test run in Soma."
        }
    }

    var fields: [FunctionalField] { FunctionalCatalog.fields(self) }

    /// The value the card leads with.
    var headlineField: String {
        switch self {
        case .dexa: "bodyFat"
        case .labVO2: "vo2Max"
        case .carotidUltrasound: "cimt"
        case .calciumScore: "agatston"
        case .spirometry: "fev1FvcRatio"
        case .gripStrength: "grip"
        case .fieldVO2: "vo2Max"
        }
    }
}

/// One value a test's report prints.
nonisolated struct FunctionalField: Identifiable, Sendable, Hashable {
    enum Quantity: Sendable, Hashable {
        /// Kilograms in storage, shown in the person's measures.
        case mass
        case plain
        /// Present (1) or absent (0).
        case yesNo
    }

    let id: String
    let name: String
    /// The storage unit, also the one shown for anything but a mass. Empty
    /// for a value without one.
    let unit: String
    let quantity: Quantity
    /// Normalised unit to the factor into `unit`. Empty accepts a bare number.
    let acceptedUnits: [String: Double]
    let aliases: [String]
    let decimals: Int
    /// A ratio a report may print as 0.72 or as 72 %: stored as a percent.
    var percentFromFraction = false

    static func == (a: FunctionalField, b: FunctionalField) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func toStorage(_ value: Double, from unit: String) -> Double? {
        let key = BloodMarkerCatalog.normalize(unit)
        if percentFromFraction, value <= 1.5, key.isEmpty || key == "%" { return value * 100 }
        // A bare number is already in the storage unit.
        if acceptedUnits.isEmpty || key.isEmpty { return value }
        guard let factor = acceptedUnits[key] else { return nil }
        return value * factor
    }

    func accepts(_ unit: String) -> Bool {
        let key = BloodMarkerCatalog.normalize(unit)
        return acceptedUnits.isEmpty || key.isEmpty || acceptedUnits[key] != nil
    }

    /// The unit a person reads the value in.
    func displayUnit(_ measures: MeasureSystem) -> String {
        quantity == .mass ? (measures == .imperial ? "lb" : "kg") : unit
    }

    /// "45.4 kg", "100.0 lb", "-1.8", "Present"; a dash when nothing was measured.
    func text(_ storage: Double?, measures: MeasureSystem) -> String {
        guard let storage else { return "-" }
        switch quantity {
        case .yesNo:
            return storage >= 0.5 ? "Present" : "None seen"
        case .mass:
            let shown = measures == .imperial ? storage * TrackMassUnit.poundsPerKilogram : storage
            let number = String(format: "%.1f", shown)
            return "\(number) \(displayUnit(measures))"
        case .plain:
            let number = LabMath.format(storage, decimals: decimals, locale: Locale(identifier: "en_US_POSIX")) ?? "-"
            if unit.isEmpty { return number }
            return unit == "%" ? "\(number)%" : "\(number) \(unit)"
        }
    }
}

nonisolated enum FunctionalCatalog {
    private static let kilograms: [String: Double] = ["kg": 1, "g": 0.001, "lb": 0.453_592_37, "lbs": 0.453_592_37]
    private static let litres: [String: Double] = ["l": 1, "ml": 0.001]
    private static let percent: [String: Double] = ["%": 1]

    static func fields(_ kind: FunctionalTestKind) -> [FunctionalField] {
        switch kind {
        case .dexa:
            [
                FunctionalField(id: "tScore", name: "T-score", unit: "", quantity: .plain, acceptedUnits: [:],
                                aliases: ["t score", "tscore", "femoral neck t score", "total hip t score", "lumbar spine t score", "spine t score"],
                                decimals: 1),
                FunctionalField(id: "boneDensity", name: "Bone density", unit: "g/cm²", quantity: .plain,
                                acceptedUnits: ["g/cm2": 1, "g/cm²": 1, "g/cm^2": 1],
                                aliases: ["bmd", "bone mineral density", "bone density"], decimals: 3),
                FunctionalField(id: "bodyFat", name: "Body fat", unit: "%", quantity: .plain, acceptedUnits: percent,
                                aliases: ["body fat", "total body fat", "body fat percentage", "fat percent", "total fat percent", "masse grasse %"],
                                decimals: 1),
                FunctionalField(id: "fatMass", name: "Fat mass", unit: "kg", quantity: .mass, acceptedUnits: kilograms,
                                aliases: ["fat mass", "total fat mass"], decimals: 1),
                FunctionalField(id: "leanMass", name: "Lean mass", unit: "kg", quantity: .mass, acceptedUnits: kilograms,
                                aliases: ["lean mass", "total lean mass", "lean body mass", "lean tissue", "masse maigre"], decimals: 1),
                FunctionalField(id: "visceralFat", name: "Visceral fat", unit: "kg", quantity: .mass, acceptedUnits: kilograms,
                                aliases: ["visceral fat", "visceral fat mass", "vat mass", "visceral adipose tissue", "graisse viscerale"],
                                decimals: 2),
            ]
        case .labVO2:
            [
                FunctionalField(id: "vo2Max", name: "VO2 max", unit: "mL/kg/min", quantity: .plain,
                                acceptedUnits: ["ml/kg/min": 1, "ml/min/kg": 1, "ml.kg 1.min 1": 1],
                                aliases: ["vo2 max", "vo2max", "vo2 peak", "vo2peak", "peak vo2", "maximal oxygen uptake", "vo₂ max"],
                                decimals: 1),
                FunctionalField(id: "peakHeartRate", name: "Peak heart rate", unit: "bpm", quantity: .plain,
                                acceptedUnits: ["bpm": 1, "/min": 1, "beats/min": 1],
                                aliases: ["peak heart rate", "max heart rate", "maximum heart rate", "hr max", "fc max"], decimals: 0),
            ]
        case .carotidUltrasound:
            [
                FunctionalField(id: "cimt", name: "Wall thickness (CIMT)", unit: "mm", quantity: .plain,
                                acceptedUnits: ["mm": 1, "cm": 10, "um": 0.001],
                                aliases: ["cimt", "imt", "intima media thickness", "carotid intima media thickness", "mean imt", "mean cimt"],
                                decimals: 2),
                FunctionalField(id: "cimtPercentile", name: "Thickness percentile", unit: "%", quantity: .plain, acceptedUnits: percent,
                                aliases: ["imt percentile", "cimt percentile"], decimals: 0),
                FunctionalField(id: "plaque", name: "Plaque", unit: "", quantity: .yesNo, acceptedUnits: [:],
                                aliases: ["plaque", "plaques", "carotid plaque"], decimals: 0),
            ]
        case .calciumScore:
            [
                FunctionalField(id: "agatston", name: "Agatston score", unit: "", quantity: .plain, acceptedUnits: [:],
                                aliases: ["agatston", "agatston score", "total agatston score", "calcium score", "total calcium score",
                                          "cac score", "cac", "coronary artery calcium", "score calcique"],
                                decimals: 0),
                FunctionalField(id: "percentile", name: "Percentile for age and sex", unit: "%", quantity: .plain, acceptedUnits: percent,
                                aliases: ["percentile", "mesa percentile"], decimals: 0),
            ]
        case .spirometry:
            [
                FunctionalField(id: "fev1", name: "FEV1", unit: "L", quantity: .plain, acceptedUnits: litres,
                                aliases: ["fev1", "fev 1", "vems"], decimals: 2),
                FunctionalField(id: "fvc", name: "FVC", unit: "L", quantity: .plain, acceptedUnits: litres,
                                aliases: ["fvc", "cvf"], decimals: 2),
                FunctionalField(id: "fev1FvcRatio", name: "FEV1/FVC", unit: "%", quantity: .plain, acceptedUnits: percent,
                                aliases: ["fev1 fvc", "fev1 fvc ratio", "tiffeneau", "vems cvf"], decimals: 0, percentFromFraction: true),
                FunctionalField(id: "fev1Predicted", name: "FEV1, % of predicted", unit: "%", quantity: .plain, acceptedUnits: percent,
                                aliases: ["fev1 % predicted", "fev1 % pred", "fev1 percent predicted", "fev1 %pred"], decimals: 0),
            ]
        case .fieldVO2:
            [
                FunctionalField(id: "vo2Max", name: "VO2 max", unit: "mL/kg/min", quantity: .plain,
                                acceptedUnits: ["ml/kg/min": 1], aliases: [], decimals: 1),
                FunctionalField(id: "distance", name: "Distance", unit: "m", quantity: .plain,
                                acceptedUnits: ["m": 1], aliases: [], decimals: 0),
                FunctionalField(id: "duration", name: "Time", unit: "min", quantity: .plain,
                                acceptedUnits: ["min": 1], aliases: [], decimals: 1),
                FunctionalField(id: "heartRate", name: "Heart rate read", unit: "bpm", quantity: .plain,
                                acceptedUnits: ["bpm": 1], aliases: [], decimals: 0),
            ]
        case .gripStrength:
            [
                FunctionalField(id: "grip", name: "Grip strength", unit: "kg", quantity: .mass,
                                acceptedUnits: ["kg": 1, "lb": 0.453_592_37, "lbs": 0.453_592_37],
                                aliases: ["grip", "grip strength", "handgrip", "hand grip", "dynamometer", "force de prehension"],
                                decimals: 1),
            ]
        }
    }

    static func field(_ id: String, in kind: FunctionalTestKind) -> FunctionalField? {
        fields(kind).first { $0.id == id }
    }
}

// MARK: - A saved result

/// One test, confirmed by the person: the values in storage units, by field id.
nonisolated struct FunctionalResult: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var kind: FunctionalTestKind
    var date: Date
    var values: [String: Double]
    var note: String?

    init(id: UUID = UUID(), kind: FunctionalTestKind, date: Date, values: [String: Double], note: String? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.values = values
        self.note = note
    }

    /// The screening this result counts as done on the ledger, when it is one.
    /// A DEXA counts for bone density only when it carries a T-score: a body
    /// composition scan alone says nothing about bone.
    var screeningRecord: SomaTools.ScreeningDone? {
        switch kind {
        case .calciumScore where values["agatston"] != nil:
            SomaTools.ScreeningDone(id: id, itemID: "calciumScore", performedOn: date, note: "From the Lab")
        case .dexa where values["tScore"] != nil:
            SomaTools.ScreeningDone(id: id, itemID: "osteoporosis", performedOn: date, note: "From the Lab")
        default:
            nil
        }
    }
}

// MARK: - Bands

/// The AHA/ACC 2018 calcium score categories.
nonisolated enum CalciumCategory: String, Sendable {
    case none, mild, moderate, severe

    var title: String {
        switch self {
        case .none: "No calcium seen"
        case .mild: "Mild, 1 to 99"
        case .moderate: "Moderate, 100 to 399"
        case .severe: "Extensive, 400 or more"
        }
    }
}

nonisolated enum CalciumScore {
    static func category(agatston: Double) -> CalciumCategory {
        switch agatston {
        case ..<1: .none
        case ..<100: .mild
        case ..<400: .moderate
        default: .severe
        }
    }
}

/// The WHO's bone density bands.
nonisolated enum BoneDensityBand: String, Sendable {
    case normal, osteopenia, osteoporosis

    static func band(tScore: Double) -> BoneDensityBand {
        if tScore <= -2.5 { return .osteoporosis }
        if tScore < -1 { return .osteopenia }
        return .normal
    }

    var title: String {
        switch self {
        case .normal: "Usual range"
        case .osteopenia: "Lower than usual (osteopenia range)"
        case .osteoporosis: "In the osteoporosis range"
        }
    }
}

/// A DEXA result read by its fields.
nonisolated struct DexaResult: Sendable, Equatable {
    var tScore: Double?
    var boneDensity: Double?
    var bodyFatPercent: Double?
    var fatMassKg: Double?
    var leanMassKg: Double?
    var visceralFatKg: Double?

    init(_ result: FunctionalResult) {
        tScore = result.values["tScore"]
        boneDensity = result.values["boneDensity"]
        bodyFatPercent = result.values["bodyFat"]
        fatMassKg = result.values["fatMass"]
        leanMassKg = result.values["leanMass"]
        visceralFatKg = result.values["visceralFat"]
    }

    var boneBand: BoneDensityBand? { tScore.map(BoneDensityBand.band) }
}

/// What a value says, in a few words, when a source gives it a band.
nonisolated struct FunctionalNote: Sendable, Equatable {
    var text: String
    var isFlagged: Bool
    /// A result worth a word with a clinician.
    var needsClinician: Bool
}

nonisolated enum FunctionalAssessment {
    /// FEV1/FVC under 70%: GOLD 2024.
    static let obstructionRatio = 70.0
    /// EWGSOP2 low grip, in kilograms.
    static let lowGripMale = 27.0
    static let lowGripFemale = 16.0

    /// Nil for a value no source bands (VO2 max, masses, thickness): those
    /// read against the person's own earlier tests.
    /// The band's own short name, for the word beside the value on a band
    /// line: Osteopenia range rather than Below normal. Nil when the field
    /// has no named band, or the value sits in the usual one.
    static func bandWord(field: String, value: Double) -> String? {
        switch field {
        case "tScore":
            switch BoneDensityBand.band(tScore: value) {
            case .normal: nil
            case .osteopenia: String(localized: "Osteopenia range")
            case .osteoporosis: String(localized: "Osteoporosis range")
            }
        case "agatston":
            switch CalciumScore.category(agatston: value) {
            case .none, .mild: nil
            case .moderate: String(localized: "Moderate calcium")
            case .severe: String(localized: "Extensive calcium")
            }
        default: nil
        }
    }

    static func note(field: String, value: Double, sex: LabSex?) -> FunctionalNote? {
        switch field {
        case "tScore":
            let band = BoneDensityBand.band(tScore: value)
            return FunctionalNote(text: band.title, isFlagged: band != .normal, needsClinician: band == .osteoporosis)
        case "agatston":
            let category = CalciumScore.category(agatston: value)
            return FunctionalNote(text: category.title, isFlagged: category == .moderate || category == .severe,
                                  needsClinician: category == .moderate || category == .severe)
        case "fev1FvcRatio":
            let low = value < obstructionRatio
            return FunctionalNote(text: low ? "Under 70%, worth a look" : "70% or more, the usual range",
                                  isFlagged: low, needsClinician: low)
        case "grip":
            guard let sex else { return nil }
            let cut = sex == .male ? lowGripMale : lowGripFemale
            let low = value < cut
            return FunctionalNote(text: low ? "Below the usual floor for strength" : "Above the usual floor",
                                  isFlagged: low, needsClinician: false)
        case "plaque":
            let present = value >= 0.5
            return FunctionalNote(text: present ? "Plaque reported" : "No plaque reported",
                                  isFlagged: present, needsClinician: present)
        default:
            return nil
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class FunctionalResultStore {
    static let shared: FunctionalResultStore = {
        #if DEBUG
        if LabFixtures.isOn {
            let store = FunctionalResultStore(url: nil)
            LabFixtures.functionalResults.forEach(store.save)
            return store
        }
        #endif
        return FunctionalResultStore(url: LabFiles.url("functional-results.json"))
    }()

    /// Newest first.
    private(set) var results: [FunctionalResult]
    private let url: URL?

    init(url: URL?) {
        self.url = url
        results = (LabFiles.load([FunctionalResult].self, from: url) ?? []).sorted { $0.date > $1.date }
    }

    var latest: FunctionalResult? { results.first }

    func latest(_ kind: FunctionalTestKind) -> FunctionalResult? { results.first { $0.kind == kind } }

    /// Every result of one test, oldest first.
    func history(_ kind: FunctionalTestKind) -> [FunctionalResult] {
        results.filter { $0.kind == kind }.reversed()
    }

    /// The tests with at least one result, in the catalog's order.
    var kinds: [FunctionalTestKind] {
        FunctionalTestKind.allCases.filter { kind in results.contains { $0.kind == kind } }
    }

    func save(_ result: FunctionalResult) {
        results.removeAll { $0.id == result.id }
        results.append(result)
        results.sort { $0.date > $1.date }
        LabFiles.save(results, to: url)
    }

    func delete(_ result: FunctionalResult) {
        results.removeAll { $0.id == result.id }
        LabFiles.save(results, to: url)
    }

    /// The latest lab VO2 max, for the biological age. It decides itself
    /// whether the test is recent enough to win over the watch.
    var labVO2: BiologicalAge.LabVO2? {
        guard let result = latest(.labVO2), let value = result.values["vo2Max"] else { return nil }
        return BiologicalAge.LabVO2(value: value, date: result.date)
    }

    /// The screenings these results stand for, folded into the ledger as it
    /// is read, never written to it.
    var screeningRecords: [SomaTools.ScreeningDone] { results.compactMap(\.screeningRecord) }
}
