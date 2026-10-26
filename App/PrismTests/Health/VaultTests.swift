//
//  VaultTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The quality grader's rules, in the order they decide.
@Suite("Reading quality")
struct ReadingQualityTests {
    private let heartRate = "HKQuantityTypeIdentifierHeartRate"
    private let steps = "HKQuantityTypeIdentifierStepCount"

    private func grade(
        _ metric: String,
        device: String? = nil,
        model: String? = nil,
        source: String? = nil,
        entered: Bool = false
    ) -> ReadingQuality {
        ReadingQuality.grade(metric: metric, device: device, deviceModel: model, source: source, wasUserEntered: entered)
    }

    @Test("Typed in beats every device")
    func manualWins() {
        let quality = grade(heartRate, device: "Polar H10", entered: true)
        #expect(quality.level == .manual)
        #expect(quality.reason == "Entered by hand")
    }

    @Test("A metric a model works out is estimated, whatever wrote it")
    func derivedIsEstimated() {
        #expect(grade("HKQuantityTypeIdentifierVO2Max", device: "Apple Watch").level == .estimated)
        #expect(grade("HKQuantityTypeIdentifierActiveEnergyBurned", device: "Apple Watch").level == .estimated)
    }

    @Test("A chest strap on heart rate is the reference, off it a sensor")
    func chestStrap() {
        #expect(grade(heartRate, device: "Polar H10").level == .reference)
        #expect(grade(heartRate, model: "HRM-Pro Garmin").level == .reference)
        #expect(grade(heartRate, source: "Wahoo TICKR").level == .reference)
        #expect(grade(steps, device: "Polar H10").level == .sensor)
    }

    @Test("A cuff is the reference on blood pressure")
    func cuff() {
        #expect(grade("HKQuantityTypeIdentifierBloodPressureSystolic", device: "Withings BPM Connect").level == .reference)
        #expect(grade("HKQuantityTypeIdentifierBloodPressureSystolic", source: "OMRON connect").level == .reference)
    }

    @Test("Watches, rings and scales are sensors")
    func sensors() {
        #expect(grade(heartRate, device: "Ada's Apple Watch", model: "Watch Apple Inc.") == ReadingQuality(level: .sensor, reason: "Wrist sensor"))
        #expect(grade(heartRate, device: "Oura Ring") == ReadingQuality(level: .sensor, reason: "Ring"))
        #expect(grade(heartRate, source: "Ultrahuman") == ReadingQuality(level: .sensor, reason: "Ring"))
        #expect(grade("HKQuantityTypeIdentifierBodyMass", device: "Withings Body+") == ReadingQuality(level: .sensor, reason: "Scale"))
    }

    @Test("A renamed watch still matches on its model")
    func renamedWatch() {
        #expect(grade(heartRate, device: "My wrist", model: "Watch Apple Inc.").level == .sensor)
    }

    @Test("A phone infers, so it estimates")
    func phone() {
        #expect(grade(steps, device: "iPhone", model: "iPhone Apple Inc.").level == .estimated)
    }

    @Test("Nothing recognised is unknown, with no marks")
    func unknown() {
        let quality = grade(heartRate, source: "Some App")
        #expect(quality.level == .unknown)
        #expect(quality.level.marks == 0)
        #expect(grade(heartRate).level == .unknown)
    }

    @Test("The levels order from unknown to reference, one mark each")
    func ordering() {
        #expect(ReadingQuality.Level.allCases.sorted() == [.unknown, .manual, .estimated, .sensor, .reference])
        #expect(ReadingQuality.Level.reference.marks == ReadingQuality.scale)
    }

    @Test("A reading carries its provenance into the grade")
    func gradesReading() {
        let reading = HealthReading(metric: heartRate, value: 60, unit: .countPerMinute, start: .now, end: .now,
                                    source: "Polar Beat", device: "Polar H10", wasUserEntered: false)
        #expect(ReadingQuality.grade(reading).level == .reference)
    }
}

