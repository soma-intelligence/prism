//
//  UrineCatalog.swift
//  Prism
//
//  Every urine marker Soma knows: the ten pads of a standard urinalysis
//  dipstick (specific gravity, pH, protein, glucose, ketones, blood,
//  bilirubin, urobilinogen, nitrite, leukocyte esterase) and the three a lab
//  report adds for the kidneys (albumin, the albumin to creatinine ratio and
//  creatinine).
//
//  Each marker names its storage unit, the units accepted on entry with the
//  factor into storage, an indicative adult range (a badge, never a
//  diagnosis), the aliases a printed report uses, and, for a pad, the steps
//  of the strip's colour chart.
//
//  Sources for the ranges:
//  Simerville JA, Maxted WC, Pahira JJ. Urinalysis: a comprehensive review.
//  Am Fam Physician 2005;71(6):1153-62 (specific gravity, pH, and a negative
//  pad for protein, glucose, ketones, blood, bilirubin, nitrite and
//  leukocyte esterase; urobilinogen 0.2 to 1 mg/dL).
//  KDIGO 2012 Clinical Practice Guideline for CKD, Kidney Int Suppl 2013;3:1-150
//  (albumin to creatinine ratio under 30 mg/g, category A1; 3 mg/mmol).
//  ADA Standards of Care 2025, section 11 (albumin under 30 mg/L on a spot
//  sample as the screening cut point).
//  Mayo Clinic Laboratories, test RANDU (random urine creatinine, adult
//  indicative 20 to 320 mg/dL).
//
//  The dipstick steps follow the common ten pad charts (URS-10, Multistix 10
//  SG). Their colours are a generic approximation of those charts in sRGB:
//  brands differ, so a camera reading is always marked approximate and the
//  person checks every pad against the chart on their own bottle.
//

import Foundation

/// One step of a pad's colour chart: what it is called, the value it
/// stands for in the marker's storage unit, and its chart colour.
nonisolated struct UrineDipstickStep: Sendable, Hashable {
    var label: String
    var value: Double
    /// sRGB, 0 to 255.
    var red: Double
    var green: Double
    var blue: Double

    init(_ label: String, _ value: Double, _ red: Double, _ green: Double, _ blue: Double) {
        self.label = label
        self.value = value
        self.red = red
        self.green = green
        self.blue = blue
    }

    var rgb: UrineRGB { UrineRGB(red: red / 255, green: green / 255, blue: blue / 255) }
}

nonisolated enum UrineMarkerGroup: String, CaseIterable, Sendable {
    case kidney, sugar, liver, infection

    var title: String {
        switch self {
        case .kidney: "Kidneys and hydration"
        case .sugar: "Sugar, ketones and acidity"
        case .liver: "Liver and bile"
        case .infection: "Signs of infection"
        }
    }
}

nonisolated struct UrineMarker: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let group: UrineMarkerGroup
    /// The unit stored values are in, also the one shown. Empty for a
    /// marker that has no unit (pH, specific gravity, nitrite).
    let unit: String
    /// Normalised unit to the factor into `unit`.
    let acceptedUnits: [String: Double]
    let refLow: Double?
    let refHigh: Double?
    /// The usual result in words: "Negative", "1.005 to 1.030".
    let usual: String
    let aliases: [String]
    /// The chart, low to high, for a dipstick pad. Empty for a lab only marker.
    let steps: [UrineDipstickStep]
    /// When to read the pad after dipping, in seconds, from the URS-10 leaflet.
    let readAfter: Int?

    static func == (a: UrineMarker, b: UrineMarker) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var isPad: Bool { !steps.isEmpty }

    func toStorage(_ value: Double, from unit: String) -> Double? {
        if acceptedUnits.isEmpty { return value }
        guard let factor = acceptedUnits[BloodMarkerCatalog.normalize(unit)] else { return nil }
        return value * factor
    }

    func accepts(_ unit: String) -> Bool {
        acceptedUnits.isEmpty || acceptedUnits[BloodMarkerCatalog.normalize(unit)] != nil
    }

    func status(forStorage value: Double) -> BloodMarker.RangeStatus {
        if let lo = refLow, value < lo { return .low }
        if let hi = refHigh, value > hi { return .high }
        if refLow == nil && refHigh == nil { return .unknown }
        return .normal
    }

    /// The chart step nearest a stored value, for showing "Trace" rather
    /// than "15 mg/dL".
    func nearestStep(to value: Double) -> UrineDipstickStep? {
        steps.min { abs($0.value - value) < abs($1.value - value) }
    }
}

