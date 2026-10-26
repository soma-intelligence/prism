//
//  ToolsAgingScreeningTests.swift
//  PrismTests
//
//  Aging Pace resolves one number, bio years per calendar year, from two
//  sources: the model's calibrated two window pace first, the least squares
//  slope of the dense bio age history second. Pinned here: the band edges
//  (0.95 and 1.05 both read as "holding"), the 0.4 to 1.8 clamp on both
//  sources, the five point floor of the trend fit, and that a non finite model
//  value falls back instead of leaking through.
//
//  The screening ledger's two guarantees get their own cases: a `.discuss`
//  item can never be reported due, and neither can an item gated on a risk
//  flag the user has not answered.
//

import Foundation
import Testing
@testable import Prism

private func approx(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: - Aging Pace

@Suite("Tools: Aging Pace")
struct ToolsAgingPaceTests {

    typealias Engine = SomaTools.AgingPace

    /// `count` daily points whose bio age rises by `perYear` years per calendar
    /// year, so the fitted pace is exactly `perYear`.
    func linearHistory(perYear: Double, count: Int = 5,
                       start: Double = 40) -> [(day: Double, bioAge: Double)] {
        (0..<count).map { day in
            (day: Double(day), bioAge: start + Double(day) * perYear / 365.25)
        }
    }

    // MARK: Band

    @Test func bandEdgesAreInclusiveOnTheHoldingSide() {
        #expect(Engine.Band(pace: 0.4) == .gaining)
        #expect(Engine.Band(pace: 0.9499) == .gaining)
        #expect(Engine.Band(pace: 0.95) == .holding)
        #expect(Engine.Band(pace: 1.0) == .holding)
        #expect(Engine.Band(pace: 1.05) == .holding)
        #expect(Engine.Band(pace: 1.0501) == .faster)
        #expect(Engine.Band(pace: 1.8) == .faster)
    }

    // MARK: Reading

    @Test func readingDerivesGapBandAndProjections() {
        let reading = Engine.Reading(pace: 0.8, source: .model, fitQuality: 0.6,
                                     currentBioAge: 40, chronoAge: 42, coverageDays: 120)
        #expect(reading.band == .gaining)
        #expect(approx(reading.gapYears, -2))
        #expect(approx(reading.projectedBioAge(inYears: 10), 48))
        #expect(approx(reading.projectedChronoAge(inYears: 10), 52))
        // Two years younger today, and 0.2 years a year gained on top.
        #expect(approx(reading.projectedGap(inYears: 10), -4))
    }

    @Test func aFasterPaceWidensAnOlderGapOverTime() {
        let reading = Engine.Reading(pace: 1.5, source: .trendFit, fitQuality: nil,
                                     currentBioAge: 51, chronoAge: 50, coverageDays: 30)
        #expect(reading.band == .faster)
        #expect(approx(reading.gapYears, 1))
        #expect(approx(reading.projectedGap(inYears: 4), 3))
        #expect(approx(reading.projectedGap(inYears: 0), 1))
    }

    // MARK: Continuous pace

    @Test func fewerThanFivePointsGiveNoTrend() {
        #expect(Engine.continuousPace(fromDatedBioAge: []) == nil)
        #expect(Engine.continuousPace(fromDatedBioAge: linearHistory(perYear: 1, count: 4)) == nil)
    }

    @Test func theSlopeIsConvertedToBioYearsPerCalendarYear() throws {
        let fit = try #require(Engine.continuousPace(fromDatedBioAge: linearHistory(perYear: 0.9)))
        #expect(approx(fit.pace, 0.9))
        #expect(approx(fit.rSquared, 1))
    }

    @Test func theTrendPaceIsClampedToTheBelievableWindow() throws {
        let fast = try #require(Engine.continuousPace(fromDatedBioAge: linearHistory(perYear: 3)))
        #expect(fast.pace == Engine.maxPace)
        let reversing = try #require(Engine.continuousPace(fromDatedBioAge: linearHistory(perYear: -2)))
        #expect(reversing.pace == Engine.minPace)
    }

    @Test func aFlatHistoryClampsToTheFloorWithNoFitQuality() throws {
        let flat = (0..<6).map { (day: Double($0), bioAge: 45.0) }
        let fit = try #require(Engine.continuousPace(fromDatedBioAge: flat))
        #expect(fit.pace == 0.4)
        #expect(fit.rSquared == 0)
    }

    @Test func pointsOnOneDayCannotFormASlope() {
        let stacked = (0..<5).map { (day: 3.0, bioAge: 40.0 + Double($0)) }
        #expect(Engine.continuousPace(fromDatedBioAge: stacked) == nil)
    }

    // MARK: Resolution

    @Test func theModelPaceWinsAndTheFitStillReportsItsQuality() throws {
        let resolved = try #require(Engine.resolvePace(modelPace: 1.2,
                                                       historyPoints: linearHistory(perYear: 0.7)))
        #expect(resolved.pace == 1.2)
        #expect(resolved.source == .model)
        #expect(approx(resolved.fitQuality ?? -1, 1))
    }

    @Test func theModelPaceIsClampedAndCarriesNoQualityWithoutHistory() throws {
        let high = try #require(Engine.resolvePace(modelPace: 2.5, historyPoints: []))
        #expect(high.pace == 1.8)
        #expect(high.source == .model)
        #expect(high.fitQuality == nil)

        let low = try #require(Engine.resolvePace(modelPace: 0.1, historyPoints: []))
        #expect(low.pace == 0.4)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func aNonFiniteModelPaceFallsBackToTheTrend(bad: Double) throws {
        let resolved = try #require(Engine.resolvePace(modelPace: bad,
                                                       historyPoints: linearHistory(perYear: 1.1)))
        #expect(resolved.source == .trendFit)
        #expect(approx(resolved.pace, 1.1))
        #expect(approx(resolved.fitQuality ?? -1, 1))
    }

    @Test func nothingToResolveIsNil() {
        #expect(Engine.resolvePace(modelPace: nil, historyPoints: []) == nil)
        #expect(Engine.resolvePace(modelPace: .nan,
                                   historyPoints: linearHistory(perYear: 1, count: 3)) == nil)
    }

    // MARK: Page pieces

    @Test func projectionVerdictHasAParBand() {
        #expect(Engine.Verdict(gap: 0.04) == .onPar)
        #expect(Engine.Verdict(gap: -0.04) == .onPar)
        #expect(Engine.Verdict(gap: 2) == .older(years: 2))
        #expect(Engine.Verdict(gap: -1.5) == .younger(years: 1.5))
    }

    @Test func driversAreSortedBiggestMoverFirst() {
        let components = [
            SomaTools.AgingBioAge.Component(metric: .steps, zScore: 0, yearsDelta: -0.5,
                                            logHazardDelta: 0, windowDays: 90),
            SomaTools.AgingBioAge.Component(metric: .hrv, zScore: 0, yearsDelta: 1.2,
                                            logHazardDelta: 0, windowDays: 90),
            SomaTools.AgingBioAge.Component(metric: .vo2Max, zScore: 0, yearsDelta: -2,
                                            logHazardDelta: 0, windowDays: 90)
        ]
        #expect(Engine.drivers(from: components).map(\.title) == ["VO2 Max", "HRV", "Daily steps"])
    }

    @Test func weeklyHistoryKeepsEmptyWeeksAsNil() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29)))
        let history = [
            Engine.HistoryPoint(date: end.addingTimeInterval(-86_400), bioAge: 40),
            Engine.HistoryPoint(date: end, bioAge: 42)
        ]
        let weeks = Engine.weeklyHistory(history, weeks: 3, endingOn: end, calendar: calendar)
        #expect(weeks.count == 3)
        #expect(weeks.last?.index == 0)
        #expect(weeks.last?.meanBioAge == 41)
        #expect(weeks.first?.meanBioAge == nil)
    }
}

