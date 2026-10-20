//
//  SomaPreviewSamples+Articles.swift
//  SomaUIPreviewSupport
//

import SomaUI

/// A few articles as the library shows them, one per calm tone.
public extension SomaPreviewSamples {
    struct ArticleSample: Identifiable, Sendable {
        public var id: String { seed }
        public let title: String
        public let topic: String
        public let caption: String
        public let reason: String?
        public let tone: SomaTrackTone
        public let mark: SomaArticleCover.Mark
        public let seed: String
    }

    static let articles: [ArticleSample] = [
        ArticleSample(title: "Why a steady bedtime matters", topic: "Sleep", caption: "4 min",
                      reason: "Because your sleep was short this week", tone: .dusk, mark: .aspect(.sleep), seed: "sleep-regularity"),
        ArticleSample(title: "Reading your resting heart rate", topic: "Heart", caption: "3 min",
                      reason: "Because your resting heart rate is up", tone: .rose, mark: .aspect(.heart), seed: "resting-heart-rate"),
        ArticleSample(title: "What your HRV is telling you", topic: "Recovery", caption: "4 min",
                      reason: "Because you check your recovery often", tone: .tide, mark: .track(.hrv), seed: "hrv-basics"),
        ArticleSample(title: "Zone 2, the easy pace that builds", topic: "Movement", caption: "4 min",
                      reason: nil, tone: .moss, mark: .aspect(.activity), seed: "zone-2"),
        ArticleSample(title: "Fibre and the gut", topic: "Nutrition", caption: "5 min",
                      reason: nil, tone: .sand, mark: .aspect(.gut), seed: "fibre"),
        ArticleSample(title: "A few slow breaths", topic: "Mind", caption: "3 min",
                      reason: nil, tone: .sage, mark: .aspect(.mind), seed: "breathing"),
        ArticleSample(title: "Strength as you age", topic: "Longevity", caption: "4 min",
                      reason: nil, tone: .clay, mark: .aspect(.body), seed: "strength"),
    ]
}