/// The period spans and their buckets, read against a fixed calendar so a
/// daylight saving change or a locale never moves the answer.
@Suite("Vault periods")
struct VaultPeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Friday 3 October 2026, 14:30 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 14, minute: 30))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("A day is today, hour by hour")
    func day() {
        let buckets = VaultPeriod.day.buckets(endingAt: now, calendar: calendar)
        #expect(buckets.count == 24)
        #expect(buckets.first?.start == date(2026, 10, 3))
        #expect(buckets.last?.end == date(2026, 10, 4))
    }

    @Test("A week is the last seven days, ending with today")
    func week() {
        let buckets = VaultPeriod.week.buckets(endingAt: now, calendar: calendar)
        #expect(buckets.count == 7)
        #expect(buckets.first?.start == date(2026, 9, 27))
        #expect(buckets.last?.start == date(2026, 10, 3))
    }

    @Test("A month runs day by day back one calendar month")
    func month() {
        let buckets = VaultPeriod.month.buckets(endingAt: now, calendar: calendar)
        #expect(buckets.count == 30)
        #expect(buckets.first?.start == date(2026, 9, 4))
        #expect(buckets.last?.end == date(2026, 10, 4))
    }

    @Test("Six months is twenty six weeks, ending with this week")
    func sixMonths() {
        let buckets = VaultPeriod.sixMonths.buckets(endingAt: now, calendar: calendar)
        #expect(buckets.count == 26)
        // The week holding Friday 3 October starts on Monday 28 September.
        #expect(buckets.last?.start == date(2026, 9, 28))
        #expect(buckets.allSatisfy { $0.duration == 7 * 86_400 })
    }

    @Test("Three months is thirteen weeks, ending with this week")
    func threeMonths() {
        let buckets = VaultPeriod.threeMonths.buckets(endingAt: now, calendar: calendar)
        #expect(buckets.count == 13)
        #expect(buckets.last?.start == date(2026, 9, 28))
    }

    @Test("Paging moves back whole spans")
    func paging() {
        #expect(VaultPeriod.week.shifted(now, by: 1, calendar: calendar) == date(2026, 9, 26, 14).addingTimeInterval(30 * 60))
        #expect(VaultPeriod.month.shifted(now, by: 2, calendar: calendar) == date(2026, 8, 3, 14).addingTimeInterval(30 * 60))
        #expect(VaultPeriod.day.shifted(now, by: 0, calendar: calendar) == now)
    }

    @Test("A year is twelve months, ending with this one")
    func year() {
        let buckets = VaultPeriod.year.buckets(endingAt: now, calendar: calendar)
        #expect(buckets.count == 12)
        #expect(buckets.first?.start == date(2025, 11, 1))
        #expect(buckets.last?.start == date(2026, 10, 1))
    }

    @Test("Buckets tile the span with no gap and no overlap")
    func contiguous() {
        for period in VaultPeriod.allCases {
            let buckets = period.buckets(endingAt: now, calendar: calendar)
            let span = period.interval(endingAt: now, calendar: calendar)
            #expect(buckets.first?.start == span.start)
            #expect(buckets.last?.end == span.end)
            for (earlier, later) in zip(buckets, buckets.dropFirst()) {
                #expect(earlier.end == later.start)
            }
        }
    }

    private func reading(_ value: Double, at time: Date) -> HealthReading {
        HealthReading(metric: "m", value: value, unit: .count, start: time, end: time)
    }

    @Test("Folding averages a quantity, counts a category, and leaves an empty bucket nil")
    func fold() {
        let buckets = [
            DateInterval(start: date(2026, 10, 3, 8), end: date(2026, 10, 3, 9)),
            DateInterval(start: date(2026, 10, 3, 9), end: date(2026, 10, 3, 10)),
        ]
        let readings = [
            reading(60, at: date(2026, 10, 3, 8)),
            reading(80, at: date(2026, 10, 3, 8).addingTimeInterval(600)),
        ]

        let averaged = VaultBucketing.fold(readings, into: buckets, counting: false)
        #expect(averaged.map(\.value) == [70, nil])

        let counted = VaultBucketing.fold(readings, into: buckets, counting: true)
        #expect(counted.map(\.value) == [2, nil])
    }

    @Test("A reading on a bucket's end belongs to the next bucket")
    func edges() {
        let buckets = [
            DateInterval(start: date(2026, 10, 3, 8), end: date(2026, 10, 3, 9)),
            DateInterval(start: date(2026, 10, 3, 9), end: date(2026, 10, 3, 10)),
        ]
        let counted = VaultBucketing.fold([reading(1, at: date(2026, 10, 3, 9))], into: buckets, counting: true)
        #expect(counted.map(\.value) == [nil, 1])
    }

    @Test("Total and average skip empty buckets rather than read them as zero")
    func summaries() {
        let bucket = DateInterval(start: date(2026, 10, 3), duration: 3600)
        let points = [
            VaultPoint(interval: bucket, value: 4),
            VaultPoint(interval: bucket, value: nil),
            VaultPoint(interval: bucket, value: 8),
        ]
        #expect(VaultBucketing.total(points) == 12)
        #expect(VaultBucketing.average(points) == 6)
        #expect(VaultBucketing.total([VaultPoint(interval: bucket, value: nil)]) == nil)
        #expect(VaultBucketing.average([]) == nil)
    }

    @Test("Records group by the day they started, newest day first")
    func byDay() {
        let readings = [
            reading(3, at: date(2026, 10, 3, 9)),
            reading(2, at: date(2026, 10, 3, 7)),
            reading(1, at: date(2026, 10, 2, 22)),
        ]
        let days = VaultBucketing.byDay(readings, calendar: calendar)
        #expect(days.map(\.day) == [date(2026, 10, 3), date(2026, 10, 2)])
        #expect(days.first?.readings.map(\.value) == [3, 2])
    }

    @Test("Values read at the precision they deserve, percentages as percent")
    func format() {
        #expect(VaultFormat.scaled(0.97, unit: .percent) == 97)
        #expect(VaultFormat.scaled(72, unit: .countPerMinute) == 72)
        #expect(VaultFormat.number(72) == 72.formatted(.number.precision(.fractionLength(0))))
        #expect(VaultFormat.number(72.44) == 72.4.formatted(.number.precision(.fractionLength(1))))
        #expect(VaultFormat.number(0.054) == 0.05.formatted(.number.precision(.fractionLength(2))))
    }
}