// MARK: - Biological age model

@Suite("Tools: Biological age model")
struct ToolsAgingBioAgeTests {

    typealias Model = SomaTools.AgingBioAge

    func inputs(hrv: Double = 40, rhr: Double = 68, days: Int = 120) -> Model.Inputs {
        Model.Inputs(restingHR: Array(repeating: rhr, count: days),
                     hrv: Array(repeating: hrv, count: days))
    }

    @Test func nonPositiveAgeOrNoSeriesGivesNothing() {
        #expect(Model.compute(chronologicalAge: 0, sex: .male, inputs: inputs()) == nil)
        #expect(Model.compute(chronologicalAge: 40, sex: .male, inputs: Model.Inputs()) == nil)
    }

    @Test func aSeriesUnderItsFloorIsLeftOut() {
        #expect(Model.compute(chronologicalAge: 40, sex: .male, inputs: inputs(days: 29)) == nil)
    }

    @Test func steadyReferenceValuesReadNearTheCalendar() throws {
        // HRV at the 48 year norm and resting HR at the male mean.
        let result = try #require(Model.compute(chronologicalAge: 48, sex: .male, inputs: inputs()))
        #expect(result.estimatedAge == 48)
        #expect(approx(result.paceOfAging ?? -1, 1))
        #expect(result.coverageDays == 120)
    }

