//
//  StoolCatalog.swift
//  Prism
//
//  Every stool marker Soma knows: four a clinical lab reports (calprotectin,
//  the faecal immunochemical test for hidden blood, pancreatic elastase and
//  the Helicobacter pylori stool antigen) and five a microbiome kit reports
//  (Shannon diversity, three taxa as relative abundance, and the Firmicutes
//  to Bacteroidetes ratio).
//
//  Each marker names its storage unit, the units accepted on entry with the
//  factor into storage, the aliases a printed report uses, and how a value
//  reads (`flag(value:)`): a badge, never a diagnosis. A result that needs
//  care points to a clinician.
//
//  Sources for the bands:
//  NICE DG11, Faecal calprotectin diagnostic tests for inflammatory diseases
//  of the bowel, 2013 (under 50 µg/g usual, 50 to 200 borderline and worth a
//  repeat, over 200 a referral).
//  US Multi-Society Task Force on Colorectal Cancer, Robertson DJ et al.
//  Gastroenterology 2017;152:1217-37, and USPSTF 2021 (a positive FIT is
//  followed by a colonoscopy; the common cut off is 20 µg haemoglobin per
//  gram of stool).
//  Löhr JM et al. HaPanEU guidelines on chronic pancreatitis, United European
//  Gastroenterol J 2017;5:153-99 (elastase over 200 µg/g usual, 100 to 200
//  mild to moderate exocrine insufficiency, under 100 severe).
//  Chey WD et al. ACG Clinical Guideline: Treatment of Helicobacter pylori
//  Infection, Am J Gastroenterol 2017;112:212-39 (a positive test is treated).
//  No band for diversity or taxa: Shade A, Diversity is the question, not the
//  answer, ISME J 2017;11:1-6; Lloyd-Price J et al. Nature 2017;550:61-6
//  (wide spread among healthy people); Magne F et al. The Firmicutes to
//  Bacteroidetes ratio, Nutrients 2020;12:1474 (not a reliable marker on its
//  own). Those read against the person's own earlier tests only.
//

import Foundation

/// How one stool value reads.
nonisolated enum LabFlag: String, Codable, Sendable {
    /// In the usual range.
    case usual
    /// Between usual and raised: worth a repeat.
    case borderline
    /// Above the range.
    case elevated
    /// Below the range.
    case low
    /// A result that asks for a doctor soon, whatever else the test says.
    case actNow
    /// No agreed range: read against the person's own tests.
    case noBand

    var isOutside: Bool { self == .borderline || self == .elevated || self == .low || self == .actNow }

    /// Worth a word with a clinician.
    var needsClinician: Bool { self == .elevated || self == .low || self == .actNow }
}

nonisolated enum StoolMarkerGroup: String, CaseIterable, Sendable {
    case inflammation, digestion, microbiome

    var title: String {
        switch self {
        case .inflammation: "Inflammation and hidden blood"
        case .digestion: "Digestion and infection"
        case .microbiome: "Microbiome"
        }
    }
}

nonisolated struct StoolMarker: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let group: StoolMarkerGroup
    /// The unit stored values are in, also the one shown. Empty for a marker
    /// without one (an index, a ratio, a positive or negative result).
    let unit: String
    /// Normalised unit to the factor into `unit`. Empty accepts a bare number.
    let acceptedUnits: [String: Double]
    /// Negative (0) or positive (1).
    let isQualitative: Bool
    /// The usual result in words: "Under 50 µg/g", "Negative".
    let usual: String
    let aliases: [String]

    static func == (a: StoolMarker, b: StoolMarker) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// False for a marker with no agreed range.
    var hasBand: Bool { flag(value: 0) != .noBand }

    func toStorage(_ value: Double, from unit: String) -> Double? {
        let key = BloodMarkerCatalog.normalize(unit)
        if acceptedUnits.isEmpty || key.isEmpty { return value }
        guard let factor = acceptedUnits[key] else { return nil }
        return value * factor
    }

    func accepts(_ unit: String) -> Bool {
        let key = BloodMarkerCatalog.normalize(unit)
        return acceptedUnits.isEmpty || key.isEmpty || acceptedUnits[key] != nil
    }

    /// How a stored value reads, by the sources above.
    func flag(value: Double) -> LabFlag {
        switch id {
        case "calprotectin":
            if value < 50 { return .usual }
            return value <= 200 ? .borderline : .elevated
        case "fit":
            return value >= 0.5 ? .actNow : .usual
        case "elastase":
            if value > 200 { return .usual }
            return value >= 100 ? .borderline : .low
        case "hPylori":
            return value >= 0.5 ? .elevated : .usual
        default:
            return .noBand
        }
    }

    /// What to do about a result that needs care, in words that inform and
    /// never diagnose. Nil when the result needs nothing.
    func advice(value: Double) -> String? {
        switch (id, flag(value: value)) {
        case ("fit", .actNow):
            "A positive stool blood test needs a follow up, usually a colonoscopy. Call your doctor this week to arrange it: the follow up is what tells what the blood means."
        case ("calprotectin", .elevated):
            "Calprotectin over 200 can mean inflammation in the bowel. Share the result with your doctor, who may repeat it or refer you."
        case ("calprotectin", .borderline):
            "Between 50 and 200 is borderline: guidelines suggest repeating the test in a few weeks."
        case ("elastase", .low):
            "Low elastase can mean the pancreas makes too few digestive enzymes. Worth showing your doctor, especially with oily stools or weight loss."
        case ("elastase", .borderline):
            "Slightly low elastase. Worth mentioning to your doctor if digestion troubles you."
        case ("hPylori", .elevated):
            "A positive H. pylori test is usually treated. Your doctor can prescribe it and check it worked."
        default:
            nil
        }
    }
}

