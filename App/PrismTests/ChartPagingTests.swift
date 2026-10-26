//
//  ChartPagingTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

@Suite("Paged charts: whole spans, round scales, totals counted once")
struct ChartPagingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 14))! }

    @Test("Every span pages back in whole spans, edge to edge, the last ending now", arguments: VaultPeriod.allCases)
    func pagesAreWhole(period: VaultPeriod) {
        let earliest = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))!
        let pages = period.pages(from: earliest, now: now, calendar: calendar)
        #expect(pages.last == period.interval(endingAt: now, calendar: calendar))
        #expect(pages.first!.start <= earliest)
        for (older, newer) in zip(pages, pages.dropFirst()) {
            #expect(older.end == newer.start)
        }
        // Each page is one whole span: the span ending at its own end.
        for page in pages where period != .day {
            let step: (Calendar.Component, Int) = switch period {
            case .day: (.day, 1)
            case .week: (.day, 7)
            case .month: (.month, 1)
            case .threeMonths: (.weekOfYear, 13)
            case .sixMonths: (.weekOfYear, 26)
            case .year: (.month, 12)
            }
            let expectedStart = calendar.date(byAdding: step.0, value: -step.1, to: page.end)!
            // Month lengths differ, so a month back from the end is the start
            // to within the clamp of a short month.
            #expect(abs(page.start.timeIntervalSince(expectedStart)) <= 3 * 86_400)
        }
        if period == .day {
            #expect(pages.allSatisfy { $0.duration == 86_400 })
        }
        if period == .week {
            #expect(pages.allSatisfy { $0.duration == 7 * 86_400 })
            #expect(pages.last!.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 18)))
            #expect(pages[pages.count - 2].start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        }
    }

    @Test("A scale's top lands on a round gridline close above the data")
    func niceScale() {
        let steps = MetricDetailMath.niceDomain(0...10_627, ceiling: nil)
        #expect(steps == 0...12_000)
        #expect(MetricDetailMath.niceTicks(steps) == [0, 2_000, 4_000, 6_000, 8_000, 10_000, 12_000])
        // A quiet week no longer borrows a year's outlier: the scale is the
        // week's own.
        #expect(MetricDetailMath.niceDomain(0...4_300, ceiling: nil).upperBound <= 5_000)
        // A percentage never runs past its ceiling.
        #expect(MetricDetailMath.niceDomain(90...99.4, ceiling: 100).upperBound <= 100)
        // A domain off zero keeps its foot off zero.
        #expect(MetricDetailMath.niceDomain(52...63, ceiling: nil).lowerBound >= 50)
    }

    @Test("A day of overlapping phone and watch steps counts the walk once")
    func overlappingStepsCountOnce() {
        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        func reading(_ hour: Double, _ minutes: Double, _ value: Double, watch: Bool) -> HealthReading {
            let start = day.addingTimeInterval(hour * 3600)
            return HealthReading(
                metric: "HKQuantityTypeIdentifierStepCount", value: value, unit: .count,
                start: start, end: start.addingTimeInterval(minutes * 60),
                source: watch ? "Apple Watch" : "iPhone", device: watch ? "Apple Watch" : nil
            )
        }
        // The phone counts 1,000 steps an hour from 8 to 18; the watch,
        // worn 9 to 13, counts 1,100 an hour over the same walks.
        let phone = (8..<18).map { reading(Double($0), 60, 1_000, watch: false) }
        let watch = (9..<13).map { reading(Double($0), 60, 1_100, watch: true) }
        let naive = (phone + watch).map(\.value).reduce(0, +)
        let total = CumulativeTotal.deduplicated(phone + watch, from: day, to: end) { $0.device == "Apple Watch" ? 0 : 1 }
        #expect(naive == 14_400)
        // Four watch hours, and the phone's six hours the watch did not cover.
        #expect(total == 4 * 1_100 + 6 * 1_000)

        // A phone sample half under the watch counts its other half.
        let half = CumulativeTotal.deduplicated(
            [reading(9, 60, 1_100, watch: true), reading(9.5, 60, 1_000, watch: false)], from: day, to: end
        ) { $0.device == "Apple Watch" ? 0 : 1 }
        #expect(half == 1_100 + 500)
    }

    @Test("The simulator's fixture counts an overlapping day once")
    func fixtureTotalsDeduplicate() async throws {
        let source = FixtureHealthSource(now: now, calendar: calendar)
        let metric = try #require(HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierStepCount"))
        let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let total = try await source.total(metric, from: day, to: end)?.value ?? 0
        let samples = try await source.samples(metric, from: day, to: end, limit: 0)
            .filter { $0.start >= day && $0.start < end }
        // One phone, no overlap: the total is the plain sum, and a day is
        // thousands of steps, never tens of thousands.
        #expect(abs(total - samples.map(\.value).reduce(0, +)) < 0.001)
        #expect(total < 20_000)
    }
}
