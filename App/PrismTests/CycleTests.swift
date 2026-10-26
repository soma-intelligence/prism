//
//  CycleTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthKit
import HealthExportCore
@testable import Prism

/// A writer that keeps what it was handed instead of writing to Health.
private final class SpyCycleWriter: CycleHealthWriting, @unchecked Sendable {
    private(set) var saved: [CycleSample] = []
    var canWrite = true

    func save(_ sample: CycleSample) async throws {
        saved.append(sample)
    }
}

/// Whether the page has asked, flipped by the test.
@MainActor
private final class AskedFlag {
    var value = false
}

/// The cycle and perimenopause: periods with and without an end, the stages
/// STRAW+10 names read from cycle lengths, the tile that only shows for a
/// person who tracks a cycle, writes that wait for the page to have asked,
/// and the launch sheet that never names a cycle type.
@Suite("Cycle and perimenopause")
@MainActor
struct CycleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// Saturday 24 October 2026, 21:00 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 21))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    /// Five days of flow from each start, offsets from today.
    private func flow(starts: [Int], days: Int = 5) -> [Date] {
        starts.flatMap { start in (0..<days).map { day(start + $0) } }
    }

    /// Period starts walking back from `last` with these cycle lengths,
    /// oldest length first.
    private func starts(lengths: [Int], last: Int) -> [Int] {
        var offsets = [last]
        for length in lengths.reversed() { offsets.insert(offsets[0] - length, at: 0) }
        return offsets
    }

    private func periods(_ flowDays: [Date]) -> [CyclePeriod] {
        CycleHistory.periods(flowDays: flowDays, today: now, calendar: calendar)
    }

    private func stage(_ flowDays: [Date], symptoms: [CycleSymptom: [Date]] = [:], age: Int? = 47) -> PerimenopauseStage? {
        PerimenopauseSignal.evaluate(cycles: periods(flowDays), symptoms: symptoms, wristTemperature: [],
                                     now: now, calendar: calendar, age: age)
    }

    // MARK: Periods

    @Test("A period that started and has not ended has no length, and its cycle is not counted")
    func openPeriodHasNoEnd() {
        let found = periods(flow(starts: [-58, -30]) + [day(-1), day(0)])
        #expect(found.count == 3)
        #expect(found.last?.isOpen == true)
        #expect(found.last?.days == nil)
        #expect(found.first?.days == 5)
        // Two closed cycles, none still running.
        #expect(CycleHistory.cycleLengths(found) == [28, 29])
    }

    @Test("Flow ten days apart or more starts a new period")
    func periodsSplitOnGap() {
        let found = periods(flow(starts: [-40, -12]))
        #expect(found.map(\.start) == [day(-40), day(-12)])
        #expect(found.allSatisfy { !$0.isOpen })
    }

    // MARK: Perimenopause

    @Test("Cycles that differ by seven days or more, more than once in ten, are an early transition")
    func variableCyclesEarlyTransition() {
        let lengths = [28, 27, 36, 28, 26, 35, 29, 27, 28, 27]
        #expect(stage(flow(starts: starts(lengths: lengths, last: -20))) == .earlyTransition)
    }

    @Test("A single long cycle is not yet a persistent difference")
    func oneVariableCycleIsNone() {
        let lengths = [28, 27, 36, 28, 27, 28, 29, 27, 28, 27]
        #expect(stage(flow(starts: starts(lengths: lengths, last: -20))) == PerimenopauseStage.none)
    }

    @Test("Sixty days or more without a period is a late transition")
    func sixtyDaysLateTransition() {
        let recorded = flow(starts: starts(lengths: [28, 29, 28], last: -64))
        #expect(stage(recorded) == .lateTransition)
        // The same gap inside the record, between two periods, counts too.
        let inside = flow(starts: starts(lengths: [28, 29, 63, 28], last: -10))
        #expect(stage(inside) == .lateTransition)
    }

    @Test("Twelve months without a period is postmenopause")
    func twelveMonthsPost() {
        let recorded = flow(starts: starts(lengths: [45, 70, 90], last: -380))
        #expect(stage(recorded) == .postmenopause)
        #expect(stage(flow(starts: starts(lengths: [45, 70, 90], last: -300))) == .lateTransition)
    }

    @Test("No periods on record reads nothing, and two periods are too few to stage")
    func emptyAndShortRecords() {
        #expect(stage([]) == nil)
        #expect(stage(flow(starts: [-40, -12])) == nil)
    }

    @Test("Under forty the signs are not staged")
    func youngerThanFortyIsNotStaged() {
        let lengths = [28, 27, 36, 28, 26, 35, 29, 27, 28, 27]
        #expect(stage(flow(starts: starts(lengths: lengths, last: -20)), age: 32) == nil)
    }

    @Test("Hot flashes and night sweats on several days are listed as signs, never as a stage of their own")
    func symptomsAreSigns() {
        let flashes = (0..<6).map { day(-$0 * 3) }
        let sweats = (0..<4).map { day(-$0 * 5) }
        let warm = sweats.map { night in
            HealthReading(metric: HomeMetric.wristTemperature, value: 36.9, unit: .degreeCelsius,
                          start: night.addingTimeInterval(3 * 3600), end: night.addingTimeInterval(6 * 3600), source: "Watch")
        }
        let usual = (0..<30).map { back -> HealthReading in
            let night = day(-back)
            return HealthReading(metric: HomeMetric.wristTemperature, value: 36.3, unit: .degreeCelsius,
                                 start: night.addingTimeInterval(3 * 3600), end: night.addingTimeInterval(6 * 3600), source: "Watch")
        }.filter { reading in !sweats.contains { calendar.isDate($0, inSameDayAs: reading.start) } }
        let assessment = PerimenopauseSignal.assess(
            cycles: periods(flow(starts: starts(lengths: [28, 28, 29], last: -10))),
            symptoms: [.hotFlashes: flashes, .nightSweats: sweats],
            wristTemperature: usual + warm,
            now: now, calendar: calendar, age: 48
        )
        #expect(assessment.stage == PerimenopauseStage.none)
        #expect(assessment.signs.contains(.hotFlashes(days: 6)))
        #expect(assessment.signs.contains(.nightSweats(nights: 4, warmNights: 4)))
    }

    // MARK: Tile

    @Test("The cycle tile shows for a person who tracks a cycle, and stays hidden otherwise")
    func hiddenForNonCycleProfile() {
        #expect(!CycleVisibility.tracksCycle(sex: .male, flowOnRecord: false))
        #expect(!CycleVisibility.tracksCycle(sex: .other, flowOnRecord: false))
        #expect(!CycleVisibility.tracksCycle(sex: nil, flowOnRecord: false))
        #expect(CycleVisibility.tracksCycle(sex: .female, flowOnRecord: false))
        // Flow on record is the strongest sign, whatever the profile says.
        #expect(CycleVisibility.tracksCycle(sex: .male, flowOnRecord: true))
        #expect(CycleVisibility.tracksCycle(sex: nil, flowOnRecord: true))
    }

    // MARK: Writing

    @Test("Flow and symptoms reach Health only once the cycle page has asked for them")
    func writesSensitiveOnlyAfterAsk() async {
        let writer = SpyCycleWriter()
        let asked = AskedFlag()
        let log = CycleLog(writer: writer, isAsked: { asked.value })

        #expect(await log.write(flow: .medium, on: now, startsPeriod: true, calendar: calendar) == .notAsked)
        #expect(await log.write(symptom: .hotFlashes, on: now, calendar: calendar) == .notAsked)
        #expect(writer.saved.isEmpty)

        asked.value = true
        #expect(await log.write(flow: .medium, on: now, startsPeriod: true, calendar: calendar) == .saved)
        #expect(await log.write(symptom: .hotFlashes, on: now, calendar: calendar) == .saved)
        #expect(writer.saved.count == 2)

        let flowSample = writer.saved[0]
        #expect(flowSample.identifier == HomeMetric.menstrualFlow)
        #expect(flowSample.value == HKCategoryValueVaginalBleeding.medium.rawValue)
        #expect(flowSample.startsCycle == true)
        #expect(flowSample.start == calendar.startOfDay(for: now))
        #expect(flowSample.end == day(1))

        let symptomSample = writer.saved[1]
        #expect(symptomSample.identifier == "HKCategoryTypeIdentifierHotFlashes")
        #expect(symptomSample.value == HKCategoryValueSeverity.unspecified.rawValue)
        #expect(symptomSample.startsCycle == nil)
    }

    @Test("Nothing is written where Health cannot be written")
    func writesNothingWithoutHealth() async {
        let writer = SpyCycleWriter()
        writer.canWrite = false
        let log = CycleLog(writer: writer, isAsked: { true })
        #expect(await log.write(symptom: .headache, on: now, calendar: calendar) == .notWritten)
        #expect(writer.saved.isEmpty)
    }

    @Test("The one Health sheet carries every cycle type, as the owner ruled on 2026-10-03")
    func oneSheetCarriesCycleTypes() {
        let read = HealthAccess.readTypes()
        let cycleIDs = [HomeMetric.menstrualFlow] + CycleSymptom.allCases.map(\.identifier)
        for id in cycleIDs {
            let type = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: id))!
            #expect(read.contains(type), "\(id) is missing from the one sheet")
        }
    }

    // MARK: Notes

    @Test("Notes and the flow seen survive a reload, and an empty note clears the day")
    func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cycle-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = CycleStore(url: url)
        store.setNote("Tired after the run", on: now, calendar: calendar)
        store.markFlowSeen(day(-3))
        let reloaded = CycleStore(url: url)
        #expect(reloaded.note(on: now, calendar: calendar) == "Tired after the run")
        #expect(reloaded.flowSeenAt == day(-3))

        reloaded.setNote("  ", on: now, calendar: calendar)
        #expect(CycleStore(url: url).note(on: now, calendar: calendar) == nil)
    }

    @Test("Symptoms of the current cycle are counted in days, most frequent first")
    func symptomTally() {
        let tally = CycleSymptomTally.make(
            symptoms: [.cramps: [day(-6), day(-5), day(-5)], .headache: [day(-2)], .bloating: [day(-40)]],
            since: day(-7), now: now, calendar: calendar
        )
        #expect(tally.map(\.symptom) == [.cramps, .headache])
        #expect(tally.map(\.days) == [2, 1])
    }
}