nonisolated enum StoolCatalog {
    /// Micrograms per gram, the unit every faecal protein is printed in.
    private static let microgramsPerGram: [String: Double] = ["ug/g": 1, "mg/kg": 1]
    private static let percent: [String: Double] = ["%": 1]

    static let all: [StoolMarker] = [
        StoolMarker(id: "calprotectin", name: "Calprotectin", group: .inflammation,
                    unit: "µg/g", acceptedUnits: microgramsPerGram, isQualitative: false, usual: "Under 50 µg/g",
                    aliases: ["calprotectin", "faecal calprotectin", "fecal calprotectin", "calprotectine", "calprotectine fecale", "fcp"]),
        StoolMarker(id: "fit", name: "Hidden blood (FIT)", group: .inflammation,
                    unit: "", acceptedUnits: [:], isQualitative: true, usual: "Negative",
                    aliases: ["fit", "faecal immunochemical test", "fecal immunochemical test", "occult blood", "fecal occult blood",
                              "faecal occult blood", "fobt", "ifobt", "sang occulte", "test immunologique"]),
        StoolMarker(id: "elastase", name: "Pancreatic elastase", group: .digestion,
                    unit: "µg/g", acceptedUnits: microgramsPerGram, isQualitative: false, usual: "Over 200 µg/g",
                    aliases: ["elastase", "pancreatic elastase", "pancreatic elastase 1", "fecal elastase", "faecal elastase", "elastase fecale"]),
        StoolMarker(id: "hPylori", name: "H. pylori antigen", group: .digestion,
                    unit: "", acceptedUnits: [:], isQualitative: true, usual: "Negative",
                    aliases: ["h pylori", "h. pylori", "helicobacter pylori", "helicobacter pylori stool antigen", "h pylori antigen",
                              "helicobacter", "antigene helicobacter"]),
        StoolMarker(id: "shannon", name: "Diversity (Shannon)", group: .microbiome,
                    unit: "", acceptedUnits: [:], isQualitative: false, usual: "No single healthy value",
                    aliases: ["shannon", "shannon diversity", "shannon index", "shannon diversity index", "alpha diversity", "diversity index"]),
        StoolMarker(id: "akkermansia", name: "Akkermansia", group: .microbiome,
                    unit: "%", acceptedUnits: percent, isQualitative: false, usual: "No single healthy value",
                    aliases: ["akkermansia", "akkermansia muciniphila", "a muciniphila"]),
        StoolMarker(id: "faecalibacterium", name: "Faecalibacterium", group: .microbiome,
                    unit: "%", acceptedUnits: percent, isQualitative: false, usual: "No single healthy value",
                    aliases: ["faecalibacterium", "faecalibacterium prausnitzii", "f prausnitzii"]),
        StoolMarker(id: "bifidobacterium", name: "Bifidobacterium", group: .microbiome,
                    unit: "%", acceptedUnits: percent, isQualitative: false, usual: "No single healthy value",
                    aliases: ["bifidobacterium", "bifidobacteria", "bifidobacterium spp"]),
        StoolMarker(id: "firmicutesBacteroidetes", name: "Firmicutes to Bacteroidetes", group: .microbiome,
                    unit: "", acceptedUnits: [:], isQualitative: false, usual: "No single healthy value",
                    aliases: ["firmicutes bacteroidetes", "firmicutes bacteroidetes ratio", "firmicutes to bacteroidetes",
                              "f b ratio", "bacillota bacteroidota"]),
    ]

    static let byID: [String: StoolMarker] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func marker(id: String) -> StoolMarker? { byID[id] }
}
