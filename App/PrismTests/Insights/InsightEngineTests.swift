//
//  InsightEngineTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

@Suite("Insight engine")
struct InsightEngineTests {
    /// Sixty steady days of `value`, wobbling by `wobble`, then `recent`.
    private func days(_ value: Double, wobble: Double = 0, count: Int = 60, then recent: [Double?]) -> [Double?] {
        (0..<count).map { value + ($0.isMultiple(of: 2) ? wobble : -wobble) } + recent
    }

    @Test("The usual is the median of the days before the last week, the band at least the metric's floor")
    func usualAndBand() {
        let insight = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 55, 55, 55, 55, 55, 55]))
        #expect(insight.usual == 55)
        #expect(insight.band == 53...57)
        #expect(insight.position == .within)
        #expect(insight.cue == nil)
        #expect(insight.direction == .steady)
    }

    @Test("The band widens with the median absolute deviation")
    func madBand() {
        let insight = InsightEngine.interpret(.restingHeartRate, days: days(55, wobble: 4, then: Array(repeating: 55, count: 7)))
        // Every day is 4 off the median of 55: MAD 4, spread 4 x 1.4826.
        let half = 4 * InsightEngine.madScale
        #expect(abs((insight.band?.upperBound ?? 0) - (55 + half)) < 0.0001)
    }

    @Test("The last week stays out of the usual")
    func lastWeekExcluded() {
        let insight = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [80, 80, 80, 80, 80, 80, 80]))
        #expect(insight.usual == 55)
        #expect(insight.position == .above)
    }

    @Test("Too little history gives no usual, and the cue says it is being learned")
    func learning() {
        let insight = InsightEngine.interpret(.heartRateVariability, days: [nil, nil, 50, 52, 51])
        #expect(insight.usual == nil)
        #expect(insight.position == nil)
        #expect(insight.cue == "Usual range after 12 days")
    }

    @Test("Nothing measured says nothing and weighs nothing")
    func empty() {
        let insight = InsightEngine.interpret(.bloodGlucose, days: Array(repeating: nil, count: 90))
        #expect(insight.cue == nil)
        #expect(insight.severity == 0)
        #expect(insight.current == nil)
    }

    @Test("Below the usual reads in percent, and for a higher is better metric it is one to watch")
    func underUsual() {
        let insight = InsightEngine.interpret(.heartRateVariability, days: days(50, then: [50, 50, 50, 50, 39, 41, 40]))
        #expect(insight.position == .below)
        #expect(insight.percent.map { $0.rounded() } == -20)
        #expect(insight.cue == "20% under usual")
        #expect(insight.tone == .watch)
        #expect(insight.higherIsBetter == true)
    }

    @Test("Above the usual is good news when higher is better, to watch when lower is")
    func toneFollowsPreference() {
        let hrv = InsightEngine.interpret(.heartRateVariability, days: days(50, then: [50, 50, 50, 50, 60, 61, 62]))
        #expect(hrv.tone == .good)
        let resting = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 55, 55, 55, 62, 63, 62]))
        #expect(resting.tone == .watch)
        let temperature = InsightEngine.interpret(.wristTemperature, days: days(36, then: [36, 36, 36, 36, 36.8, 36.9, 36.8]))
        #expect(temperature.tone == .watch)
        #expect(temperature.higherIsBetter == nil)
    }

    @Test("A temperature says over the usual without a percent")
    func temperatureCue() {
        let insight = InsightEngine.interpret(.wristTemperature, days: days(36, then: [36, 36, 36, 36, 36.8, 36.9, 36.8]))
        #expect(insight.cue == "Over your usual")
    }

    @Test("The newest reading at the top of the month reads as the highest in 30 days")
    func highest() {
        let insight = InsightEngine.interpret(.restingHeartRate, days: days(55, wobble: 1, then: [55, 56, 55, 54, 55, 58, 64]))
        #expect(insight.position == .above)
        #expect(insight.cue == "Highest in 30 days")
    }

    @Test("Three days in a row the same way, outside the usual, reads as a run")
    func run() {
        // Rising every day but never above the month's peak of 70 (day 40).
        var series = days(55, then: [])
        series[40] = 70
        series += [55, 55, 55, 57, 59, 61, 63]
        let insight = InsightEngine.interpret(.restingHeartRate, days: series)
        #expect(insight.position == .above)
        #expect(insight.cue == "4 days rising")
    }

    @Test("Within the usual after days outside it reads as back in range")
    func backInRange() {
        let insight = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [62, 63, 62, 62, 55, 55, 55]))
        #expect(insight.position == .within)
        #expect(insight.cue == "Back in range")
        #expect(insight.tone == .good)
    }

    @Test("A month moving past the metric's step reads as a direction")
    func direction() {
        let rising = (0..<30).map { Optional(70 + Double($0) * 0.1) }
        let insight = InsightEngine.interpret(.weight, days: rising)
        #expect(insight.direction == .rising)
        #expect(abs((insight.change ?? 0) - 2.9) < 0.0001)
        let flat = (0..<30).map { Optional(70 + ($0.isMultiple(of: 2) ? 0.1 : -0.1)) }
        #expect(InsightEngine.interpret(.weight, days: flat).direction == .steady)
    }

    @Test("One odd reading does not tilt the direction")
    func robustDirection() {
        var series: [Double?] = Array(repeating: 55, count: 30)
        series[29] = 90
        #expect(InsightEngine.interpret(.restingHeartRate, days: series).direction == .steady)
    }

    @Test("Steps leave out today, which is still adding up")
    func partialToday() {
        let series = days(8000, wobble: 500, then: [8000, 8000, 8000, 8000, 8000, 8000, 300])
        let insight = InsightEngine.interpret(.steps, days: series)
        #expect(insight.position == .within)
        #expect(insight.current == 8000)
        #expect(insight.currentAge == 1)
    }

    @Test("Severity grows with distance from the usual and stays in 0 to 1")
    func severity() {
        let near = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 55, 55, 55, 56, 56, 56]))
        let far = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 55, 55, 55, 61, 61, 61]))
        let farther = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 55, 55, 55, 75, 75, 75]))
        #expect(near.severity < far.severity)
        #expect(far.severity < farther.severity)
        #expect((0...1).contains(farther.severity))
    }

    @Test("A stale reading weighs less than a fresh one")
    func freshness() {
        let fresh = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 55, 55, 55, 61, 61, 61]))
        let stale = InsightEngine.interpret(.restingHeartRate, days: days(55, then: [55, 61, 61, nil, nil, nil, nil]))
        #expect(stale.currentAge == 4)
        #expect(stale.severity < fresh.severity)
    }

    @Test("Ranking keeps three to five, highest first, the given order among equals")
    func ranking() {
        func insight(_ severity: Double) -> Insight {
            var insight = Insight.empty(.higher)
            insight.severity = severity
            insight.current = 1
            return insight
        }
        let items: [(key: String, insight: Insight)] = [
            ("a", insight(0.1)), ("b", insight(0.9)), ("c", insight(0.5)), ("d", insight(0.5)),
            ("e", insight(0.4)), ("f", insight(0.35)), ("g", insight(0.7)),
        ]
        #expect(InsightEngine.ranked(items).map(\.key) == ["b", "g", "c", "d", "e"])

        let quiet: [(key: String, insight: Insight)] = [("a", insight(0.1)), ("b", insight(0.2)), ("c", insight(0.05)), ("d", insight(0.0))]
        #expect(InsightEngine.ranked(quiet).map(\.key) == ["b", "a", "c"])
    }

    @Test("Sorting by severity is stable among equals")
    func stableSort() {
        let sorted = InsightEngine.sortedBySeverity([("a", 0.0), ("b", 0.5), ("c", 0.0), ("d", 0.5)]) { $0.1 }
        #expect(sorted.map(\.0) == ["b", "d", "a", "c"])
    }

    @Test("Cues stay short labels: six words at most, no full stop")
    func cuesAreShort() {
        let series: [[Double?]] = [
            days(55, then: [55, 55, 55, 55, 61, 61, 61]),
            days(55, then: [62, 63, 62, 62, 55, 55, 55]),
            days(55, wobble: 1, then: [55, 56, 55, 54, 55, 58, 64]),
            [nil, 50, 52],
            (0..<30).map { Optional(70 + Double($0) * 0.1) },
        ]
        for metric in InsightMetric.allCases {
            for days in series {
                guard let cue = InsightEngine.interpret(metric, days: days).cue else { continue }
                #expect(cue.split(separator: " ").count <= 6, "\(cue)")
                #expect(!cue.hasSuffix("."), "\(cue)")
            }
        }
    }

    @Test("Every metric names a type the catalog knows, and Body maps onto every quantity")
    func catalog() {
        for metric in InsightMetric.allCases {
            #expect(HealthMetricCatalog.metric(for: metric.identifier) != nil, "\(metric.identifier)")
            if metric != .sleepDuration {
                #expect(BodyBiomarkerSpec(metric)?.identifier == metric.identifier, "\(metric)")
            }
        }
        #expect(BodyBiomarkerSpec(.sleepDuration) == nil)
    }

    @Test("Body composition says by how much it moved, not the direction its status already names")
    func bodyCue() {
        let rising = (0..<6).map { Optional(70 + Double($0) * 0.5) }
        let insight = InsightEngine.interpret(.weight, days: rising)
        #expect(insight.cueKind == .trend)
        #expect(BodyBiomarkers.cue(.bodyMass, insight: insight) == "Up 2.5 kg in 30 days")
    }

    @Test("Today ranks what moved from every metric")
    func pulseMoved() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func reading(_ value: Double, daysAgo: Int) -> HealthReading {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            return HealthReading(metric: "x", value: value, unit: .countPerMinute, start: date, end: date)
        }
        let resting = (0..<90).map { reading($0 < 3 ? 70 : 55, daysAgo: $0) }
        let variability = (0..<90).map { reading(50, daysAgo: $0) }
        let sleep: [Double?] = Array(repeating: 7.5, count: 90)
        let insights = PulseInsights.make(
            readings: [.restingHeartRate: resting, .heartRateVariabilitySDNN: variability],
            sleepHours: sleep, now: now, calendar: calendar
        )
        #expect(insights.items.count == InsightMetric.allCases.count)
        #expect(insights.moved.first?.metric == .restingHeartRate)
        #expect(insights.moved.count == 3)
        #expect(insights[.sleepDuration]?.value == "7:30")
    }

    @Test("A move with a time reads the time as its hero")
    func moveWords() {
        let bed = PulseToday.Move(aspect: .sleep, title: "In bed by 11:00 PM", reason: "")
        #expect(bed.words.lead == "In bed by")
        #expect(bed.words.hero == "11:00 PM")
        let walk = PulseToday.Move(aspect: .activity, title: "Walk for 15 minutes", reason: "")
        #expect(walk.words.lead == nil)
        #expect(walk.words.hero == "Walk for 15 minutes")
    }

}
