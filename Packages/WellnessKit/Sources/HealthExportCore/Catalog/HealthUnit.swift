//
//  HealthUnit.swift
//  HealthExportCore
//

import Foundation

/// The canonical unit a metric is always read in.
///
/// One unit per metric, fixed here rather than chosen at the call site: the same
/// value can then never arrive as kilograms on one screen and pounds on another,
/// and a stored reading needs no unit negotiation to be compared with the next.
///
/// Platform-free on purpose: the mapping to `HKUnit` lives in the HealthKit
/// module, so this catalog compiles and is testable anywhere.
public enum HealthUnit: String, Sendable, Codable, Hashable, CaseIterable {
    case count
    case countPerMinute
    case kilocalorie
    case kilocaloriePerKilogramHour
    case meter
    case centimeter
    case minute
    case hour
    case second
    case millisecond
    case percent
    case millimeterOfMercury
    case kilogram
    case degreeCelsius
    case millilitrePerKilogramMinute
    case metrePerSecond
    case watt
    case milligramPerDecilitre
    case microsiemens
    case decibelASPL
    case decibelHearingLevel
    case litre
    case litrePerMinute
    case internationalUnit
    case gram
    case milligram
    case microgram
    /// Categories, workouts and characteristics carry no unit.
    case none
}