    @Test func theTotalIsClampedAtSixYears() throws {
        let result = try #require(Model.compute(chronologicalAge: 40, sex: .male,
                                                inputs: inputs(hrv: 5, rhr: 120)))
        #expect(result.estimatedAge == 46)
    }

    @Test func aHigherHRVLeverReadsYounger() throws {
        let whatIf = try #require(SomaTools.AgingPace.whatIf(.hrv(ms: 20), chronologicalAge: 48,
                                                             sex: .male, inputs: inputs()))
        #expect(whatIf.deltaYears < 0)
        if case .younger = whatIf.verdict {} else { Issue.record("expected younger, got \(whatIf.verdict)") }
    }

    @Test func aLeverOnAnEmptySeriesHasNoAnswer() {
        #expect(SomaTools.AgingPace.whatIf(.vo2Max(mlKgMin: 3), chronologicalAge: 48,
                                           sex: .male, inputs: inputs()) == nil)
    }

    @Test func confidenceIsTheWeakerOfCoverageAndComponents() throws {
        let result = try #require(Model.compute(chronologicalAge: 48, sex: .male, inputs: inputs()))
        // 120 days is high coverage, but only two components: low.
        #expect(result.confidence == .low)
    }
}

// MARK: - Screening due engine

@Suite("Tools: Screening due engine")
struct ToolsScreeningDueEngineTests {

    typealias Engine = SomaTools.ScreeningDueEngine
    typealias Catalog = SomaTools.ScreeningCatalog
    typealias Done = SomaTools.ScreeningDone
    typealias Risk = SomaTools.ScreeningRisk

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    var today: Date { date(2026, 7, 31) }

    func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func statuses(age: Int,
                  sex: SomaTools.ScreeningEligibility? = .male,
                  records: [Done] = [],
                  risk: [Risk] = [],
                  catalog: [SomaTools.ScreeningItem] = Catalog.items) -> [Engine.Status] {
        Engine.statuses(age: age, sex: sex, today: today, records: records, risk: risk,
                        catalog: catalog, calendar: calendar)
    }

    func status(_ id: String, in list: [Engine.Status]) -> Engine.Status? {
        list.first { $0.item.id == id }
    }

    // MARK: The guard that stops an empty profile from asserting nonsense

    @Test func nonPositiveAgeReturnsNothing() {
        #expect(statuses(age: 0).isEmpty)
        #expect(statuses(age: -3).isEmpty)
    }

    // MARK: Guarantee one, tier discuss is never due

    @Test func discussTierNeverProducesDue() {
        let list = statuses(age: 70, sex: .male)
        for item in Catalog.discuss {
            guard let found = status(item.id, in: list) else { continue }
            #expect(found.state == .discussOnly, "\(item.id) must stay discussOnly")
            #expect(!found.isDue, "\(item.id) must never report as due")
        }
    }

