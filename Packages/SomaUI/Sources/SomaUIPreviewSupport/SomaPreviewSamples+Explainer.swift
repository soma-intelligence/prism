//
//  SomaPreviewSamples+Explainer.swift
//  SomaUIPreviewSupport
//

import SwiftUI
import SomaUI

/// An explainer's worth of sample data: a sleep score's six parts at the
/// engine's weights (40, 15, 15, 10, 10 and 5 over 95), a recovery morning's
/// signed points, and the shared 34 and 67 thresholds.
public extension SomaPreviewSamples {
    static let explainerSleepParts: [SomaExplainerPart] = [
        SomaExplainerPart(title: "Duration", symbol: "clock.fill", hue: .sleep, weight: 42, line: "Time asleep against your need."),
        SomaExplainerPart(title: "Efficiency", symbol: "bed.double.fill", hue: .cycle, weight: 16, line: "Asleep against in bed."),
        SomaExplainerPart(title: "Deep sleep", symbol: "moon.zzz.fill", hue: .hearing, weight: 16, line: "Its share, for your age."),
        SomaExplainerPart(title: "REM", symbol: "sparkles", hue: .symptoms, weight: 11, line: "Its share of the night."),
        SomaExplainerPart(title: "Interruptions", symbol: "alarm.fill", hue: .respiratory, weight: 11, line: "Each waking costs a little."),
        SomaExplainerPart(title: "Heart rate dip", symbol: "heart.fill", hue: .heart, weight: 5, line: "Asleep against resting."),
    ]

    static let explainerSleepMoves: [SomaExplainerMove] = [
        SomaExplainerMove(title: "Duration", value: "36 of 42", hue: .sleep, shape: .filled(36.0 / 42)),
        SomaExplainerMove(title: "Efficiency", value: "11 of 16", hue: .cycle, shape: .filled(11.0 / 16)),
        SomaExplainerMove(title: "Deep sleep", value: "14 of 16", hue: .hearing, shape: .filled(14.0 / 16)),
    ]

    static let explainerRecoveryMoves: [SomaExplainerMove] = [
        SomaExplainerMove(title: "HRV", value: "+14", detail: "58 ms against 51 usual", hue: .heart, shape: .signed(14.0 / 28)),
        SomaExplainerMove(title: "Resting heart rate", value: "\u{2212}4", detail: "56 bpm against 54 usual", hue: .vitals, shape: .signed(-4.0 / 20)),
        SomaExplainerMove(title: "Sleep", value: "+9", detail: "Sleep score 70", hue: .sleep, shape: .signed(9.0 / 16)),
    ]

    static let explainerBands: [SomaExplainerBand] = [
        SomaExplainerBand("Run down", 0...34, tone: .poor),
        SomaExplainerBand("Partly", 34...67, tone: .fair),
        SomaExplainerBand("Recovered", 67...100, tone: .good),
    ]
}

#Preview("Explainer, sleep") {
    SomaExplainer(title: "Sleep", summary: "Last night, against your own need.", aspect: .sleep, onClose: {}) {
        SomaExplainerDonut(parts: SomaPreviewSamples.explainerSleepParts, value: "78", caption: "Fair")
    } content: {
        SomaExplainerSection("How it’s built") {
            ForEach(SomaPreviewSamples.explainerSleepParts) { SomaExplainerRow($0) }
        }
        SomaExplainerMoves("Last night", moves: SomaPreviewSamples.explainerSleepMoves)
        SomaExplainerRanges("Ranges", bands: [
            SomaExplainerBand("Short", 0...60, tone: .poor),
            SomaExplainerBand("Fair", 60...80, tone: .fair),
            SomaExplainerBand("Restored", 80...100, tone: .good),
        ], aspect: .sleep, marker: 78, markerLabel: "Last night, 78")
    }
}

#Preview("Explainer, recovery, dark") {
    SomaExplainer(title: "Recovery", summary: "How ready you are for load today.", aspect: .heart, onClose: {}) {
        SomaExplainerRing(fraction: 0.72, value: "72", caption: "Recovered", aspect: .heart)
    } content: {
        SomaExplainerMoves("What moved it", moves: SomaPreviewSamples.explainerRecoveryMoves)
        SomaExplainerRanges("Ranges", bands: SomaPreviewSamples.explainerBands, aspect: .heart,
                            marker: 72, markerLabel: "Today, 72")
        SomaExplainerNote("Starts from 50. Needs seven nights.")
    }
    .preferredColorScheme(.dark)
}
