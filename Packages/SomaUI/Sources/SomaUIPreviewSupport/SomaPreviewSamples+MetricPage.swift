//
//  SomaPreviewSamples+MetricPage.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// A metric's page for the gallery: a month of steps against a usual band,
/// a week of resting heart rate, the facts under the chart and the sources
/// behind it.
public extension SomaPreviewSamples {
    /// Thirty days of steps, the last one still adding up.
    static let metricSteps: [Double?] = [
        9_840, 8_120, 6_910, 8_470, 9_720, 8_640, 7_290, 7_660, 9_410, 9_530,
        7_250, 7_180, 8_710, 9_380, 8_170, 6_800, 7_950, 9_760, 8_420, 6_920,
        8_050, 9_270, 9_590, 8_840, 7_310, 8_960, 9_820, 8_230, 7_170, 7_020,
    ]

    /// Seven mornings of resting heart rate, one missing.
    static let metricResting: [Double?] = [58, 57, 59, nil, 56, 61, 64]

    /// The steps as chart slots, every seventh day labelled back from today.
    static var metricStepBuckets: [SomaChartBucket] {
        let count = metricSteps.count
        return metricSteps.enumerated().map { index, value in
            SomaChartBucket(
                id: index,
                value: value,
                band: 7_100...9_400,
                axisLabel: (count - 1 - index) % 7 == 0 ? "\((index + 19) % 30 + 1)" : nil,
                readout: "Day \(index + 1)",
                valueText: value.map { Int($0).formatted() }
            )
        }
    }

    /// The resting heart rate as chart slots, one weekday letter each.
    static var metricRestingBuckets: [SomaChartBucket] {
        let days = ["T", "W", "T", "F", "S", "S", "M"]
        return metricResting.enumerated().map { index, value in
            SomaChartBucket(
                id: index, value: value, band: 54...62, axisLabel: days[index],
                readout: days[index], valueText: value.map { "\(Int($0))" }
            )
        }
    }

    static let metricFacts: [SomaFact] = [
        SomaFact("Your usual", value: "7.1K to 9.4K"),
        SomaFact("30 day trend", value: "Up 4%", detail: "From 7,950", tone: .good),
        SomaFact("Usual days", value: "18 of 30"),
    ]

    static let metricSources: [SomaSource] = [
        SomaSource(name: "Apple Watch", symbol: "applewatch", share: 0.81, quality: "Measured"),
        SomaSource(name: "iPhone", symbol: "iphone", share: 0.17, quality: "Estimated"),
        SomaSource(name: "Health", symbol: "hand.point.up.left", share: 0.02, quality: "Entered by hand"),
    ]

    static let metricInfo: [SomaInfoSection] = [
        SomaInfoSection("What it is", body: "Every step your phone and watch count through the day."),
        SomaInfoSection("Your usual", body: "The range your last two weeks sat in. It moves with you."),
        SomaInfoSection("Unit", body: "Steps"),
    ]
}