    @Test func discussTierStaysDiscussEvenWithFamilyHistory() {
        let risk = [Risk(flag: .familyMelanoma, isPresent: true, earliestDiagnosisAge: 35),
                    Risk(flag: .familyProstate, isPresent: true, earliestDiagnosisAge: 50)]
        let list = statuses(age: 60, sex: .male, risk: risk)
        #expect(status("skinExam", in: list)?.state == .discussOnly)
        #expect(status("psa", in: list)?.state == .discussOnly)
    }

    // MARK: Guarantee two, a gated item is never due without an answer

    @Test func gatedItemStaysDiscussUntilRiskAnswered() {
        #expect(status("lungCT", in: statuses(age: 60, sex: .male))?.state == .discussOnly)
        #expect(status("aorticUltrasound", in: statuses(age: 70, sex: .male))?.state == .discussOnly)
    }

    @Test func gatedItemBecomesDueOnceRiskAnswered() {
        let risk = [Risk(flag: .tobaccoEverSmoker, isPresent: true, packYears: 25)]
        #expect(status("lungCT", in: statuses(age: 60, sex: .male, risk: risk))?.isDue == true)
    }

    @Test func riskAnsweredFalseDoesNotOpenTheGate() {
        let risk = [Risk(flag: .tobaccoEverSmoker, isPresent: false)]
        #expect(status("lungCT", in: statuses(age: 60, sex: .male, risk: risk))?.state == .discussOnly)
    }

    // MARK: Age gating

    @Test func tooYoungReportsEffectiveStartAge() {
        #expect(status("colorectal", in: statuses(age: 30))?.state == .notYetEligible(startsAtAge: 45))
    }

    @Test func pastStopAgeStopsAsserting() {
        #expect(status("colorectal", in: statuses(age: 80))?.state == .pastStopAge)
    }

    @Test func neverRecordedAndEligibleIsDueByYearsOfEligibility() {
        // Eligible at 45, now 49: four years of eligibility, no record.
        #expect(status("colorectal", in: statuses(age: 49))?.state == .due(monthsLate: 48))
    }

    // MARK: Sex eligibility

    @Test func femaleOnlyItemsAreAbsentForMale() {
        let list = statuses(age: 50, sex: .male)
        #expect(status("mammography", in: list) == nil)
        #expect(status("cervical", in: list) == nil)
    }

    @Test func unknownSexKeepsOnlyUniversalItems() {
        let list = statuses(age: 50, sex: nil)
        #expect(status("mammography", in: list) == nil, "female item must not appear")
        #expect(status("psa", in: list) == nil, "male item must not appear")
        #expect(status("colorectal", in: list) != nil, "universal item must still appear")
    }

    // MARK: Intervals

    @Test func recentRecordIsUpToDate() {
        let records = [Done(itemID: "colorectal", performedOn: date(2024, 3))]
        let found = status("colorectal", in: statuses(age: 50, records: records))
        guard case .upToDate = found?.state else {
            Issue.record("expected upToDate, got \(String(describing: found?.state))")
            return
        }
        #expect(found?.lastDone == date(2024, 3))
    }

    @Test func expiredIntervalIsDueWithMonthsLate() {
        // Ten year interval from March 2014 came due March 2024, so 28 months
        // by the end of July 2026.
        let records = [Done(itemID: "colorectal", performedOn: date(2014, 3))]
        #expect(status("colorectal", in: statuses(age: 60, records: records))?.state == .due(monthsLate: 28))
    }