nonisolated enum UrineCatalog {
    /// The ten pads in the order they sit on a URS-10 strip, from the handle
    /// to the tip. Some brands run the other way; the reader offers a flip.
    static let padOrder = ["leukocytes", "nitrite", "urobilinogen", "protein", "ph",
                           "blood", "specificGravity", "ketones", "bilirubin", "glucose"]

    static let all: [UrineMarker] = [
        UrineMarker(id: "specificGravity", name: "Specific gravity", group: .kidney,
                    unit: "", acceptedUnits: [:], refLow: 1.005, refHigh: 1.030, usual: "1.005 to 1.030",
                    aliases: ["specific gravity", "sg", "densite", "densite urinaire", "density"],
                    steps: [
                        .init("1.000", 1.000, 20, 90, 110), .init("1.005", 1.005, 45, 110, 105),
                        .init("1.010", 1.010, 75, 125, 95), .init("1.015", 1.015, 105, 140, 85),
                        .init("1.020", 1.020, 135, 150, 70), .init("1.025", 1.025, 160, 160, 60),
                        .init("1.030", 1.030, 180, 165, 50),
                    ], readAfter: 45),
        UrineMarker(id: "ph", name: "pH", group: .sugar,
                    unit: "", acceptedUnits: [:], refLow: 4.5, refHigh: 8.0, usual: "4.5 to 8",
                    aliases: ["ph", "ph urinaire"],
                    steps: [
                        .init("5.0", 5.0, 240, 140, 60), .init("6.0", 6.0, 235, 175, 60),
                        .init("6.5", 6.5, 215, 190, 70), .init("7.0", 7.0, 175, 190, 80),
                        .init("7.5", 7.5, 130, 175, 95), .init("8.0", 8.0, 85, 150, 120),
                        .init("8.5", 8.5, 40, 115, 140),
                    ], readAfter: 60),
        UrineMarker(id: "protein", name: "Protein", group: .kidney,
                    unit: "mg/dL", acceptedUnits: ["mg/dl": 1, "g/l": 100, "mg/l": 0.1], refLow: nil, refHigh: 14,
                    usual: "Negative",
                    aliases: ["protein", "proteins", "proteine", "proteines", "proteinurie", "total protein", "pro"],
                    steps: [
                        .init("Negative", 0, 232, 236, 140), .init("Trace", 15, 212, 226, 140),
                        .init("1+ (30)", 30, 185, 214, 140), .init("2+ (100)", 100, 150, 196, 145),
                        .init("3+ (300)", 300, 115, 175, 150), .init("4+ (2000)", 2000, 80, 150, 145),
                    ], readAfter: 60),
        UrineMarker(id: "glucose", name: "Glucose", group: .sugar,
                    unit: "mg/dL", acceptedUnits: ["mg/dl": 1, "mmol/l": 18.016, "g/l": 100], refLow: nil, refHigh: 15,
                    usual: "Negative",
                    aliases: ["glucose", "glycosurie", "glucose urinaire", "glu"],
                    steps: [
                        .init("Negative", 0, 130, 200, 200), .init("100", 100, 130, 190, 150),
                        .init("250", 250, 140, 175, 110), .init("500", 500, 150, 150, 80),
                        .init("1000", 1000, 145, 120, 70), .init("2000", 2000, 125, 90, 60),
                    ], readAfter: 30),
        UrineMarker(id: "ketones", name: "Ketones", group: .sugar,
                    unit: "mg/dL", acceptedUnits: ["mg/dl": 1, "mmol/l": 10.3], refLow: nil, refHigh: 0,
                    usual: "Negative",
                    aliases: ["ketones", "ketone", "cetones", "corps cetoniques", "acetone", "ket"],
                    steps: [
                        .init("Negative", 0, 240, 205, 175), .init("Trace (5)", 5, 235, 180, 170),
                        .init("Small (15)", 15, 215, 145, 150), .init("Moderate (40)", 40, 190, 105, 125),
                        .init("Large (80)", 80, 150, 70, 105), .init("Large (160)", 160, 110, 45, 85),
                    ], readAfter: 40),
        UrineMarker(id: "blood", name: "Blood", group: .kidney,
                    unit: "Ery/µL", acceptedUnits: ["ery/ul": 1, "rbc/ul": 1, "/ul": 1], refLow: nil, refHigh: 0,
                    usual: "Negative",
                    aliases: ["blood", "hemoglobin", "haemoglobin", "hemoglobine", "sang", "hematies", "occult blood", "bld"],
                    steps: [
                        .init("Negative", 0, 238, 200, 80), .init("Trace (10)", 10, 210, 200, 80),
                        .init("Small (25)", 25, 165, 180, 80), .init("Moderate (80)", 80, 110, 150, 75),
                        .init("Large (200)", 200, 55, 110, 70),
                    ], readAfter: 60),
        UrineMarker(id: "bilirubin", name: "Bilirubin", group: .liver,
                    unit: "mg/dL", acceptedUnits: ["mg/dl": 1, "umol/l": 1 / 17.1], refLow: nil, refHigh: 0,
                    usual: "Negative",
                    aliases: ["bilirubin", "bilirubine", "bil"],
                    steps: [
                        .init("Negative", 0, 245, 238, 210), .init("Small (1)", 1, 232, 215, 185),
                        .init("Moderate (3)", 3, 215, 190, 165), .init("Large (6)", 6, 195, 165, 145),
                    ], readAfter: 30),
        UrineMarker(id: "urobilinogen", name: "Urobilinogen", group: .liver,
                    unit: "mg/dL", acceptedUnits: ["mg/dl": 1, "eu/dl": 1, "umol/l": 1 / 16.9], refLow: nil, refHigh: 1,
                    usual: "0.2 to 1 mg/dL",
                    aliases: ["urobilinogen", "urobilinogene", "ubg", "uro"],
                    steps: [
                        .init("0.2", 0.2, 250, 220, 190), .init("1", 1, 246, 200, 175),
                        .init("2", 2, 240, 175, 160), .init("4", 4, 230, 150, 145),
                        .init("8", 8, 220, 125, 130),
                    ], readAfter: 60),
        UrineMarker(id: "nitrite", name: "Nitrite", group: .infection,
                    unit: "", acceptedUnits: [:], refLow: nil, refHigh: 0, usual: "Negative",
                    aliases: ["nitrite", "nitrites", "nit"],
                    steps: [
                        .init("Negative", 0, 250, 244, 225), .init("Positive", 1, 240, 190, 200),
                    ], readAfter: 60),
        UrineMarker(id: "leukocytes", name: "Leukocyte esterase", group: .infection,
                    unit: "Leu/µL", acceptedUnits: ["leu/ul": 1, "wbc/ul": 1, "/ul": 1], refLow: nil, refHigh: 0,
                    usual: "Negative",
                    aliases: ["leukocyte esterase", "leukocytes", "leucocytes", "leucocyte esterase", "white cells", "leu"],
                    steps: [
                        .init("Negative", 0, 238, 232, 196), .init("Trace (15)", 15, 222, 206, 190),
                        .init("Small (70)", 70, 196, 168, 186), .init("Moderate (125)", 125, 165, 128, 170),
                        .init("Large (500)", 500, 130, 92, 150),
                    ], readAfter: 120),
        UrineMarker(id: "albumin", name: "Albumin (microalbumin)", group: .kidney,
                    unit: "mg/L", acceptedUnits: ["mg/l": 1, "mg/dl": 10, "ug/ml": 1], refLow: nil, refHigh: 30,
                    usual: "Under 30 mg/L",
                    aliases: ["microalbumin", "microalbuminuria", "urine albumin", "albumin", "albumine", "microalbuminurie"],
                    steps: [], readAfter: nil),
        UrineMarker(id: "acr", name: "Albumin to creatinine ratio", group: .kidney,
                    unit: "mg/g", acceptedUnits: ["mg/g": 1, "mg/mmol": 8.84, "ug/mg": 1], refLow: nil, refHigh: 30,
                    usual: "Under 30 mg/g",
                    aliases: ["albumin creatinine ratio", "albumin to creatinine ratio", "albumin creatinine", "acr", "uacr",
                              "rapport albumine creatinine", "rac", "racu"],
                    steps: [], readAfter: nil),
        UrineMarker(id: "creatinine", name: "Creatinine", group: .kidney,
                    unit: "mg/dL", acceptedUnits: ["mg/dl": 1, "mmol/l": 11.31, "umol/l": 0.01131, "g/l": 100],
                    refLow: 20, refHigh: 320, usual: "20 to 320 mg/dL",
                    aliases: ["creatinine", "urine creatinine", "creatinine urinaire", "creatininurie"],
                    steps: [], readAfter: nil),
    ]

    static let byID: [String: UrineMarker] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func marker(id: String) -> UrineMarker? { byID[id] }

    static var pads: [UrineMarker] { padOrder.compactMap { byID[$0] } }
}
