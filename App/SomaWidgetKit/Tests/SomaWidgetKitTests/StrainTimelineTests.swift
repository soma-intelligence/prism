import Foundation
import Testing
@testable import SomaWidgetKit

@Test func strainTimelineEveryQuarterHourForThreeHours() {
    let now = SomaWidgetSnapshot.placeholder.generatedAt
    let dates = StrainTimeline.entryDates(from: now)
    #expect(dates.count == 13)
    #expect(dates.first == now)
    #expect(dates.last == now.addingTimeInterval(3 * 3600))
    for (index, date) in dates.enumerated() {
        #expect(date == now.addingTimeInterval(Double(index) * 15 * 60))
    }
}

@Test func placeholderIsTheThirdOfOctoberAtNoon() throws {
    let snapshot = SomaWidgetSnapshot.placeholder
    let noon = try #require(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z"))
    #expect(snapshot.generatedAt == noon)
    #expect(snapshot.tally.day == "2026-10-03")
}

@Test func placeholderCurveStartsAtBedtime() throws {
    let snapshot = SomaWidgetSnapshot.placeholder
    let band = try #require(snapshot.sleepBand)
    let first = try #require(snapshot.energyCurve.first)
    let last = try #require(snapshot.energyCurve.last)
    #expect(first.date == band.lowerBound)
    #expect(last.date == snapshot.generatedAt)
    #expect(band.upperBound < snapshot.generatedAt)
    #expect(abs(last.level - (snapshot.energyNow ?? 0)) < 1e-9)
    let stages = try #require(snapshot.hypnogram)
    #expect(stages.first?.start == band.lowerBound)
    #expect(stages.last?.end == band.upperBound)
}