    @Test func onceInALifetimeIsSettledByOneRecord() {
        let records = [Done(itemID: "hepatitisC", performedOn: date(2009, 1))]
        #expect(status("hepatitisC", in: statuses(age: 50, records: records))?.state
                == .upToDate(until: .distantFuture))
    }

    @Test func onlyTheMostRecentRecordCounts() {
        let records = [Done(itemID: "bloodPressure", performedOn: date(2019, 1)),
                       Done(itemID: "bloodPressure", performedOn: date(2026, 6))]
        let found = status("bloodPressure", in: statuses(age: 40, records: records))
        #expect(found?.lastDone == date(2026, 6))
        #expect(found?.isDue == false)
    }

    @Test func upcomingWindowIsNinetyDays() {
        let records = [Done(itemID: "bloodPressure", performedOn: date(2025, 9))]
        guard case .upcoming = status("bloodPressure", in: statuses(age: 40, records: records))?.state else {
            Issue.record("expected upcoming inside the 90 day horizon")
            return
        }
    }

    // MARK: nextDueOverride

    @Test func overrideWinsOverTheCatalogInterval() {
        let records = [Done(itemID: "colorectal", performedOn: date(2019, 3), nextDueOverride: date(2024, 3))]
        #expect(status("colorectal", in: statuses(age: 60, records: records))?.state == .due(monthsLate: 28))
    }

    @Test func overrideCanAlsoPushOutAOnceInALifetimeItem() {
        let records = [Done(itemID: "hepatitisC", performedOn: date(2020, 1), nextDueOverride: date(2025, 1))]
        #expect(status("hepatitisC", in: statuses(age: 50, records: records))?.isDue == true)
    }

    // MARK: Family history modifiers

    @Test func familyHistoryPullsStartAgeToTheFixedOverride() {
        let risk = [Risk(flag: .familyColorectal, isPresent: true)]
        let found = status("colorectal", in: statuses(age: 41, sex: .male, risk: risk))
        #expect(found?.effectiveStartAge == 40)
        #expect(found?.isDue == true, "eligible at 40, aged 41, nothing recorded")
        #expect(found?.appliedFlags == [.familyColorectal])
    }

    @Test func familyHistoryUsesTheEarlierOfTheTwoComputations() {
        let risk = [Risk(flag: .familyColorectal, isPresent: true, earliestDiagnosisAge: 45)]
        #expect(status("colorectal", in: statuses(age: 36, sex: .male, risk: risk))?.effectiveStartAge == 35)
    }

    @Test func fixedOverrideWinsWhenItIsTheEarlierOne() {
        let risk = [Risk(flag: .familyColorectal, isPresent: true, earliestDiagnosisAge: 70)]
        #expect(status("colorectal", in: statuses(age: 50, sex: .male, risk: risk))?.effectiveStartAge == 40)
    }

    @Test func familyHistoryShortensTheInterval() {
        let risk = [Risk(flag: .familyColorectal, isPresent: true)]
        #expect(status("colorectal", in: statuses(age: 60, sex: .male, risk: risk))?.effectiveIntervalMonths == 60)
    }

    @Test func unansweredFlagLeavesTheGeneralPopulationCadence() {
        let found = status("colorectal", in: statuses(age: 42, sex: .male))
        #expect(found?.effectiveStartAge == 45)
        #expect(found?.effectiveIntervalMonths == 120)
        #expect(found?.state == .notYetEligible(startsAtAge: 45))
        #expect(found?.appliedFlags.isEmpty == true)
    }

    @Test func flagAnsweredFalseChangesNothing() {
        let risk = [Risk(flag: .familyColorectal, isPresent: false, earliestDiagnosisAge: 40)]
        #expect(status("colorectal", in: statuses(age: 42, sex: .male, risk: risk))?.effectiveStartAge == 45)
    }

    @Test func riskDoesNotTurnAOnceOnlyItemIntoARecurringOne() {
        let risk = [Risk(flag: .tobaccoEverSmoker, isPresent: true)]
        #expect(status("aorticUltrasound", in: statuses(age: 70, sex: .male, risk: risk))?
                    .effectiveIntervalMonths == nil)
    }

    // MARK: Ordering and the card's input

    @Test func dueNowKeepsOnlyRecommendedAndOrdersWorstFirst() {
        let records = [Done(itemID: "bloodPressure", performedOn: date(2025, 1)),
                       Done(itemID: "colorectal", performedOn: date(2010, 1))]
        let ids: Set<String> = ["bloodPressure", "colorectal", "psa", "hearing"]
        let catalog = Catalog.items.filter { ids.contains($0.id) }
        #expect(catalog.count == ids.count, "a fixture id left the catalog")

        let due = Engine.dueNow(statuses(age: 60, sex: .male, records: records, catalog: catalog))
        #expect(due.allSatisfy { $0.item.tier == .recommended })
        // Colonoscopy due 2020-01-15, blood pressure due 2026-01-15.
        #expect(due.map(\.item.id) == ["colorectal", "bloodPressure"], "the latest one leads")
        #expect(due.map(\.monthsLate) == [78, 6])
    }

    @Test func dueItemsSortAheadOfEverythingElse() {
        let list = statuses(age: 60, sex: .male)
        guard let firstNonDue = list.firstIndex(where: { !$0.isDue }) else { return }
        #expect(!list[firstNonDue...].contains { $0.isDue }, "no due item may appear after a non due one")
    }

    // MARK: Card priority

    @Test func priorityRisesWithLatenessAndStaysUnderTheCeiling() {
        #expect(Engine.priority(monthsLate: 0) == 60)
        #expect(Engine.priority(monthsLate: 48) == 76)
        #expect(Engine.priority(monthsLate: 600) <= 80)
    }

    // MARK: Catalog integrity

    @Test func catalogIdsAreUnique() {
        let ids = Catalog.items.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyItemCarriesACitation() {
        for item in Catalog.items {
            #expect(!item.citation.isEmpty, "\(item.id) has no citation")
            #expect(!item.title.isEmpty, "\(item.id) has no title")
            #expect(!item.evidence.isEmpty, "\(item.id) has no evidence line")
        }
    }

    @Test func everyRiskFlagHasALabel() {
        for flag in SomaTools.ScreeningRiskFlag.allCases {
            #expect(!flag.label.isEmpty, "\(flag.rawValue) has no label")
        }
    }

    @Test func everyGatedItemGatesOnAnAnswerableFlag() {
        for item in Catalog.items {
            guard let gate = item.requiresRiskFlag else { continue }
            #expect(SomaTools.ScreeningRiskFlag.allCases.contains(gate))
        }
    }

    @Test func everyModifierNamesAFlagTheUserIsAsked() {
        for item in Catalog.items {
            for modifier in item.modifiers {
                #expect(SomaTools.ScreeningRiskFlag.allCases.contains(modifier.flag))
            }
        }
    }

    @Test func eligibilityMapsTheProfileStringsWeActuallyStore() {
        #expect(SomaTools.ScreeningEligibility.from(profileSex: "Female") == .female)
        #expect(SomaTools.ScreeningEligibility.from(profileSex: "male") == .male)
        #expect(SomaTools.ScreeningEligibility.from(profileSex: "Homme") == .male)
        #expect(SomaTools.ScreeningEligibility.from(profileSex: "") == nil)
        #expect(SomaTools.ScreeningEligibility.from(profileSex: "other") == nil)
    }

    // MARK: Copy

    @Test func lateLabelsReadInYearsPastAYear() {
        #expect(Engine.lateLabel(monthsLate: 0) == nil)
        #expect(Engine.lateLabel(monthsLate: 7) == "7 months late")
        #expect(Engine.lateLabel(monthsLate: 36) == "3 years late")
        #expect(Engine.lateLabel(monthsLate: 12) == "1 year late")
    }
}

