//
//  LabFixtures.swift
//  Prism
//
//  A blood panel, two urine tests, a DNA result, imaging and functional
//  tests and two stool tests for screenshots on a
//  simulator, behind the launch argument `-lab.fixture YES`. The stores then
//  keep memory only: nothing is written, and the person's own lab files are
//  never touched. Development only.
//

#if DEBUG
import Foundation

enum LabFixtures {
    /// The defaults key behind `-lab.fixture YES`.
    nonisolated static let launchKey = "lab.fixture"

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    private static func daysAgo(_ days: Double) -> Date { Date(timeIntervalSinceNow: -days * 86_400) }

    static var bloodPanels: [BloodPanel] {
        [BloodPanel(sampledAt: daysAgo(21), createdAt: daysAgo(20), markers: [
            BloodMarkerValue(key: "apoB", value: 92, enteredUnit: "mg/dL", source: .extracted),
            BloodMarkerValue(key: "ldl", value: 128, enteredUnit: "mg/dL", source: .extracted),
            BloodMarkerValue(key: "hdl", value: 58, enteredUnit: "mg/dL", source: .extracted),
            BloodMarkerValue(key: "hba1c", value: 5.3, enteredUnit: "%", source: .extracted),
            BloodMarkerValue(key: "glucose", value: 5.1, enteredUnit: "mmol/L", source: .extracted),
            BloodMarkerValue(key: "crp", value: 0.08, enteredUnit: "mg/dL", source: .extracted),
            BloodMarkerValue(key: "vitaminD", value: 24, enteredUnit: "ng/mL", source: .manual),
            BloodMarkerValue(key: "tsh", value: 1.8, enteredUnit: "mU/L", source: .extracted),
            BloodMarkerValue(key: "creatinine", value: 88, enteredUnit: "umol/L", source: .extracted),
        ])]
    }

    static var urinePanels: [UrinePanel] {
        [
            UrinePanel(sampledAt: daysAgo(60), createdAt: daysAgo(59), kind: .labReport, values: [
                UrineValue(key: "specificGravity", value: 1.018, enteredUnit: "", source: .extracted),
                UrineValue(key: "ph", value: 6.0, enteredUnit: "", source: .extracted),
                UrineValue(key: "protein", value: 0, enteredUnit: "mg/dL", source: .extracted),
                UrineValue(key: "glucose", value: 0, enteredUnit: "mg/dL", source: .extracted),
                UrineValue(key: "acr", value: 12, enteredUnit: "mg/g", source: .extracted),
                UrineValue(key: "albumin", value: 9, enteredUnit: "mg/L", source: .extracted),
                UrineValue(key: "creatinine", value: 110, enteredUnit: "mg/dL", source: .extracted),
            ]),
            UrinePanel(sampledAt: daysAgo(3), createdAt: daysAgo(3), kind: .dipstick, values: [
                UrineValue(key: "leukocytes", value: 0, enteredUnit: "Leu/µL", source: .camera),
                UrineValue(key: "nitrite", value: 0, enteredUnit: "", source: .camera),
                UrineValue(key: "urobilinogen", value: 0.2, enteredUnit: "mg/dL", source: .camera),
                UrineValue(key: "protein", value: 15, enteredUnit: "mg/dL", source: .camera),
                UrineValue(key: "ph", value: 6.5, enteredUnit: "", source: .camera),
                UrineValue(key: "blood", value: 0, enteredUnit: "Ery/µL", source: .camera),
                UrineValue(key: "specificGravity", value: 1.025, enteredUnit: "", source: .camera),
                UrineValue(key: "ketones", value: 5, enteredUnit: "mg/dL", source: .manual),
                UrineValue(key: "bilirubin", value: 0, enteredUnit: "mg/dL", source: .camera),
                UrineValue(key: "glucose", value: 0, enteredUnit: "mg/dL", source: .camera),
            ]),
        ]
    }

    static var functionalResults: [FunctionalResult] {
        [
            FunctionalResult(kind: .dexa, date: daysAgo(400), values: ["tScore": -0.9, "bodyFat": 26.1, "leanMass": 55.8, "visceralFat": 0.92]),
            FunctionalResult(kind: .dexa, date: daysAgo(35), values: ["tScore": -1.3, "boneDensity": 0.861, "bodyFat": 23.4,
                                                                      "fatMass": 17.9, "leanMass": 57.2, "visceralFat": 0.71]),
            FunctionalResult(kind: .labVO2, date: daysAgo(70), values: ["vo2Max": 46.2, "peakHeartRate": 182]),
            FunctionalResult(kind: .calciumScore, date: daysAgo(120), values: ["agatston": 0]),
            FunctionalResult(kind: .gripStrength, date: daysAgo(210), values: ["grip": 41.5]),
            FunctionalResult(kind: .gripStrength, date: daysAgo(12), values: ["grip": 44.0], note: "Dominant hand"),
        ]
    }

    static var stoolPanels: [StoolPanel] {
        [
            StoolPanel(sampledAt: daysAgo(150), createdAt: daysAgo(140), kind: .microbiomeKit, values: [
                StoolValue(key: "shannon", value: 3.4, enteredUnit: "", source: .extracted),
                StoolValue(key: "akkermansia", value: 1.1, enteredUnit: "%", source: .extracted),
                StoolValue(key: "faecalibacterium", value: 6.2, enteredUnit: "%", source: .extracted),
            ]),
            StoolPanel(sampledAt: daysAgo(8), createdAt: daysAgo(6), kind: .labReport, values: [
                StoolValue(key: "calprotectin", value: 84, enteredUnit: "µg/g", source: .extracted),
                StoolValue(key: "fit", value: 0, enteredUnit: "", source: .extracted),
                StoolValue(key: "elastase", value: 410, enteredUnit: "µg/g", source: .extracted),
                StoolValue(key: "hPylori", value: 0, enteredUnit: "", source: .extracted),
                StoolValue(key: "shannon", value: 3.9, enteredUnit: "", source: .extracted),
                StoolValue(key: "akkermansia", value: 2.4, enteredUnit: "%", source: .extracted),
                StoolValue(key: "faecalibacterium", value: 7.9, enteredUnit: "%", source: .extracted),
                StoolValue(key: "bifidobacterium", value: 0.8, enteredUnit: "%", source: .extracted),
                StoolValue(key: "firmicutesBacteroidetes", value: 1.6, enteredUnit: "", source: .extracted),
            ]),
        ]
    }

    static var genome: GenomeResult {
        GenomeResult(importedAt: daysAgo(10), parse: GenomeParse(
            provider: .twentyThreeAndMe, build: "GRCh37", snpsRead: 631_442, noCalls: 4_107,
            genotypes: ["rs762551": "AC", "rs4988235": "AG", "rs1801133": "AG", "rs1815739": "CT",
                        "rs9939609": "AT", "rs429358": "TT", "rs7412": "CC"]))
    }
}
#endif
