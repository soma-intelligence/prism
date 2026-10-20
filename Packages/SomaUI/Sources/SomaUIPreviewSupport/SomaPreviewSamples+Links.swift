//
//  SomaPreviewSamples+Links.swift
//  SomaUIPreviewSupport
//

import Foundation
import SwiftUI
import SomaUI

/// Cause and effect links for the gallery and the Trends previews: what the
/// Trends page shows once a person has a couple of months of days.
public extension SomaPreviewSamples {
    struct LinkSample: Identifiable, Sendable {
        public let driver: String
        public let outcome: String
        public let value: String
        public let unit: String
        public let caption: String
        public let tone: SomaLinkTone
        public let high: [Double]
        public let low: [Double]
        /// The card's words: what happens, its size and days, and the sides.
        public let headline: String
        public let detail: String
        public let highLabel: String
        public let lowLabel: String

        public var id: String { "\(driver)>\(outcome)" }
    }

    /// Strongest first.
    static let links: [LinkSample] = [
        LinkSample(driver: "Alcohol", outcome: "Sleep", value: "\u{2212}11", unit: "points", caption: "9 vs 41 nights",
                   tone: .cost,
                   high: [64, 70, 59, 66, 72, 61, 68, 63, 67],
                   low: [78, 74, 81, 69, 77, 83, 72, 80, 75, 79, 76, 82, 73, 71, 84, 77, 79, 74, 80, 78],
                   headline: "After drinking, your sleep score is lower", detail: "About 11 points, across 50 nights",
                   highLabel: "Alcohol", lowLabel: "Without"),
        LinkSample(driver: "Sleep", outcome: "HRV", value: "+8", unit: "ms", caption: "21 long vs 21 short nights",
                   tone: .good,
                   high: [58, 61, 55, 64, 60, 57, 62, 59, 66, 56, 63, 60],
                   low: [49, 52, 47, 55, 50, 51, 53, 48, 54, 50, 46, 52],
                   headline: "After a long night, your morning HRV is higher", detail: "About 8 ms, across 42 nights",
                   highLabel: "Long nights", lowLabel: "Short nights"),
        LinkSample(driver: "Strain", outcome: "Resting HR", value: "+2.4", unit: "bpm", caption: "20 hard vs 20 easy days",
                   tone: .cost,
                   high: [56, 58, 55, 57, 59, 56, 58, 57, 55, 58],
                   low: [54, 53, 55, 54, 52, 55, 53, 54, 56, 53],
                   headline: "After a hard day, your resting heart rate is higher", detail: "About 2.4 bpm, across 40 days",
                   highLabel: "Hard days", lowLabel: "Easy days"),
        LinkSample(driver: "Daylight", outcome: "Bedtime", value: "\u{2212}24", unit: "minutes", caption: "18 bright vs 18 dim days",
                   tone: .neutral,
                   high: [23.1, 23.4, 22.9, 23.2, 23.0, 23.5, 22.8, 23.3],
                   low: [23.6, 23.9, 23.5, 24.1, 23.7, 24.0, 23.4, 23.8],
                   headline: "After a bright day, you fall asleep earlier", detail: "About 24 minutes, across 36 days",
                   highLabel: "Bright days", lowLabel: "Dim days"),
    ]

    /// Links still gathering days.
    static let pendingLinks = ["Active days and sleep", "Sauna and sleep", "Sauna and HRV", "Late coffee and sleep"]

    /// Ninety nights of a sleep score with the alcohol nights lit: what the
    /// first link's detail sheet draws in time. A fixed generator, so the same
    /// nights on every run.
    static let linkDays: [SomaLinkDay] = {
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)) ?? Date(timeIntervalSince1970: 0)
        var state: UInt64 = 0x11AC
        func noise(_ scale: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Double(state >> 11) / Double(1 << 53) * 2 - 1) * scale
        }
        return (0..<90).map { index in
            let date = calendar.date(byAdding: .day, value: index - 89, to: end) ?? end
            let drank = index % 9 == 4 || index % 11 == 6
            let missing = index % 17 == 8
            let value = 77 + (drank ? -11 : 0) + noise(6)
            return SomaLinkDay(date: date, value: missing ? nil : value, side: drank ? .high : .none)
        }
    }()

    /// Dates under the timeline.
    static let linkXLabels = ["Jul 6", "Aug 5", "Sep 4", "Oct 3"]

    /// The first link's facts row.
    static let linkFacts: [SomaLinkFact] = [
        SomaLinkFact("Days", value: "9 vs 41"),
        SomaLinkFact("Difference", value: "\u{2212}11 points"),
        SomaLinkFact("Usual swing", value: "\u{00B1}5 points"),
        SomaLinkFact("Strength", strength: 4),
        SomaLinkFact("Timing", value: "Same night"),
    ]

    /// A link still waiting on its gate.
    static let linkProgress = (fraction: 0.6, label: "3 of 5 nights with Sauna")
}

#Preview("Link detail") {
    let link = SomaPreviewSamples.links[0]
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            SomaLinkHeadline(title: link.headline, value: link.value, unit: link.unit,
                             caption: link.caption, tone: link.tone)
            SomaCard {
                SomaLinkComparison(high: link.high, low: link.low, highLabel: "With", lowLabel: "Without",
                                   gap: "\(link.value) \(link.unit)", tone: link.tone)
            }
            SomaCard {
                SomaLinkTimeline(days: SomaPreviewSamples.linkDays, aspect: .sleep, tone: link.tone,
                                 xLabels: SomaPreviewSamples.linkXLabels, legend: "Alcohol nights")
            }
            SomaCard {
                SomaLinkFacts(SomaPreviewSamples.linkFacts)
            }
        }
        .padding()
    }
}

#Preview("Link waiting") {
    VStack(alignment: .leading, spacing: 20) {
        SomaLinkHeadline(title: "Sauna and sleep", value: nil, unit: "points", caption: nil, tone: .neutral)
        SomaLinkProgress(fraction: SomaPreviewSamples.linkProgress.fraction, label: SomaPreviewSamples.linkProgress.label)
        SomaLinkPendingRow(title: "Still learning", names: SomaPreviewSamples.pendingLinks) { _ in }
    }
    .padding()
}
