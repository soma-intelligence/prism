//
//  SomaPreviewSamples+Zones.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// Two metrics on their zone bars for the gallery: a resting heart rate in
/// its optimal zone, and an HRV under the typical range for its age.
public extension SomaPreviewSamples {
    static let zoneBarResting: [SomaZoneBar.Zone] = [
        .init(name: "Very low", lower: 30, upper: 40, tone: .out),
        .init(name: "Athletic", lower: 40, upper: 50, tone: .good),
        .init(name: "Optimal", lower: 50, upper: 70, tone: .good),
        .init(name: "Normal", lower: 70, upper: 100, tone: .fair),
        .init(name: "High", lower: 100, upper: 130, tone: .out),
    ]
    static let zoneBarRestingValue: Double = 58

    static let zoneBarHRV: [SomaZoneBar.Zone] = [
        .init(name: "Low", lower: 0, upper: 35, tone: .fair),
        .init(name: "Typical", lower: 35, upper: 70, tone: .good),
        .init(name: "High", lower: 70, upper: 105, tone: .good),
    ]
    static let zoneBarHRVValue: Double = 31
}
