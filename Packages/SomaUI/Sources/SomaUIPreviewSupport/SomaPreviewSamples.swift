//
//  SomaPreviewSamples.swift
//  SomaUIPreviewSupport
//

import SwiftUI
import SomaUI

/// Shared sample data for every `#Preview` and for the component gallery.
///
/// Components never carry their own fixtures: they all draw from here, so one
/// edit re-feeds the whole catalog. This target is never linked into a release
/// surface.
public enum SomaPreviewSamples {
    /// Glass needs content behind it to refract, but a backdrop must not compete
    /// with the accent: the canvas token plus two muted orbs.
    public static func backdrop(_ theme: SomaTheme = .standard) -> some View {
        ZStack {
            theme.colors.canvas.color

            Circle()
                .fill(.primary.opacity(0.06))
                .frame(width: 260)
                .blur(radius: 40)
                .offset(x: -70, y: -120)

            Circle()
                .fill(.primary.opacity(0.09))
                .frame(width: 200)
                .blur(radius: 30)
                .offset(x: 90, y: 60)
        }
        .ignoresSafeArea()
    }

    /// One line of a browse list, for the gallery and for any preview that
    /// needs a list to put on screen.
    public struct BrowseItem: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let detail: String?

        public init(_ id: String, symbol: String, detail: String? = nil) {
            self.id = id
            self.symbol = symbol
            self.detail = detail
        }
    }

    /// The categories a health app browses by.
    public static let browseCategories: [BrowseItem] = [
        BrowseItem("Activity", symbol: "flame.fill"),
        BrowseItem("Body Measurements", symbol: "figure.arms.open"),
        BrowseItem("Heart", symbol: "heart.fill"),
        BrowseItem("Sleep", symbol: "bed.double.fill"),
    ]

    /// Readings inside one category, each stating a value.
    public static let browseReadings: [BrowseItem] = [
        BrowseItem("Resting Heart Rate", symbol: "heart", detail: "58 bpm"),
        BrowseItem("Heart Rate Variability", symbol: "waveform.path.ecg", detail: "42 ms"),
        BrowseItem("Cardio Fitness", symbol: "figure.run", detail: "-"),
    ]

    /// The parts a page offers in its top bar's segmented control.
    public static let segments: [SomaSegment<String>] = [
        SomaSegment(id: "today", title: "Today"),
        SomaSegment(id: "trends", title: "Trends"),
        SomaSegment(id: "explore", title: "Explore"),
    ]

    /// A camera's modes, for a mode strip that selects one.
    public static let modes: [SomaModeStrip<String>.Item] = [
        .init(id: "knock", title: "Knock"),
        .init(id: "jumps", title: "Jumps"),
    ]

    /// Conditions marked during a recording, for a mode strip that selects several.
    public static let conditions: [SomaModeStrip<String>.Item] = [
        .init(id: "rest", title: "rest"),
        .init(id: "talking", title: "talking"),
        .init(id: "head_motion", title: "head motion"),
        .init(id: "low_light", title: "low light"),
        .init(id: "changing_light", title: "changing light"),
    ]

    /// The move written on the orb of each aspect that has one.
    public static let orbLabels: [SomaAspect: LocalizedStringResource] = [
        .mind: "Slow down",
        .sleep: "Wind down",
        .activity: "Move now",
    ]

    /// The row of values under the orb: one that rose, one that fell, one
    /// not measured.
    public static let scores: [SomaScore] = [
        SomaScore(aspect: .sleep, value: "7:12", trend: .up),
        SomaScore(aspect: .mind, value: "38", unit: "ms", trend: .down),
        SomaScore(aspect: .activity, value: nil, unit: "min"),
    ]

    /// One next move, for a list of them.
    public struct Move: Identifiable, Sendable {
        public let aspect: SomaAspect
        public let title: String
        public let reason: String
        public var id: SomaAspect { aspect }
    }

    public static let moves: [Move] = [
        Move(aspect: .mind, title: "Breathe for 10 minutes",
             reason: "Slow breathing can bring your HRV back toward your usual 48 ms."),
        Move(aspect: .sleep, title: "In bed by 23:00",
             reason: "Your longest nights this month started before 23:30."),
    ]

    /// Today's energy level, as a share of the bank.
    public static let energyLevel = 0.42

    /// A record's grade on each step of the four mark scale, best first.
    public static let qualityGrades = [4, 3, 2, 1, 0]

    /// A day so far, from waking to now.
    public static let day: [SomaTimelineEvent] = [
        SomaTimelineEvent(id: "wake", time: "07:16", title: "Woke up",
                          detail: "Slept 7:12, 68 min of deep sleep.", aspect: .sleep),
        SomaTimelineEvent(id: "walk", time: "12:05", title: "Walk",
                          detail: "35 min, 3,900 steps.", aspect: .activity),
        SomaTimelineEvent(id: "peak", time: "14:30", title: "Stress peak",
                          detail: "Heart at 104 while still, 49 above resting.", aspect: .mind),
        SomaTimelineEvent(id: "now", time: "19:46", title: "Now",
                          detail: "3,900 steps and 42 min of exercise so far.", isNow: true),
    ]

    /// Hours asleep over a week, the last night missing one value earlier on.
    public static let nights: [Double?] = [6.7, 6.9, 5.8, nil, 7.4, 7.7, 7.2]

    /// Resting heart rate over two weeks, and the band that is usual for it.
    public static let restingHeart: [Double?] = [58, 57, 59, nil, 58, 56, 57, 58, 59, 57, 56, 57, 55, 54]
    public static let restingBand: ClosedRange<Double> = 56...58

    /// The words of one aspect card.
    public struct AspectCard: Identifiable, Sendable {
        public let aspect: SomaAspect
        public let value: String?
        public let unit: String
        public let summary: String
        public var id: SomaAspect { aspect }
    }

    public static let aspectCards: [AspectCard] = [
        AspectCard(aspect: .sleep, value: "7:12", unit: "asleep",
                   summary: "Your longest night this week, 68 min deep."),
        AspectCard(aspect: .heart, value: "54", unit: "bpm resting",
                   summary: "4 below your usual, lowest at 03:40 last night."),
        AspectCard(aspect: .body, value: "41", unit: "fitness age, ± 3",
                   summary: "From 6 Soma visits. You are 46."),
    ]

    /// A fitness age on its track: the estimate, the span it may be off by,
    /// and the age it is read against.
    public static let fitnessAge = (estimate: 41.0, spread: 3.0, age: 46.0)

    /// Every aspect's identity hue, for the gallery's swatch strip.
    public static func aspectHues(_ theme: SomaTheme) -> [(name: String, color: Color)] {
        SomaAspect.allCases.map { ($0.rawValue, theme.aspects[$0].identity.color) }
    }

    /// Every colour role the theme carries, for the gallery's swatch strip.
    ///
    /// A function of the theme rather than a constant: a theme copied with a
    /// different accent shows its own swatches, not the shipped theme's.
    public static func colourRoles(_ theme: SomaTheme) -> [(name: String, color: Color)] {
        [
            ("canvas", theme.colors.canvas.color),
            ("surface", theme.colors.surface.color),
            ("surfaceRecessed", theme.colors.surfaceRecessed.color),
            ("accent", theme.colors.accent.color),
            ("onAccent", theme.colors.onAccent.color),
            ("inkPrimary", theme.colors.inkPrimary.color),
            ("inkSecondary", theme.colors.inkSecondary.color),
            ("danger", theme.colors.danger.color),
            ("record", theme.colors.record.color),
        ]
    }
}
