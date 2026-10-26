//
//  MetricDetailTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

@Suite("Metric detail page math")
struct MetricDetailTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))! }

    @Test("Gaps fill on a straight line; the ends take the nearest value")
    func interpolation() {
        #expect(MetricDetailMath.interpolated([nil, 2, nil, 4, nil]) == [2, 2, 3, 4, 4])
        #expect(MetricDetailMath.interpolated([nil, nil]).isEmpty)
    }

    @Test("The rolling band is the mean give or take at least 3 percent")
    func rollingBand() {
        let band = MetricDetailMath.rollingBand(Array(repeating: 100, count: 20))
        #expect(band.lower.last == 97)
        #expect(band.upper.last == 103)
        // The warm up keeps the first full window's width.
        #expect(band.upper[0] - band.lower[0] == 6)
    }

    @Test("A metric with a reference band reads against it, the rest against the rolling band")
    func standing() {
        let resting = MetricProfile.of("HKQuantityTypeIdentifierRestingHeartRate")
        let high = MetricDetailMath.standing(Array(repeating: 60, count: 20) + [72], profile: resting)
        #expect(high.status == .above)
        #expect(high.band == 50...70)
        #expect(high.isReference)
        let inside = MetricDetailMath.standing(Array(repeating: 60, count: 20), profile: resting)
        #expect(inside.status == .normal(reference: true))

        let hrv = MetricProfile.of("HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        let personal = MetricDetailMath.standing(Array(repeating: 50, count: 20), profile: hrv)
        #expect(personal.status == .normal(reference: false))
        #expect(MetricDetailMath.standing([50, 51], profile: hrv).status == .none)
    }

    @Test("A daily total on an open day reads its direction, never a verdict")
    func openDay() {
        let steps = MetricProfile.of("HKQuantityTypeIdentifierStepCount")
        let days: [Double?] = (0..<20).map { 5000 + Double($0) * 300 } + [800]
        let standing = MetricDetailMath.standing(days, profile: steps, todayOpen: true)
        #expect(standing.status == .direction(.rising))
    }

    @Test("Trend rows compare the latest with N days ago, and only where history reaches")
    func trendRows() {
        let days: [Double?] = (0..<40).map { Double($0) }
        let rows = MetricDetailMath.trendRows(days, risingIsGood: true)
        #expect(rows.map(\.days) == [3, 7, 14, 30])
        #expect(rows.first?.change == 3)
        #expect(rows.first?.verdict == "Improving")
        #expect(rows.last?.spark.count == 8)
        let worse = MetricDetailMath.trendRows(days, risingIsGood: false)
        #expect(worse.first?.verdict == "Worsening")
        let neutral = MetricDetailMath.trendRows(Array(repeating: 5, count: 10), risingIsGood: nil)
        #expect(neutral.first?.verdict == "Stable")
    }

    @Test("The open day is left out of the changes")
    func trendOpenDay() {
        let days: [Double?] = Array(repeating: 8000, count: 20) + [500]
        let rows = MetricDetailMath.trendRows(days, risingIsGood: true, openDayTail: 1)
        #expect(rows.allSatisfy { $0.change == 0 })
    }

    @Test("Projections need five readings over two weeks and a fit that holds")
    func projections() {
        var weight: [Double?] = Array(repeating: nil, count: 60)
        for index in stride(from: 0, to: 60, by: 5) { weight[index] = 80 - Double(index) * 0.05 }
        let rows = MetricDetailMath.projections(weight)
        #expect(rows.map(\.days) == [7, 30, 90])
        #expect(rows.first?.direction == .falling)
        #expect((rows.last?.margin ?? 0) >= (rows.first?.margin ?? 0))

        let short: [Double?] = [80, 80.1, 80, 79.9]
        #expect(MetricDetailMath.projections(short).isEmpty)
        let noise: [Double?] = (0..<30).map { $0.isMultiple(of: 2) ? 80 : 82 }
        #expect(MetricDetailMath.projections(noise).isEmpty)
    }

    @Test("Buckets average the days they hold, with the band over them")
    func buckets() {
        let days: [Double?] = (0..<14).map { Double($0) }
        let master = MetricMaster(today: today, days: days)
        let band = MetricDetailMath.Band(lower: Array(repeating: 1, count: 14), upper: Array(repeating: 3, count: 14), isReference: true)
        let intervals = VaultPeriod.week.buckets(endingAt: today, calendar: calendar)
        let buckets = MetricDetailMath.buckets(master, band: band, intervals: intervals, calendar: calendar)
        #expect(buckets.count == 7)
        #expect(buckets.last?.value == 13)
        #expect(buckets.first?.value == 7)
        #expect(buckets.first?.band == 1...3)

        let weeks = MetricDetailMath.buckets(master, band: nil, intervals: VaultPeriod.threeMonths.buckets(endingAt: today, calendar: calendar), calendar: calendar)
        // The week from Monday 28 September holds 28 Sep to 3 Oct: days 7 to 13.
        #expect(weeks.last?.value == 10.5)
    }

    @Test("The scale holds the band, keeps room, and respects a ceiling")
    func domain() {
        let domain = MetricDetailMath.domain(values: [96, 97, 98], bands: [95...100], ceiling: 100, zeroBased: false)
        #expect(domain.lowerBound <= 95)
        #expect(domain.upperBound == 100)
        let bars = MetricDetailMath.domain(values: [4000, 9000], bands: [], ceiling: nil, zeroBased: true)
        #expect(bars.lowerBound == 0)
    }

    @Test("Stats are min, mean and max of the buckets that hold a value")
    func stats() {
        let stats = MetricDetailMath.stats([1, nil, 3, 5])
        #expect(stats == MetricDetailMath.Stats(minimum: 1, average: 3, maximum: 5))
        #expect(MetricDetailMath.stats([nil]) == nil)
    }

    @Test("Sources are grouped by app and device, most records first, with the best grade")
    func origins() {
        func reading(_ source: String, device: String?, typed: Bool = false) -> HealthReading {
            HealthReading(metric: "HKQuantityTypeIdentifierHeartRate", value: 60, unit: .countPerMinute, start: today, end: today,
                          source: source, sourceBundle: nil, device: device, deviceModel: nil, wasUserEntered: typed)
        }
        let origins = VaultMasterReader.origins([
            reading("Watch", device: "Apple Watch"), reading("Watch", device: "Apple Watch"), reading("Health", device: nil, typed: true),
        ])
        #expect(origins.map(\.name) == ["Watch", "Health"])
        #expect(origins.first?.count == 2)
        #expect(origins.last?.quality.level == .manual)
    }

    @Test("One table: every interpreted metric and every score has a profile, and the engine reads the same preference")
    func table() {
        for metric in InsightMetric.allCases {
            let profile = MetricProfile.of(metric)
            #expect(profile.policy != nil, "\(metric)")
            let expected: InsightPreference = switch profile.risingIsGood {
            case true: .higher
            case false: .lower
            default: .steady
            }
            #expect(metric.policy.preference == expected, "\(metric)")
        }
        for score in ScoreMetric.allCases {
            #expect(MetricProfile.table[score.identifier] != nil, "\(score)")
        }
        #expect(MetricProfile.of("HKQuantityTypeIdentifierActiveEnergyBurned").accumulates)
    }
}
