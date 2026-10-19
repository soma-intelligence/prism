//
//  SomaPreviewSamples+Inputs.swift
//  SomaUIPreviewSupport
//

import SwiftUI
import SomaUI

/// Sample values for the visual inputs in the gallery: Sam Rivera's evening.
public extension SomaPreviewSamples {
    static let weightKilograms = 68.4
    static let heightCentimetres = 172.0
    static let waterMillilitres = 250.0
    static let fastStartHour = 20.0
    static let fastLengthHours = 14.0
    static let sleepWindow: (from: Double, to: Double) = (23.25, 7)
    static let plungeMinutes = 3.0
    static let scoopGrams = 10.0
    static let wakeRating: Int? = 7
    static let feeling: Int? = 4
    static let feelingNames = [
        "Very unpleasant", "Unpleasant", "Slightly unpleasant", "Neutral",
        "Slightly pleasant", "Pleasant", "Very pleasant",
    ]

    static let dayGlasses: [Double] = [1, 1, 1, 1, 1, 1, 0.4, 0]

    static let dayPours: [SomaVessel.Mark] = [
        .init(id: 0, top: 0.18, bottom: 0, label: "07:30   400 ml"),
        .init(id: 1, top: 0.32, bottom: 0.18, label: "10:30   300 ml"),
        .init(id: 2, top: 0.54, bottom: 0.32, label: "13:00   500 ml"),
        .init(id: 3, top: 0.73, bottom: 0.54, label: "16:30   400 ml"),
    ]

    static let dinnerParts: [SomaMacroPart] = [
        .init(title: "Protein", detail: "38 g", weight: 152),
        .init(title: "Carbs", detail: "62 g", weight: 248),
        .init(title: "Fat", detail: "22 g", weight: 198),
    ]
}
