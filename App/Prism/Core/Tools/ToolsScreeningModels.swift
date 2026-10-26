//
//  ToolsScreeningModels.swift
//  Prism
//
//  Value types for the preventive screening ledger. Pure data: no SwiftUI, no
//  store. Here "screening" means the real thing: a colonoscopy, a mammogram, a
//  DEXA scan.
//
//  Copy rule, enforced by the types and not only in review: an item of tier
//  `.discuss` can never be reported as due or late. See ScreeningDueEngine.
//

import Foundation

extension SomaTools {

    /// How strong the evidence behind a screening is, and therefore whether the
    /// app may call it overdue.
    ///
    /// `.recommended` is USPSTF grade A or B: a start age and an interval the
    /// app can assert. `.discuss` is everything weaker (grade C, grade I, or a
    /// specialty society decision aid that is not a screening test at all). A
    /// `.discuss` item is listed, its last date remembered, and nothing more is
    /// claimed about it.
    nonisolated enum ScreeningTier: String, Codable, Sendable {
        case recommended
        case discuss
    }

    /// Who a screening applies to.
    nonisolated enum ScreeningEligibility: String, Codable, Sendable {
        case any
        case female
        case male

        /// Maps a free form sex string. Anything unrecognised, empty included,
        /// returns nil: an unknown sex must not silently pick a side, and the
        /// caller then shows only `.any` items.
        static func from(profileSex: String) -> ScreeningEligibility? {
            switch profileSex.trimmingCharacters(in: .whitespaces).lowercased() {
            case "female", "f", "femme", "woman", "w": return .female
            case "male", "m", "homme", "man": return .male
            default: return nil
            }
        }

        /// True when an item gated on `self` applies to someone whose
        /// eligibility is `userSex`. `.any` items apply to everyone, an unknown
        /// sex included.
        func applies(to userSex: ScreeningEligibility?) -> Bool {
            guard self != .any else { return true }
            return self == userSex
        }
    }

    /// A risk answer the user gives once: first degree family history, plus
    /// tobacco history, which two catalog items are gated on.
    ///
    /// A closed enum rather than free text: the engine must never infer a risk
    /// from anything except an explicit answer. A family flag is answered
    /// on the ledger, or by a first degree relative in the medical record's
    /// family history (`MedicalRecord.screeningRisks`, folded in by
    /// `ScreeningLedger.withFamilyHistory`).
    nonisolated enum ScreeningRiskFlag: String, Codable, Sendable, CaseIterable {
        case familyColorectal
        case familyBreastOvarian
        case familyProstate
        case familyMelanoma
        case familyOsteoporosis
        case familyEarlyCardiac
        case familyDiabetes
        /// Ever smoked, at any intensity. Gates lung CT and abdominal aortic
        /// ultrasound.
        case tobaccoEverSmoker

        /// True when this flag describes a first degree relative, and therefore
        /// when `earliestDiagnosisAge` is meaningful for it.
        var isFamilyHistory: Bool { self != .tobaccoEverSmoker }

        /// The question as the ledger asks it.
        var label: String {
            switch self {
            case .familyColorectal: return "Colorectal cancer in the family"
            case .familyBreastOvarian: return "Breast or ovarian cancer in the family"
            case .familyProstate: return "Prostate cancer in the family"
            case .familyMelanoma: return "Melanoma in the family"
            case .familyOsteoporosis: return "Osteoporosis or hip fracture in the family"
            case .familyEarlyCardiac: return "Heart attack or stroke before 55 in the family"
            case .familyDiabetes: return "Type 2 diabetes in the family"
            case .tobaccoEverSmoker: return "I have smoked, now or in the past"
            }
        }
    }

    /// How one answered risk flag changes one catalog item.
    ///
    /// All three adjustments are optional and independent. When several apply,
    /// the engine keeps the earliest start age and the shortest interval: risk
    /// only ever pulls a screening forward, never pushes it back.
    nonisolated struct ScreeningModifier: Sendable, Equatable {
        let flag: ScreeningRiskFlag
        /// Fixed replacement start age, e.g. colorectal at 40 instead of 45.
        var startAgeOverride: Int?
        /// Start this many years before the youngest relative's diagnosis.
        /// Applied only when the answer carries `earliestDiagnosisAge`. Ten years
        /// before a father diagnosed at 45 gives a start at 35.
        var yearsBeforeRelativeDiagnosis: Int?
        /// Shorter cadence, e.g. colorectal every 5 years instead of every 10.
        var intervalMonthsOverride: Int?

        init(flag: ScreeningRiskFlag,
             startAgeOverride: Int? = nil,
             yearsBeforeRelativeDiagnosis: Int? = nil,
             intervalMonthsOverride: Int? = nil) {
            self.flag = flag
            self.startAgeOverride = startAgeOverride
            self.yearsBeforeRelativeDiagnosis = yearsBeforeRelativeDiagnosis
            self.intervalMonthsOverride = intervalMonthsOverride
        }
    }

