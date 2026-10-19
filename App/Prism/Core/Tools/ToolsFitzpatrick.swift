//
//  ToolsFitzpatrick.swift
//  Prism
//
//  The Fitzpatrick skin phototype (I lightest to VI darkest), the one scale
//  the burn time (`ErythemalDoseEngine`), the vitamin D estimate
//  (`VitaminDEngine`) and the self-assessment (`FitzpatrickAssessment`) all
//  key on. Kept as a shared primitive: each engine that needs a per-type
//  number keeps its own table, except the vitamin D sensitivity, which is
//  carried on the type itself.
//

import Foundation

extension SomaTools {

    /// Fitzpatrick skin phototype (I lightest to VI darkest) with a RELATIVE
    /// vitamin D synthesis sensitivity factor. Lighter skin synthesizes vitamin
    /// D faster for the same UVB, so the factor runs from 1.0 (type I) down to
    /// 0.35 (type VI). These are relative multipliers for the wellness model,
    /// not clinical minimal erythemal dose ratios.
    nonisolated enum Fitzpatrick: Int, Sendable, CaseIterable, Equatable, Identifiable {
        case typeI = 1
        case typeII = 2
        case typeIII = 3
        case typeIV = 4
        case typeV = 5
        case typeVI = 6

        var id: Int { rawValue }

        /// The type a page assumes before the user has picked or answered.
        static let assumedDefault: Fitzpatrick = .typeIII

        /// Relative synthesis speed versus the lightest skin (type I = 1.0).
        /// Monotonically decreasing with melanin.
        var sensitivityFactor: Double {
            switch self {
            case .typeI:   return 1.00
            case .typeII:  return 0.90
            case .typeIII: return 0.75
            case .typeIV:  return 0.60
            case .typeV:   return 0.45
            case .typeVI:  return 0.35
            }
        }

        /// The roman numeral the pickers and stat cells print.
        var roman: String {
            switch self {
            case .typeI:   return "I"
            case .typeII:  return "II"
            case .typeIII: return "III"
            case .typeIV:  return "IV"
            case .typeV:   return "V"
            case .typeVI:  return "VI"
            }
        }

        /// "Type III", the label of the result card.
        var label: String { "Type \(roman)" }

        /// One line per type: how the skin reacts, then how it looks. The
        /// reaction comes first because it is what defines the scale.
        var summary: String {
            switch self {
            case .typeI:   return "Type I: always burns, never tans. Very fair skin."
            case .typeII:  return "Type II: burns easily, tans minimally. Fair skin."
            case .typeIII: return "Type III: sometimes burns, tans gradually. Medium skin."
            case .typeIV:  return "Type IV: rarely burns, tans easily. Olive skin."
            case .typeV:   return "Type V: very rarely burns, tans darkly. Brown skin."
            case .typeVI:  return "Type VI: never burns, deeply pigmented. Dark brown to black skin."
            }
        }
    }
}