@Suite("All Data row time")
struct VaultRecordWhenTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Today shows the time alone, yesterday says so, older days carry their date")
    func dayOnlyWhenRelevant() {
        let now = date(3, 18)
        let today = VaultRecordRow.when(date(3, 9), now: now, calendar: calendar)
        let yesterday = VaultRecordRow.when(date(2, 9), now: now, calendar: calendar)
        let older = VaultRecordRow.when(date(26, 9, month: 9), now: now, calendar: calendar)
        #expect(!today.contains("Oct"))
        #expect(yesterday.hasPrefix("Yesterday"))
        #expect(older.contains("Sep"))
        #expect(!older.contains("2026"))
    }
}

/// A metric page switched to a sibling from its title.
@Suite("Vault page switch")
struct VaultPageSwitchTests {
    @Test("A sibling never shows the last metric's data under its own name")
    func readIsKeyedByItsMetric() throws {
        let heart = try #require(HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierHeartRate"))
        let resting = try #require(HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierRestingHeartRate"))
        let opened = VaultSubject.health(BodyDataType(heart))
        let sibling = VaultSubject.health(BodyDataType(resting))

        let read = VaultLoaded(key: opened, value: [62.0, 64, 61])
        #expect(read.value(for: opened) == [62, 64, 61])
        // Switched: nothing until the sibling's own read lands.
        #expect(read.value(for: sibling) == nil)
        let next = VaultLoaded(key: sibling, value: [54.0])
        #expect(next.value(for: sibling) == [54])
        #expect(next.value(for: .score(.sleepScore)) == nil)
    }
}