// MARK: - Screening ledger

@Suite("Tools: Screening ledger")
struct ToolsScreeningLedgerTests {

    typealias Ledger = SomaTools.ScreeningLedger

    func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Records

    @Test func logStoresAndReadsBack() {
        var ledger = Ledger()
        ledger.log(itemID: "colorectal", performedOn: date(2024, 3), note: "two benign polyps")
        let records = ledger.records(for: "colorectal")
        #expect(records.count == 1)
        #expect(records.first?.note == "two benign polyps")
        #expect(records.first?.performedOn == date(2024, 3))
        #expect(records.first?.documentID == nil)
    }

    @Test func lastRecordIsTheMostRecentNotTheLastWritten() {
        var ledger = Ledger()
        ledger.log(itemID: "bloodPressure", performedOn: date(2026, 6))
        ledger.log(itemID: "bloodPressure", performedOn: date(2019, 1))
        #expect(ledger.lastRecord(for: "bloodPressure")?.performedOn == date(2026, 6))
    }

    @Test func recordsAreScopedByItem() {
        var ledger = Ledger()
        ledger.log(itemID: "colorectal", performedOn: date(2024, 3))
        ledger.log(itemID: "mammography", performedOn: date(2025, 3))
        #expect(ledger.records(for: "colorectal").count == 1)
        #expect(ledger.records.count == 2)
    }

