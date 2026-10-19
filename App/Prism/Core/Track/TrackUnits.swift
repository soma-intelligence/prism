//
//  TrackUnits.swift
//  Prism
//

import Foundation

/// Weight as a person reads it: kilograms, or pounds where the locale says.
/// Always stored in kilograms.
nonisolated enum TrackMassUnit: String, Codable, CaseIterable, Sendable {
    case kilograms
    case pounds

    static let poundsPerKilogram = 2.204_62

    static func preferred(_ locale: Locale = .current) -> TrackMassUnit {
        locale.measurementSystem == .us ? .pounds : .kilograms
    }

    var symbol: String { self == .kilograms ? "kg" : "lb" }

    func display(_ kilograms: Double) -> Double {
        self == .kilograms ? kilograms : kilograms * Self.poundsPerKilogram
    }

    func kilograms(_ display: Double) -> Double {
        self == .kilograms ? display : display / Self.poundsPerKilogram
    }

    /// One detent of the scale.
    var step: Double { self == .kilograms ? 0.1 : 0.2 }

    /// "68.4": one decimal.
    func text(_ kilograms: Double) -> String {
        String(format: "%.1f", display(kilograms))
    }
}

/// Lengths on the body: centimetres, or feet and inches.
nonisolated enum TrackLengthUnit: String, Codable, CaseIterable, Sendable {
    case centimetres
    case feetInches

    static let centimetresPerInch = 2.54

    static func preferred(_ locale: Locale = .current) -> TrackLengthUnit {
        locale.measurementSystem == .us ? .feetInches : .centimetres
    }

    var title: String { self == .centimetres ? "cm" : "ft, in" }

    /// The number and its unit, set apart so the number can be large:
    /// ("172.0", "cm"), ("5′ 8″", "").
    func parts(_ centimetres: Double) -> (value: String, unit: String) {
        switch self {
        case .centimetres:
            return (String(format: "%.1f", centimetres), "cm")
        case .feetInches:
            let inches = Int((centimetres / Self.centimetresPerInch).rounded())
            return ("\(inches / 12)\u{2032} \(inches % 12)\u{2033}", "")
        }
    }

    /// One detent of the ruler, in centimetres.
    var step: Double { self == .centimetres ? 0.5 : Self.centimetresPerInch }
}