    /// A cadence that takes over from a given age, e.g. cervical screening
    /// moving from cytology every three years to HPV testing every five at 30.
    nonisolated struct ScreeningAgeBand: Sendable, Equatable {
        let fromAge: Int
        let intervalMonths: Int
    }

    /// One screening in the catalog.
    nonisolated struct ScreeningItem: Sendable, Equatable, Identifiable {
        /// Stable key, also the `itemID` persisted on every record. Never
        /// renamed once shipped.
        let id: String
        let title: String
        let tier: ScreeningTier
        /// SF Symbol.
        let icon: String
        let eligibility: ScreeningEligibility
        let startAge: Int
        /// Age past which the app stops asserting anything. nil = no stop age.
        let stopAge: Int?
        /// nil means once in a lifetime: one record settles it forever.
        let intervalMonths: Int?
        /// Cadences that replace `intervalMonths` from an age on, youngest
        /// first. Read at the age the screening was done, so a test done at 29
        /// keeps the cadence of 29.
        let ageIntervals: [ScreeningAgeBand]
        /// An item gated on a risk flag stays `.discussOnly` until that flag is
        /// answered true. This keeps a lung CT from telling a lifelong
        /// non smoker they are overdue.
        let requiresRiskFlag: ScreeningRiskFlag?
        /// One line: what it catches, why this cadence.
        let evidence: String
        /// Source, e.g. "USPSTF 2021 grade A".
        let citation: String
        let modifiers: [ScreeningModifier]

        init(id: String,
             title: String,
             tier: ScreeningTier,
             icon: String,
             eligibility: ScreeningEligibility = .any,
             startAge: Int,
             stopAge: Int? = nil,
             intervalMonths: Int?,
             ageIntervals: [ScreeningAgeBand] = [],
             requiresRiskFlag: ScreeningRiskFlag? = nil,
             evidence: String,
             citation: String,
             modifiers: [ScreeningModifier] = []) {
            self.id = id
            self.title = title
            self.tier = tier
            self.icon = icon
            self.eligibility = eligibility
            self.startAge = startAge
            self.stopAge = stopAge
            self.intervalMonths = intervalMonths
            self.ageIntervals = ageIntervals
            self.requiresRiskFlag = requiresRiskFlag
            self.evidence = evidence
            self.citation = citation
            self.modifiers = modifiers
        }

        /// The catalog cadence at `age`: the last band the age has reached,
        /// else `intervalMonths`. nil stays once in a lifetime.
        func intervalMonths(atAge age: Int?) -> Int? {
            guard let base = intervalMonths else { return nil }
            guard let age else { return base }
            return ageIntervals.last { age >= $0.fromAge }?.intervalMonths ?? base
        }
    }

    /// A risk answer as the engine consumes it.
    nonisolated struct ScreeningRisk: Sendable, Equatable, Codable {
        let flag: ScreeningRiskFlag
        var isPresent: Bool
        /// Age at diagnosis of the youngest affected first degree relative, when
        /// known. nil disables `yearsBeforeRelativeDiagnosis` for this flag.
        var earliestDiagnosisAge: Int?
        /// Pack years, when known. Informational: no catalog item branches on
        /// the amount, only on whether the flag is present.
        var packYears: Int?
        /// When the answer was last given. Informational.
        var answeredAt: Date?

        init(flag: ScreeningRiskFlag,
             isPresent: Bool,
             earliestDiagnosisAge: Int? = nil,
             packYears: Int? = nil,
             answeredAt: Date? = nil) {
            self.flag = flag
            self.isPresent = isPresent
            self.earliestDiagnosisAge = earliestDiagnosisAge
            self.packYears = packYears
            self.answeredAt = answeredAt
        }
    }

    /// A performed screening.
    nonisolated struct ScreeningDone: Sendable, Equatable, Identifiable, Codable {
        let id: UUID
        /// `ScreeningItem.id`. A plain string so a record survives an item
        /// leaving the catalog.
        let itemID: String
        var performedOn: Date
        var note: String?
        /// Points at an attached document, when one exists.
        var documentID: UUID?
        /// A result can revise the cadence: polyps found on a colonoscopy means
        /// five years, not ten. When set, this wins over the catalog interval.
        var nextDueOverride: Date?

        init(id: UUID = UUID(),
             itemID: String,
             performedOn: Date,
             note: String? = nil,
             documentID: UUID? = nil,
             nextDueOverride: Date? = nil) {
            self.id = id
            self.itemID = itemID
            self.performedOn = performedOn
            self.note = note
            self.documentID = documentID
            self.nextDueOverride = nextDueOverride
        }
    }
}
