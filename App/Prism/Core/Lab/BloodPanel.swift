//
//  BloodPanel.swift
//  Prism
//
//  The nine PhenoAge markers and the stored shape of a blood panel.
//  Values are normalised into each marker's storage unit when the
//  panel is saved, so the arithmetic never branches on units; the unit the
//  person or the lab printed is kept beside it for display.
//

import Foundation

/// Who a sex specific equation is computed for. PhenoAge's imputation,
/// CKD-EPI and PREVENT each carry a female and a male coefficient set and
/// nothing else, so an unknown sex is a missing input, never a guess.
nonisolated enum LabSex: String, Codable, Sendable, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
}

/// The nine markers of Levine's PhenoAge (2018), with the unit each
/// coefficient expects, the lab units accepted and their factors, the
/// population medians used to impute a missing one, and a wide plausibility
/// range that only badges an obviously misread value.
nonisolated enum BloodMarkerKey: String, CaseIterable, Codable, Sendable {
    case albumin
    case creatinine
    case glucose
    case crp
    case lymphocytePercent
    case mcv
    case rdw
    case alp
    case wbc

    var displayName: String {
        switch self {
        case .albumin: "Albumin"
        case .creatinine: "Creatinine"
        case .glucose: "Fasting glucose"
        case .crp: "hs-CRP"
        case .lymphocytePercent: "Lymphocytes"
        case .mcv: "Mean cell volume"
        case .rdw: "Red cell width"
        case .alp: "Alkaline phosphatase"
        case .wbc: "White cells"
        }
    }

    /// The unit Levine's coefficient expects. Stored values are in it.
    var levineUnit: String {
        switch self {
        case .albumin: "g/L"
        case .creatinine: "µmol/L"
        case .glucose: "mmol/L"
        case .crp: "mg/dL"
        case .lymphocytePercent: "%"
        case .mcv: "fL"
        case .rdw: "%"
        case .alp: "U/L"
        case .wbc: "10³/µL"
        }
    }

    /// The unit shown by default. One of `acceptedUnits`.
    var displayUnit: String {
        switch self {
        case .albumin: "g/dL"
        case .creatinine: "mg/dL"
        case .glucose: "mg/dL"
        case .crp: "mg/L"
        case .lymphocytePercent: "%"
        case .mcv: "fL"
        case .rdw: "%"
        case .alp: "U/L"
        case .wbc: "10³/µL"
        }
    }

    /// Normalised lab unit to the factor that converts a value in it into
    /// `levineUnit`.
    var acceptedUnits: [String: Double] {
        switch self {
        case .albumin: ["g/l": 1, "g/dl": 10]
        case .creatinine: ["umol/l": 1, "mg/dl": 88.42]
        case .glucose: ["mmol/l": 1, "mg/dl": 1.0 / 18.0182]
        case .crp: ["mg/dl": 1, "mg/l": 0.1]
        case .lymphocytePercent, .rdw: ["%": 1]
        case .mcv: ["fl": 1]
        case .alp: ["u/l": 1, "iu/l": 1]
        case .wbc: ["10^3/ul": 1, "10^9/l": 1, "k/ul": 1, "x10^9/l": 1]
        }
    }

    /// The population median imputed for a missing marker, and the baseline
    /// of each marker's leave one out contribution. Creatinine differs by sex.
    func referenceMedian(sex: LabSex) -> Double {
        switch self {
        case .albumin: 45
        case .creatinine: sex == .male ? 88 : 70
        case .glucose: 5.0
        case .crp: 0.1
        case .lymphocytePercent: 32
        case .mcv: 90
        case .rdw: 13
        case .alp: 70
        case .wbc: 6.0
        }
    }

    /// An indicative adult range in `levineUnit`, for the rail the panel
    /// draws.
    var referenceRange: ClosedRange<Double> {
        switch self {
        case .albumin: 35...50
        case .creatinine: 53...106
        case .glucose: 3.9...5.5
        case .crp: 0...0.1
        case .lymphocytePercent: 20...40
        case .mcv: 80...100
        case .rdw: 11.5...14.5
        case .alp: 40...130
        case .wbc: 4...11
        }
    }

    /// A wide sanity range in `levineUnit`. A value outside it is badged on
    /// the confirm screen, never refused.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .albumin: 20...60
        case .creatinine: 20...400
        case .glucose: 2...40
        case .crp: 0...50
        case .lymphocytePercent: 1...90
        case .mcv: 50...130
        case .rdw: 8...40
        case .alp: 10...1000
        case .wbc: 1...100
        }
    }

    /// A value in `unit` converted into `levineUnit`, or nil when the unit
    /// is not one this marker accepts.
    func toLevineUnit(_ value: Double, from unit: String) -> Double? {
        guard let factor = acceptedUnits[BloodMarkerCatalog.normalize(unit)] else { return nil }
        return value * factor
    }
}

/// One marker's value in a saved panel.
nonisolated struct BloodMarkerValue: Codable, Sendable, Hashable, Identifiable {
    enum Source: String, Codable, Sendable { case extracted, manual }

    /// The catalog id, or `custom:<slug>` for a marker the catalog does not
    /// know. For the nine PhenoAge markers it equals the key's raw value.
    var key: String
    /// In the marker's storage unit, or verbatim when the entered unit was
    /// not recognised.
    var value: Double
    /// The unit the lab or the person wrote.
    var enteredUnit: String
    var source: Source
    /// The name of a marker the catalog does not know.
    var customName: String?
    /// The lab's own printed range, in `enteredUnit`. Shown, never computed with.
    var labRefLow: Double?
    var labRefHigh: Double?

    var id: String { key }

    var phenoAgeKey: BloodMarkerKey? { BloodMarkerKey(rawValue: key) }
}

/// A confirmed blood panel: when it was drawn and what it read.
nonisolated struct BloodPanel: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var sampledAt: Date?
    var createdAt: Date
    var markers: [BloodMarkerValue]

    init(id: UUID = UUID(), sampledAt: Date?, createdAt: Date, markers: [BloodMarkerValue]) {
        self.id = id
        self.sampledAt = sampledAt
        self.createdAt = createdAt
        self.markers = markers
    }

    /// The date the panel speaks for: when blood was drawn, else when it was saved.
    var date: Date { sampledAt ?? createdAt }

    func value(_ key: String) -> BloodMarkerValue? {
        markers.first { $0.key == key }
    }

    /// The PhenoAge markers this panel carries, in Levine units.
    var phenoAgeValues: [BloodMarkerKey: Double] {
        Dictionary(markers.compactMap { mv in mv.phenoAgeKey.map { ($0, mv.value) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Every other catalog marker, keyed by id, in storage units.
    var extendedValues: [String: Double] {
        Dictionary(markers.filter { $0.phenoAgeKey == nil }.map { ($0.key, $0.value) },
                   uniquingKeysWith: { first, _ in first })
    }
}
