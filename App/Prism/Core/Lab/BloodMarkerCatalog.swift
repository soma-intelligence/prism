//
//  BloodMarkerCatalog.swift
//  Prism
//
//  Every blood marker Soma knows: the nine
//  PhenoAge markers the biological age reads, plus the lipid, metabolic,
//  vitamin, hormone, liver, kidney, blood count, electrolyte and advanced
//  cardiometabolic markers a lab report carries.
//
//  Each marker names the unit its stored value is in, the unit shown, the
//  units accepted on entry with the factor into storage, an indicative adult
//  reference range (a badge, never a diagnosis and never a reason to refuse
//  a value) and the aliases a printed report uses for it.
//
//  The nine PhenoAge markers carry a reference range too, so the blood panel
//  can place them on the same rail as the rest.
//

import Foundation

nonisolated enum BloodMarkerCategory: String, CaseIterable, Codable, Sendable {
    case metabolic       // glucose / insulin / diabetes
    case lipids
    case thyroid
    case hormones        // adrenal + sex steroids
    case vitamins
    case minerals        // trace elements
    case iron
    case cardiovascular  // homocysteine, CoQ10
    case inflammation
    case liver
    case kidney
    case hematology      // CBC
    case electrolytes
    case other
    var displayName: String {
        switch self {
        case .metabolic:      return "Glucose Metabolism"
        case .lipids:         return "Lipids"
        case .thyroid:        return "Thyroid"
        case .hormones:       return "Hormones"
        case .vitamins:       return "Vitamins"
        case .minerals:       return "Minerals & Trace Elements"
        case .iron:           return "Iron Status"
        case .cardiovascular: return "Cardiovascular"
        case .inflammation:   return "Inflammation"
        case .liver:          return "Liver"
        case .kidney:         return "Kidney"
        case .hematology:     return "Blood Count"
        case .electrolytes:   return "Electrolytes"
        case .other:          return "Other"
        }
    }
    var symbol: String {
        switch self {
        case .metabolic:      return "drop.fill"
        case .lipids:         return "circle.hexagongrid.fill"
        case .thyroid:        return "bolt.heart.fill"
        case .hormones:       return "waveform.path.ecg"
        case .vitamins:       return "sun.max.fill"
        case .minerals:       return "atom"
        case .iron:           return "square.stack.3d.up.fill"
        case .cardiovascular: return "heart.fill"
        case .inflammation:   return "flame.fill"
        case .liver:          return "cross.case.fill"
        case .kidney:         return "kidneys.fill"
        case .hematology:     return "testtube.2"
        case .electrolytes:   return "bolt.fill"
        case .other:          return "questionmark.circle"
        }
    }
    var sortOrder: Int {
        switch self {
        case .metabolic:      return 0
        case .lipids:         return 1
        case .cardiovascular: return 2
        case .iron:           return 3
        case .vitamins:       return 4
        case .minerals:       return 5
        case .thyroid:        return 6
        case .hormones:       return 7
        case .inflammation:   return 8
        case .liver:          return 9
        case .kidney:         return 10
        case .hematology:     return 11
        case .electrolytes:   return 12
        case .other:          return 13
        }
    }
}
nonisolated struct BloodMarkerGroup<Item>: Identifiable {
    let id: BloodMarkerCategory
    let items: [Item]
    var category: BloodMarkerCategory { id }
}
nonisolated struct BloodMarker: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let category: BloodMarkerCategory
    let storageUnit: String
    let displayUnit: String
    let acceptedUnits: [String: Double]
    let refLow: Double?
    let refHigh: Double?
    let aliases: [String]
    let phenoAgeKey: BloodMarkerKey?
    static func == (a: BloodMarker, b: BloodMarker) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    func toStorage(_ value: Double, from unit: String) -> Double? {
        guard let factor = acceptedUnits[BloodMarkerCatalog.normalize(unit)] else { return nil }
        return value * factor
    }
    func accepts(_ unit: String) -> Bool {
        acceptedUnits[BloodMarkerCatalog.normalize(unit)] != nil
    }
    func toDisplay(_ storageValue: Double) -> Double {
        if BloodMarkerCatalog.normalize(storageUnit) == BloodMarkerCatalog.normalize(displayUnit) {
            return storageValue
        }
        guard let factor = acceptedUnits[BloodMarkerCatalog.normalize(displayUnit)], factor != 0 else {
            return storageValue
        }
        return storageValue / factor
    }
    enum RangeStatus { case low, normal, high, unknown }
    func status(forStorage value: Double) -> RangeStatus {
        if let lo = refLow, value < lo { return .low }
        if let hi = refHigh, value > hi { return .high }
        if refLow == nil && refHigh == nil { return .unknown }
        return .normal
    }
}
nonisolated enum BloodMarkerCatalog {
    static let all: [BloodMarker] = phenoAgeMarkers + extended
    static let byID: [String: BloodMarker] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    static func marker(id: String) -> BloodMarker? { byID[id] }
    static func grouped(_ markers: [BloodMarker]) -> [BloodMarkerGroup<BloodMarker>] {
        group(markers) { $0.category }
    }
    static func group<Item>(_ items: [Item],
                                        by category: (Item) -> BloodMarkerCategory)
        -> [BloodMarkerGroup<Item>] {
        Dictionary(grouping: items, by: category)
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { BloodMarkerGroup(id: $0.key, items: $0.value) }
    }
    static func custom(id: String, name: String, unit: String) -> BloodMarker {
        BloodMarker(id: id, name: name, category: .other,
                    storageUnit: unit, displayUnit: unit,
                    acceptedUnits: [normalize(unit): 1],
                    refLow: nil, refHigh: nil, aliases: [], phenoAgeKey: nil)
    }
    static func customID(for name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "custom:" + (slug.isEmpty ? "marker" : slug)
    }
    static func definition(for value: BloodMarkerValue) -> BloodMarker {
        if let m = byID[value.key] { return m }
        return custom(id: value.key, name: value.customName ?? value.key,
                      unit: value.enteredUnit)
    }
    private static let phenoAgeMarkers: [BloodMarker] =
        BloodMarkerKey.allCases.map { k in
            BloodMarker(
                id: k.rawValue,
                name: k.displayName,
                category: categoryFor(k),
                storageUnit: k.levineUnit,
                displayUnit: k.displayUnit,
                acceptedUnits: k.acceptedUnits,
                refLow: k.referenceRange.lowerBound, refHigh: k.referenceRange.upperBound,
                aliases: aliasesFor(k),
                phenoAgeKey: k)
        }
    private static func categoryFor(_ k: BloodMarkerKey) -> BloodMarkerCategory {
        switch k {
        case .glucose:           return .metabolic
        case .crp:               return .inflammation
        case .albumin, .alp:     return .liver
        case .creatinine:        return .kidney
        case .lymphocytePercent, .mcv, .rdw, .wbc: return .hematology
        }
    }
    private static func aliasesFor(_ k: BloodMarkerKey) -> [String] {
        switch k {
        case .albumin:           return ["albumine"]
        case .creatinine:        return ["créatinine", "creatinine"]
        case .glucose:           return ["glycémie", "glycemie", "glucose à jeun", "fasting glucose", "glycémie à jeun"]
        case .crp:               return ["protéine c réactive", "crp", "hs-crp", "us-crp", "crp ultrasensible"]
        case .lymphocytePercent: return ["lymphocytes %", "lymphocytes"]
        case .mcv:               return ["vgm", "volume globulaire moyen"]
        case .rdw:               return ["idr", "indice de distribution"]
        case .alp:               return ["phosphatases alcalines", "pal"]
        case .wbc:               return ["leucocytes", "globules blancs", "gb"]
        }
    }
    private static let extended: [BloodMarker] = [
        BloodMarker(id: "insulin", name: "Fasting Insulin", category: .metabolic,
                    storageUnit: "pmol/L", displayUnit: "pmol/L",
                    acceptedUnits: ["pmol/l": 1, "uu/ml": 6.945, "uiu/ml": 6.945, "miu/l": 6.945],
                    refLow: nil, refHigh: 118,
                    aliases: ["insuline", "insuline à jeun", "fasting insulin"], phenoAgeKey: nil),
        BloodMarker(id: "homaIR", name: "HOMA Index", category: .metabolic,
                    storageUnit: "index", displayUnit: "index",
                    acceptedUnits: ["index": 1, "indice": 1, "": 1],
                    refLow: nil, refHigh: 2.4,
                    aliases: ["index homa", "indice homa", "homa-ir", "homa"], phenoAgeKey: nil),
        BloodMarker(id: "quicki", name: "QUICKI Index", category: .metabolic,
                    storageUnit: "index", displayUnit: "index",
                    acceptedUnits: ["index": 1, "indice": 1, "": 1],
                    refLow: 0.34, refHigh: nil,
                    aliases: ["index quicki", "indice quicki", "quicki"], phenoAgeKey: nil),
        BloodMarker(id: "hba1c", name: "HbA1c", category: .metabolic,
                    storageUnit: "%", displayUnit: "%",
                    acceptedUnits: ["%": 1],
                    refLow: nil, refHigh: 5.6,
                    aliases: ["hémoglobine glyquée", "hemoglobine glyquee", "a1c", "hba1c"], phenoAgeKey: nil),
        BloodMarker(id: "totalCholesterol", name: "Total Cholesterol", category: .lipids,
                    storageUnit: "mg/dL", displayUnit: "mg/dL",
                    acceptedUnits: ["mg/dl": 1, "mmol/l": 38.67, "g/l": 100],
                    refLow: nil, refHigh: 200,
                    aliases: ["cholestérol total", "cholesterol total", "cholestérol"], phenoAgeKey: nil),
        BloodMarker(id: "ldl", name: "LDL Cholesterol", category: .lipids,
                    storageUnit: "mg/dL", displayUnit: "mg/dL",
                    acceptedUnits: ["mg/dl": 1, "mmol/l": 38.67, "g/l": 100],
                    refLow: nil, refHigh: 130,
                    aliases: ["ldl", "cholestérol ldl", "ldl-c"], phenoAgeKey: nil),
        BloodMarker(id: "hdl", name: "HDL Cholesterol", category: .lipids,
                    storageUnit: "mg/dL", displayUnit: "mg/dL",
                    acceptedUnits: ["mg/dl": 1, "mmol/l": 38.67, "g/l": 100],
                    refLow: 40, refHigh: nil,
                    aliases: ["hdl", "cholestérol hdl", "hdl-c"], phenoAgeKey: nil),
        BloodMarker(id: "triglycerides", name: "Triglycerides", category: .lipids,
                    storageUnit: "mg/dL", displayUnit: "mg/dL",
                    acceptedUnits: ["mg/dl": 1, "mmol/l": 88.57, "g/l": 100],
                    refLow: nil, refHigh: 150,
                    aliases: ["triglycérides", "triglycerides", "tg"], phenoAgeKey: nil),
        BloodMarker(id: "homocysteine", name: "Homocysteine", category: .cardiovascular,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "mg/l": 7.397],
                    refLow: nil, refHigh: 15,
                    aliases: ["homocystéine", "homocysteine"], phenoAgeKey: nil),
        BloodMarker(id: "coenzymeQ10", name: "Coenzyme Q10", category: .cardiovascular,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/ml": 1.158, "mg/l": 1.158],
                    refLow: 0.73, refHigh: 1.87,
                    aliases: ["coenzyme q10", "coq10", "ubiquinone"], phenoAgeKey: nil),
        BloodMarker(id: "ferritin", name: "Ferritin", category: .iron,
                    storageUnit: "µg/L", displayUnit: "µg/L",
                    acceptedUnits: ["ug/l": 1, "ng/ml": 1],
                    refLow: 15, refHigh: 200,
                    aliases: ["ferritine"], phenoAgeKey: nil),
        BloodMarker(id: "ironSerum", name: "Serum Iron", category: .iron,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/dl": 0.1791],
                    refLow: 10, refHigh: 30,
                    aliases: ["fer sérique", "fer serique", "fer", "sidérémie"], phenoAgeKey: nil),
        BloodMarker(id: "transferrin", name: "Transferrin", category: .iron,
                    storageUnit: "g/L", displayUnit: "g/L",
                    acceptedUnits: ["g/l": 1, "mg/dl": 0.01],
                    refLow: 2.0, refHigh: 3.6,
                    aliases: ["transferrine"], phenoAgeKey: nil),
        BloodMarker(id: "transferrinSaturation", name: "Transferrin Saturation", category: .iron,
                    storageUnit: "%", displayUnit: "%",
                    acceptedUnits: ["%": 1],
                    refLow: 20, refHigh: 50,
                    aliases: ["coefficient de saturation", "saturation transferrine", "cst"], phenoAgeKey: nil),
        BloodMarker(id: "vitaminD", name: "Vitamin D (25-OH)", category: .vitamins,
                    storageUnit: "ng/mL", displayUnit: "ng/mL",
                    acceptedUnits: ["ng/ml": 1, "nmol/l": 0.4006],
                    refLow: 30, refHigh: 100,
                    aliases: ["25-hydroxy vitamine d", "vitamine d", "25-oh vitamine d", "25(oh)d", "vitamin d"], phenoAgeKey: nil),
        BloodMarker(id: "vitaminE", name: "Vitamin E", category: .vitamins,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/ml": 2.322, "mg/l": 2.322],
                    refLow: 23.2, refHigh: 46.4,
                    aliases: ["vitamine e", "alpha-tocophérol", "tocophérol", "tocopherol"], phenoAgeKey: nil),
        BloodMarker(id: "vitaminB12", name: "Vitamin B12", category: .vitamins,
                    storageUnit: "pmol/L", displayUnit: "pmol/L",
                    acceptedUnits: ["pmol/l": 1, "pg/ml": 0.738, "ng/l": 0.738],
                    refLow: 145, refHigh: 569,
                    aliases: ["vitamine b12", "cobalamine", "b12"], phenoAgeKey: nil),
        BloodMarker(id: "folate", name: "Folate (B9)", category: .vitamins,
                    storageUnit: "nmol/L", displayUnit: "nmol/L",
                    acceptedUnits: ["nmol/l": 1, "ng/ml": 2.266, "ug/l": 2.266],
                    refLow: 7, refHigh: 45,
                    aliases: ["folates", "acide folique", "vitamine b9", "b9"], phenoAgeKey: nil),
        BloodMarker(id: "zinc", name: "Zinc", category: .minerals,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/dl": 0.15295, "ug/l": 0.015295, "mg/l": 15.295],
                    refLow: 10.7, refHigh: 18.5,
                    aliases: ["zinc"], phenoAgeKey: nil),
        BloodMarker(id: "magnesium", name: "Magnesium", category: .minerals,
                    storageUnit: "mmol/L", displayUnit: "mmol/L",
                    acceptedUnits: ["mmol/l": 1, "mg/dl": 0.4114, "meq/l": 0.5],
                    refLow: 0.66, refHigh: 1.07,
                    aliases: ["magnésium", "magnesium"], phenoAgeKey: nil),
        BloodMarker(id: "copper", name: "Copper", category: .minerals,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/dl": 0.1574],
                    refLow: 11, refHigh: 22,
                    aliases: ["cuivre", "copper"], phenoAgeKey: nil),
        BloodMarker(id: "selenium", name: "Selenium", category: .minerals,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/l": 0.01267],
                    refLow: 0.9, refHigh: 1.7,
                    aliases: ["sélénium", "selenium"], phenoAgeKey: nil),
        BloodMarker(id: "tsh", name: "TSH", category: .thyroid,
                    storageUnit: "mU/L", displayUnit: "mU/L",
                    acceptedUnits: ["mu/l": 1, "miu/l": 1, "uu/ml": 1, "uiu/ml": 1],
                    refLow: 0.35, refHigh: 4.0,
                    aliases: ["thyréostimuline", "tsh us", "thyréotropine"], phenoAgeKey: nil),
        BloodMarker(id: "freeT4", name: "Free T4", category: .thyroid,
                    storageUnit: "pmol/L", displayUnit: "pmol/L",
                    acceptedUnits: ["pmol/l": 1, "ng/dl": 12.87, "ng/l": 1.287],
                    refLow: 9.0, refHigh: 19.0,
                    aliases: ["t4 libre", "ft4", "thyroxine libre"], phenoAgeKey: nil),
        BloodMarker(id: "freeT3", name: "Free T3", category: .thyroid,
                    storageUnit: "pmol/L", displayUnit: "pmol/L",
                    acceptedUnits: ["pmol/l": 1, "pg/ml": 1.536, "ng/l": 1.536],
                    refLow: 2.6, refHigh: 5.4,
                    aliases: ["t3 libre", "ft3", "triiodothyronine libre"], phenoAgeKey: nil),
        BloodMarker(id: "antiTPO", name: "Anti-TPO Antibodies", category: .thyroid,
                    storageUnit: "IU/mL", displayUnit: "IU/mL",
                    acceptedUnits: ["ui/ml": 1, "iu/ml": 1, "u/ml": 1, "ku/l": 1],
                    refLow: nil, refHigh: 34,
                    aliases: ["ac. anti-thyroperoxydase", "atpo", "anti-tpo", "anticorps anti-tpo"], phenoAgeKey: nil),
        BloodMarker(id: "antiThyroglobulin", name: "Anti-Thyroglobulin Antibodies", category: .thyroid,
                    storageUnit: "IU/mL", displayUnit: "IU/mL",
                    acceptedUnits: ["ui/ml": 1, "iu/ml": 1, "u/ml": 1, "ku/l": 1],
                    refLow: nil, refHigh: 115,
                    aliases: ["ac. anti-thyroglobuline", "atg", "anti-tg", "anticorps anti-thyroglobuline"], phenoAgeKey: nil),
        BloodMarker(id: "cortisol", name: "Cortisol", category: .hormones,
                    storageUnit: "nmol/L", displayUnit: "nmol/L",
                    acceptedUnits: ["nmol/l": 1, "ug/dl": 27.59, "ng/ml": 2.759],
                    refLow: 171, refHigh: 536,
                    aliases: ["cortisol total", "cortisol"], phenoAgeKey: nil),
        BloodMarker(id: "dheaSulfate", name: "DHEA-Sulfate", category: .hormones,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "ug/dl": 0.02714, "ug/ml": 2.714],
                    refLow: 1.0, refHigh: 12.0,
                    aliases: ["dhea sulfate", "sdhea", "dhea-s", "sulfate de dhea"], phenoAgeKey: nil),
        BloodMarker(id: "testosterone", name: "Testosterone", category: .hormones,
                    storageUnit: "nmol/L", displayUnit: "nmol/L",
                    acceptedUnits: ["nmol/l": 1, "ng/dl": 0.03467, "ng/ml": 3.467],
                    refLow: nil, refHigh: nil,
                    aliases: ["testostérone", "testosterone totale"], phenoAgeKey: nil),
        BloodMarker(id: "estradiol", name: "Estradiol", category: .hormones,
                    storageUnit: "pmol/L", displayUnit: "pmol/L",
                    acceptedUnits: ["pmol/l": 1, "pg/ml": 3.671, "ng/l": 3.671],
                    refLow: nil, refHigh: nil,
                    aliases: ["œstradiol", "oestradiol", "e2"], phenoAgeKey: nil),
        BloodMarker(id: "esr", name: "ESR", category: .inflammation,
                    storageUnit: "mm/h", displayUnit: "mm/h",
                    acceptedUnits: ["mm/h": 1, "mm/hr": 1],
                    refLow: nil, refHigh: 20,
                    aliases: ["vitesse de sédimentation", "vs", "sédimentation"], phenoAgeKey: nil),
        BloodMarker(id: "alt", name: "ALT (SGPT)", category: .liver,
                    storageUnit: "U/L", displayUnit: "U/L",
                    acceptedUnits: ["u/l": 1, "iu/l": 1],
                    refLow: nil, refHigh: 40,
                    aliases: ["alat", "sgpt", "tgp"], phenoAgeKey: nil),
        BloodMarker(id: "ast", name: "AST (SGOT)", category: .liver,
                    storageUnit: "U/L", displayUnit: "U/L",
                    acceptedUnits: ["u/l": 1, "iu/l": 1],
                    refLow: nil, refHigh: 40,
                    aliases: ["asat", "sgot", "tgo"], phenoAgeKey: nil),
        BloodMarker(id: "ggt", name: "GGT", category: .liver,
                    storageUnit: "U/L", displayUnit: "U/L",
                    acceptedUnits: ["u/l": 1, "iu/l": 1],
                    refLow: nil, refHigh: 55,
                    aliases: ["gamma gt", "gamma-gt", "ggt"], phenoAgeKey: nil),
        BloodMarker(id: "bilirubinTotal", name: "Total Bilirubin", category: .liver,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "mg/dl": 17.1],
                    refLow: nil, refHigh: 21,
                    aliases: ["bilirubine totale", "bilirubine"], phenoAgeKey: nil),
        BloodMarker(id: "uricAcid", name: "Uric Acid", category: .kidney,
                    storageUnit: "µmol/L", displayUnit: "µmol/L",
                    acceptedUnits: ["umol/l": 1, "mg/dl": 59.48],
                    refLow: 150, refHigh: 420,
                    aliases: ["acide urique", "uricémie"], phenoAgeKey: nil),
        BloodMarker(id: "urea", name: "Urea", category: .kidney,
                    storageUnit: "mmol/L", displayUnit: "mmol/L",
                    acceptedUnits: ["mmol/l": 1, "g/l": 16.65],
                    refLow: 2.5, refHigh: 7.1,
                    aliases: ["urée", "uree"], phenoAgeKey: nil),
        BloodMarker(id: "egfr", name: "eGFR", category: .kidney,
                    storageUnit: "mL/min/1.73m²", displayUnit: "mL/min/1.73m²",
                    acceptedUnits: ["ml/min/1.73m2": 1, "ml/min": 1, "ml/min/1.73m²": 1],
                    refLow: 90, refHigh: nil,
                    aliases: ["dfg", "débit de filtration glomérulaire", "ckd-epi", "mdrd"], phenoAgeKey: nil),
        BloodMarker(id: "hemoglobin", name: "Hemoglobin", category: .hematology,
                    storageUnit: "g/dL", displayUnit: "g/dL",
                    acceptedUnits: ["g/dl": 1, "g/l": 0.1, "mmol/l": 1.611],
                    refLow: 12, refHigh: 17,
                    aliases: ["hémoglobine", "hemoglobine", "hb", "hgb"], phenoAgeKey: nil),
        BloodMarker(id: "hematocrit", name: "Hematocrit", category: .hematology,
                    storageUnit: "%", displayUnit: "%",
                    acceptedUnits: ["%": 1, "l/l": 100],
                    refLow: 36, refHigh: 50,
                    aliases: ["hématocrite", "hematocrite", "hct", "ht"], phenoAgeKey: nil),
        BloodMarker(id: "plateletCount", name: "Platelets", category: .hematology,
                    storageUnit: "10³/µL", displayUnit: "10³/µL",
                    acceptedUnits: ["10^3/ul": 1, "10^9/l": 1, "k/ul": 1, "g/l": 1],
                    refLow: 150, refHigh: 400,
                    aliases: ["plaquettes", "thrombocytes", "plt"], phenoAgeKey: nil),
        BloodMarker(id: "redBloodCells", name: "Red Blood Cells", category: .hematology,
                    storageUnit: "10⁶/µL", displayUnit: "10⁶/µL",
                    acceptedUnits: ["10^6/ul": 1, "10^12/l": 1, "m/ul": 1, "t/l": 1],
                    refLow: 4.0, refHigh: 5.5,
                    aliases: ["globules rouges", "hématies", "gr", "rbc"], phenoAgeKey: nil),
        BloodMarker(id: "sodium", name: "Sodium", category: .electrolytes,
                    storageUnit: "mmol/L", displayUnit: "mmol/L",
                    acceptedUnits: ["mmol/l": 1, "meq/l": 1],
                    refLow: 136, refHigh: 145,
                    aliases: ["sodium", "natrémie", "na"], phenoAgeKey: nil),
        BloodMarker(id: "potassium", name: "Potassium", category: .electrolytes,
                    storageUnit: "mmol/L", displayUnit: "mmol/L",
                    acceptedUnits: ["mmol/l": 1, "meq/l": 1],
                    refLow: 3.5, refHigh: 5.1,
                    aliases: ["potassium", "kaliémie", "k"], phenoAgeKey: nil),
        BloodMarker(id: "calcium", name: "Calcium", category: .electrolytes,
                    storageUnit: "mmol/L", displayUnit: "mmol/L",
                    acceptedUnits: ["mmol/l": 1, "mg/dl": 0.2495],
                    refLow: 2.2, refHigh: 2.6,
                    aliases: ["calcium", "calcémie", "ca"], phenoAgeKey: nil),
        BloodMarker(id: "chloride", name: "Chloride", category: .electrolytes,
                    storageUnit: "mmol/L", displayUnit: "mmol/L",
                    acceptedUnits: ["mmol/l": 1, "meq/l": 1],
                    refLow: 98, refHigh: 107,
                    aliases: ["chlore", "chlorémie", "cl"], phenoAgeKey: nil),
        BloodMarker(id: "apoB", name: "Apolipoprotein B", category: .lipids,
                    storageUnit: "mg/dL", displayUnit: "mg/dL",
                    acceptedUnits: ["mg/dl": 1, "g/l": 100, "mg/l": 0.1],
                    refLow: nil, refHigh: 90,
                    aliases: ["apolipoprotéine b", "apolipoproteine b", "apo b",
                              "apob", "apolipoprotein b-100"], phenoAgeKey: nil),
        BloodMarker(id: "lpA", name: "Lipoprotein(a)", category: .lipids,
                    storageUnit: "nmol/L", displayUnit: "nmol/L",
                    acceptedUnits: ["nmol/l": 1, "mg/dl": 2.15, "mg/l": 0.215],
                    refLow: nil, refHigh: 75,
                    aliases: ["lipoprotéine (a)", "lipoproteine (a)", "lp(a)",
                              "lpa", "lipoprotein a"], phenoAgeKey: nil),
        BloodMarker(id: "apoA1", name: "Apolipoprotein A1", category: .lipids,
                    storageUnit: "mg/dL", displayUnit: "mg/dL",
                    acceptedUnits: ["mg/dl": 1, "g/l": 100, "mg/l": 0.1],
                    refLow: 120, refHigh: nil,
                    aliases: ["apolipoprotéine a1", "apolipoproteine a1", "apo a1",
                              "apoa1", "apolipoprotein a-i"], phenoAgeKey: nil),
        BloodMarker(id: "lpPLA2", name: "Lp-PLA2 Activity", category: .cardiovascular,
                    storageUnit: "nmol/min/mL", displayUnit: "nmol/min/mL",
                    acceptedUnits: ["nmol/min/ml": 1],
                    refLow: nil, refHigh: 225,
                    aliases: ["lp-pla2", "lppla2", "plac test",
                              "phospholipase a2 associée aux lipoprotéines",
                              "lipoprotein-associated phospholipase a2"], phenoAgeKey: nil),
        BloodMarker(id: "cystatinC", name: "Cystatin C", category: .kidney,
                    storageUnit: "mg/L", displayUnit: "mg/L",
                    acceptedUnits: ["mg/l": 1],
                    refLow: 0.5, refHigh: 1.0,
                    aliases: ["cystatine c", "cystatin-c", "cysc"], phenoAgeKey: nil),
        BloodMarker(id: "ntProBNP", name: "NT-proBNP", category: .cardiovascular,
                    storageUnit: "pg/mL", displayUnit: "pg/mL",
                    acceptedUnits: ["pg/ml": 1, "ng/l": 1],
                    refLow: nil, refHigh: 125,
                    aliases: ["nt-probnp", "ntprobnp", "pro-bnp", "bnp n-terminal",
                              "peptide natriurétique"], phenoAgeKey: nil),
        BloodMarker(id: "urineACR", name: "Urine Albumin-Creatinine Ratio", category: .kidney,
                    storageUnit: "mg/g", displayUnit: "mg/g",
                    acceptedUnits: ["mg/g": 1, "mg/mmol": 8.84, "ug/mg": 1],
                    refLow: nil, refHigh: 30,
                    aliases: ["rapport albumine créatinine", "racu", "uacr", "acr",
                              "albumin creatinine ratio", "microalbuminurie"], phenoAgeKey: nil),
        BloodMarker(id: "cacScore", name: "Coronary Artery Calcium", category: .cardiovascular,
                    storageUnit: "Agatston", displayUnit: "Agatston",
                    acceptedUnits: ["agatston": 1, "au": 1, "": 1],
                    refLow: nil, refHigh: 0,
                    aliases: ["score calcique", "calcium coronaire", "cac",
                              "agatston", "coronary calcium score"], phenoAgeKey: nil),
    ]
    static func normalize(_ unit: String) -> String {
        var s = unit.lowercased()
        s = s.replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: "µ", with: "u")
        s = s.replacingOccurrences(of: "μ", with: "u")
        s = s.replacingOccurrences(of: "³", with: "^3")
        s = s.replacingOccurrences(of: "⁶", with: "^6")
        s = s.replacingOccurrences(of: "⁹", with: "^9")
        s = s.replacingOccurrences(of: "¹²", with: "^12")
        return s
    }
}
