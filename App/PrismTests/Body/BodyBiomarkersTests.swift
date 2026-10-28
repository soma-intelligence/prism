//
//  BodyBiomarkersTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

@Suite("Body biomarkers")
struct BodyBiomarkersTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func reading(_ value: Double, daysAgo: Int, unit: HealthUnit = .countPerMinute) -> HealthReading {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return HealthReading(metric: "x", value: value, unit: unit, start: date, end: date)
    }

    @Test("Days are bucketed oldest first, a day with no reading is nil")
    func dailyBuckets() {
        let days = BodyBiomarkers.daily(.restingHeartRate, readings: [reading(60, daysAgo: 0), reading(62, daysAgo: 0), reading(58, daysAgo: 2)], days: 3, now: now, calendar: calendar)
        #expect(days == [58, nil, 61])
    }

    @Test("Steps add up per day instead of averaging")
    func stepsSum() {
        let days = BodyBiomarkers.daily(.stepCount, readings: [reading(1000, daysAgo: 0), reading(500, daysAgo: 0)], days: 1, now: now, calendar: calendar)
        #expect(days == [1500])
    }

    @Test("A fraction from Health shows as a percent")
    func percent() {
        #expect(BodyBiomarkerSpec.bodyFatPercentage.display(0.187) == 18.7)
    }

    @Test("Three high days against a steady usual read as above normal")
    func aboveUsual() {
        var all: [Double?] = Array(repeating: 55, count: 60)
        all += [55, 55, 55, 55, 70, 71, 72]
        #expect(BodyBiomarkers.status(.restingHeartRate, all: all, latest: 72) == .above)
    }

    @Test("A steady run reads normal, and too little history reads nothing")
    func normalAndNone() {
        let steady: [Double?] = Array(repeating: 55, count: 40)
        #expect(BodyBiomarkers.status(.restingHeartRate, all: steady, latest: 55) == .normal)
        #expect(BodyBiomarkers.status(.restingHeartRate, all: [55, 56], latest: 56) == .none)
    }

    @Test("Body composition reads as a direction")
    func direction() {
        let rising: [Double?] = [70, 70.5, 71, 71.5, 72]
        #expect(BodyBiomarkers.status(.bodyMass, all: rising, latest: 72) == .increasing)
    }

    @Test("Every identifier names a metric the catalog knows")
    func identifiersResolve() {
        for spec in BodyBiomarkerSpec.allCases {
            #expect(HealthMetricCatalog.metric(for: spec.identifier) != nil, "\(spec.identifier)")
        }
    }

    // MARK: Status colour, by which side is better

    /// How the status word is coloured: green for good news, amber for worth
    /// a look. A plain above or below carries no direction and reads amber.
    private func tone(_ status: SomaReadingStatus) -> SomaCueTone? {
        switch status {
        case .outside(let side, let better): better.tone(side)
        case .above, .below: .watch
        default: nil
        }
    }

    @Test("Heart rate recovery above its usual reads as good news, not a warning")
    func recoveryAboveIsGood() {
        let status = BodyBiomarker.Status.above.reading(BodyBiomarkerSpec.heartRateRecoveryOneMinute.policy.preference)
        #expect(tone(status) == .good)
    }

    @Test("HRV below its usual and resting heart rate above it read as worth a look")
    func watchSides() {
        let hrv = BodyBiomarker.Status.below.reading(BodyBiomarkerSpec.heartRateVariabilitySDNN.policy.preference)
        let resting = BodyBiomarker.Status.above.reading(BodyBiomarkerSpec.restingHeartRate.policy.preference)
        #expect(tone(hrv) == .watch)
        #expect(tone(resting) == .watch)
    }

    @Test("A reading kept near its usual reads as worth a look on either side")
    func steadyEitherSide() {
        let preference = BodyBiomarkerSpec.respiratoryRate.policy.preference
        #expect(tone(BodyBiomarker.Status.above.reading(preference)) == .watch)
        #expect(tone(BodyBiomarker.Status.below.reading(preference)) == .watch)
    }
}
