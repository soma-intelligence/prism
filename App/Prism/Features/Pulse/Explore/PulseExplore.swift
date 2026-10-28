//
//  PulseExplore.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// A piece opened from outside Explore, a score page say: a thin handle on a
/// bundled article, so those pages keep working whatever the library holds.
struct PulseArticle: Identifiable, Hashable, Sendable {
    let article: Article

    var id: String { article.id }
    var title: String { article.title }
    var minutes: Int { article.minutes }
}

/// The pieces other pages link to by name.
enum PulseArticles {
    static let heartRateVariability = PulseArticle(article: BundledArticles.heartRateVariability)
    static let deepSleep = PulseArticle(article: BundledArticles.deepSleep)
    static let caffeine = PulseArticle(article: BundledArticles.caffeine)
}

/// What the suggested reads are chosen from: two weeks of HRV and the last
/// couple of nights.
struct PulseExploreInputs: Sendable, Equatable {
    var now: Date
    var heartRateVariability: [HealthReading] = []
    var sleep: [HealthReading] = []

    static let metrics = [PulseInputs.Metric.heartRateVariability, PulseInputs.Metric.sleep]

    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> PulseExploreInputs {
        let today = calendar.startOfDay(for: now)
        let fortnight = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        let twoNights = calendar.date(byAdding: .day, value: -2, to: today) ?? today

        @Sendable func samples(_ identifier: String, from start: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        }
        async let variability = samples(PulseInputs.Metric.heartRateVariability, from: fortnight)
        async let sleep = samples(PulseInputs.Metric.sleep, from: twoNights)
        return PulseExploreInputs(now: now, heartRateVariability: await variability, sleep: await sleep)
    }
}

/// "Because of your week": the three suggested pieces, each with the reason it
/// is offered, written from real numbers when Health has them and a neutral
/// line when it does not.
struct PulseExploreWeek: Equatable {
    struct Suggestion: Equatable, Identifiable {
        var article: PulseArticle
        var reason: String
        var id: String { article.id }
    }

    var suggestions: [Suggestion]

    static func make(from inputs: PulseExploreInputs, calendar: Calendar = .current, locale: Locale = .current) -> PulseExploreWeek {
        let words = PulseWording(calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: inputs.now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        let thisWeek = inputs.heartRateVariability.filter { $0.start >= weekStart }.map(\.value)
        let before = inputs.heartRateVariability.filter { $0.start < weekStart }.map(\.value)
        let hrvReason: String
        if let week = PulseTrends.mean(thisWeek) {
            if let earlier = PulseTrends.mean(before), earlier > 0 {
                let share = (week - earlier) / earlier
                if share <= -PulseTrends.steadyShare {
                    hrvReason = "Your HRV dipped to \(words.whole(week)) this week."
                } else if share >= PulseTrends.steadyShare {
                    hrvReason = "Your HRV rose to \(words.whole(week)) this week."
                } else {
                    hrvReason = "Your HRV held near \(words.whole(week)) this week."
                }
            } else {
                hrvReason = "Your HRV averaged \(words.whole(week)) this week."
            }
        } else {
            hrvReason = "What the number means, and why it swings."
        }

        let lastNight = PulseNights.nights(from: inputs.sleep, calendar: calendar).last { $0.day == today }
        let sleepReason: String
        if let lastNight, let deep = lastNight.deep {
            sleepReason = "Last night held \(words.span(deep)) of deep sleep."
        } else if let lastNight {
            sleepReason = "You slept \(words.duration(lastNight.asleep)) last night."
        } else {
            sleepReason = "Why the first hours of the night matter most."
        }

        return PulseExploreWeek(suggestions: [
            Suggestion(article: PulseArticles.heartRateVariability, reason: hrvReason),
            Suggestion(article: PulseArticles.deepSleep, reason: sleepReason),
            Suggestion(article: PulseArticles.caffeine, reason: "When the last coffee of the day still counts."),
        ])
    }
}
