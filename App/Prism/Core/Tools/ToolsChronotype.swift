//
//  ToolsChronotype.swift
//  Prism
//
//  Chronotype value types.
//

import Foundation

extension SomaTools {

    /// Chronotype category. The behavioral cutoffs on MSFsc are approximate
    /// (Roenneberg MCTQ uses population percentiles); the rMEQ cutoffs are the
    /// published Adan & Almirall 1991 boundaries.
    nonisolated enum ChronotypeCategory: String, Codable, Sendable, CaseIterable {
        case morning
        case intermediate
        case evening
    }

    /// Reduced Morningness-Eveningness Questionnaire (Adan & Almirall 1991):
    /// 5 items, each already mapped to its published point value, total in [4, 25].
    /// Cutoffs: 4 to 11 evening, 12 to 17 intermediate, 18 to 25 morning.
    nonisolated struct RMEQAnswers: Codable, Sendable, Equatable {
        /// The five per-item point values (the UI maps option text to points).
        var items: [Int]

        var total: Int { items.reduce(0, +) }
        var isComplete: Bool { items.count == 5 }

        var category: ChronotypeCategory {
            switch total {
            case ...11: return .evening
            case 12...17: return .intermediate
            default: return .morning
            }
        }
    }

    /// A resolved chronotype estimate plus its provenance.
    nonisolated struct Chronotype: Codable, Sendable, Equatable {
        /// Where the estimate came from.
        nonisolated enum Source: String, Codable, Sendable {
            case rMEQ        // questionnaire seed (day 1)
            case behavioral  // MSFsc from sleep timing
        }

        var category: ChronotypeCategory
        /// Sleep-corrected mid-sleep on free days, clock hours [0, 24).
        /// nil when the estimate is rMEQ-only.
        var msfScHours: Double?
        /// Social jetlag |MSF minus MSW| in hours. nil when unknown.
        var socialJetlagHours: Double?
        var source: Source
    }
}