    @Test func deleteRemovesTheRow() {
        var ledger = Ledger()
        let record = ledger.log(itemID: "vision", performedOn: date(2024, 1))
        ledger.delete(recordID: record.id)
        #expect(ledger.records(for: "vision").isEmpty)
    }

    @Test func attachSetsTheDocumentOnAnExistingRow() {
        var ledger = Ledger()
        let record = ledger.log(itemID: "colorectal", performedOn: date(2024, 3))
        let doc = UUID()
        ledger.attach(documentID: doc, toRecord: record.id)
        #expect(ledger.lastRecord(for: "colorectal")?.documentID == doc)
    }

    // MARK: Risk answers

    @Test func answerUpsertsRatherThanAccumulates() {
        var ledger = Ledger()
        ledger.answer(flag: .familyColorectal, isPresent: true, earliestDiagnosisAge: 50)
        ledger.answer(flag: .familyColorectal, isPresent: true, earliestDiagnosisAge: 45)
        let rows = ledger.riskAnswers.filter { $0.flag == .familyColorectal }
        #expect(rows.count == 1, "answering twice revises, it does not pile up")
        #expect(rows.first?.earliestDiagnosisAge == 45)
    }

    @Test func answeringNoIsRecordedAsAnAnswer() {
        var ledger = Ledger()
        ledger.answer(flag: .familyMelanoma, isPresent: false)
        #expect(ledger.hasAnsweredAnyRisk)
        #expect(ledger.riskAnswers.first?.isPresent == false)
    }

    @Test func hasAnsweredAnyRiskStartsFalse() {
        #expect(!Ledger().hasAnsweredAnyRisk)
    }

    // MARK: Persistence

    @Test func jsonRoundTripKeepsRecordsAndAnswers() throws {
        var ledger = Ledger()
        ledger.log(itemID: "colorectal", performedOn: date(2019, 3), note: "polyps",
                   nextDueOverride: date(2024, 3))
        ledger.answer(flag: .familyColorectal, isPresent: true, earliestDiagnosisAge: 45,
                      answeredAt: date(2026, 1))
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
        #expect(decoded.records.first?.nextDueOverride == date(2024, 3))
        #expect(decoded.riskAnswers.first?.earliestDiagnosisAge == 45)
    }

    @Test func decodeDropsAnUnknownFlagRatherThanFailing() throws {
        let json = #"{"records":[],"riskAnswers":[{"flag":"gone","isPresent":true},{"flag":"familyDiabetes","isPresent":true}]}"#
        let decoded = try JSONDecoder().decode(Ledger.self, from: Data(json.utf8))
        #expect(decoded.riskAnswers.map(\.flag) == [.familyDiabetes])
    }

    @Test func anEmptyObjectDecodesToAnEmptyLedger() throws {
        let decoded = try JSONDecoder().decode(Ledger.self, from: Data("{}".utf8))
        #expect(decoded == Ledger())
    }

    // MARK: The ledger computes nothing

    @Test func theEngineNotTheLedgerDecidesWhatIsDue() {
        var ledger = Ledger()
        ledger.log(itemID: "colorectal", performedOn: date(2010, 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let statuses = ledger.statuses(age: 60, sex: .male, today: date(2026, 7, 31), calendar: calendar)
        #expect(statuses.contains { $0.item.id == "colorectal" && $0.isDue })
    }
}
