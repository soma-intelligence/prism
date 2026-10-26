//
//  MetricCoachingTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Metric coaching")
struct MetricCoachingTests {
    private func advice(_ identifier: String, _ value: Double?, secondary: Double? = nil,
                        usual: ClosedRange<Double>? = nil, age: Int? = nil, sex: BiologicalSex? = nil) -> MetricCoachingAdvice? {
        MetricCoaching.advice(for: identifier, value: value, secondary: secondary, usual: usual, age: age, sex: sex)
    }

    @Test("Which way is better never contradicts MetricProfile")
    func directionMatchesProfile() throws {
        for identifier in MetricCoaching.covered {
            let coaching = try #require(advice(identifier, nil, usual: 10...20), "\(identifier)")
            let profile = MetricProfile.of(identifier)
            switch profile.risingIsGood {
            case true: #expect(coaching.direction == .higher, "\(identifier)")
            case false: #expect(coaching.direction == .lower, "\(identifier)")
            default:
                #expect(coaching.direction == .range || coaching.direction == .trend, "\(identifier)")
                if profile.referenceBand != nil { #expect(coaching.direction == .range, "\(identifier)") }
            }
        }
    }

    @Test("A fixed band in MetricProfile is the coaching's adult target")
    func targetsMatchReferenceBands() throws {
        for identifier in MetricCoaching.covered {
            guard let band = MetricProfile.of(identifier).referenceBand else { continue }
            let coaching = try #require(advice(identifier, nil))
            #expect(coaching.target == band, "\(identifier)")
        }
    }

    @Test("Every zone scale runs low to high without gaps")
    func zonesTouch() throws {
        for identifier in MetricCoaching.covered {
            let coaching = try #require(advice(identifier, nil, usual: 10...20, age: 40, sex: .female))
            for (low, high) in zip(coaching.zones, coaching.zones.dropFirst()) {
                #expect(low.upper == high.lower, "\(identifier) \(low.name)")
                #expect(low.lower < low.upper, "\(identifier) \(low.name)")
            }
        }
    }

    @Test("HRV reads against its age band")
    func hrvAgeBands() throws {
        #expect(MetricCoaching.hrvBand(age: 25) == 40...80)
        #expect(MetricCoaching.hrvBand(age: 35) == 35...70)
        #expect(MetricCoaching.hrvBand(age: 45) == 30...60)
        #expect(MetricCoaching.hrvBand(age: 55) == 25...50)
        #expect(MetricCoaching.hrvBand(age: 65) == 20...45)
        #expect(MetricCoaching.hrvBand(age: 80) == 18...40)

        let low = try #require(advice(MetricCoaching.hrv, 37, age: 28))
        #expect(low.zone?.name == "Low")
        #expect(low.zone?.tone == .fair)
        #expect(low.verdict.hasPrefix("Your 37 ms is below the usual range at 20 to 29."))
        // The same 37 ms is typical in the fifties.
        #expect(try #require(advice(MetricCoaching.hrv, 37, age: 52)).zone?.name == "Typical")
        #expect(try #require(advice(MetricCoaching.hrv, 90, age: 52)).zone?.name == "High")
    }

    @Test("VO2 max reads against age and sex")
    func vo2BySexAndAge() throws {
        #expect(MetricCoaching.vo2Percentiles(age: 35, sex: .male).middle == 42.4)
        #expect(MetricCoaching.vo2Percentiles(age: 35, sex: .female).middle == 30.9)
        #expect(MetricCoaching.vo2Percentiles(age: 72, sex: .male).middle == 24.4)
        #expect(MetricCoaching.vo2Percentiles(age: 15, sex: .female).middle == 37.6)
        let other = MetricCoaching.vo2Percentiles(age: 35, sex: .other)
        #expect(abs(other.middle - (42.4 + 30.9) / 2) < 0.001)

        // 38 is above average for a woman in her thirties, below for a man.
        #expect(try #require(advice(MetricCoaching.vo2Max, 38, age: 34, sex: .female)).zone?.name == "High")
        #expect(try #require(advice(MetricCoaching.vo2Max, 38, age: 34, sex: .male)).zone?.name == "Below average")
        #expect(try #require(advice(MetricCoaching.vo2Max, 30, age: 34, sex: .male)).zone?.tone == .out)
    }

    @Test("Resting heart rate verdicts")
    func restingVerdicts() throws {
        let optimal = try #require(advice(MetricCoaching.restingHeartRate, 58))
        #expect(optimal.zone?.name == "Optimal")
        #expect(optimal.verdict.hasPrefix("Your 58 bpm is in the optimal range."))
        #expect(optimal.clinician == nil)
        #expect(try #require(advice(MetricCoaching.restingHeartRate, 45)).zone?.name == "Athletic")
        let normal = try #require(advice(MetricCoaching.restingHeartRate, 82))
        #expect(normal.zone?.name == "Normal")
        #expect(normal.zone?.tone == .fair)
        let high = try #require(advice(MetricCoaching.restingHeartRate, 105))
        #expect(high.zone?.tone == .out)
        #expect(high.clinician != nil)
        #expect(try #require(advice(MetricCoaching.restingHeartRate, 36)).clinician != nil)
    }

    @Test("Blood pressure categories, AHA 2017")
    func pressureCategories() throws {
        #expect(MetricCoaching.pressureCategory(systolic: 118, diastolic: 78) == .normal)
        #expect(MetricCoaching.pressureCategory(systolic: 125, diastolic: 78) == .elevated)
        #expect(MetricCoaching.pressureCategory(systolic: 135, diastolic: 78) == .stage1)
        #expect(MetricCoaching.pressureCategory(systolic: 118, diastolic: 85) == .stage1)
        #expect(MetricCoaching.pressureCategory(systolic: 142, diastolic: 85) == .stage2)
        #expect(MetricCoaching.pressureCategory(systolic: 125, diastolic: 92) == .stage2)
        #expect(MetricCoaching.pressureCategory(systolic: 185, diastolic: 100) == .crisis)
        #expect(MetricCoaching.pressureCategory(systolic: 85, diastolic: 55) == .low)

        // A diastolic that earns stage 1 puts the marker in stage 1.
        let raised = try #require(advice(MetricProfile.systolic, 118, secondary: 85))
        #expect(raised.zone?.name == "Stage 1")
        #expect(raised.verdict.hasPrefix("Your 118/85 is in stage 1 high blood pressure."))
        #expect(raised.clinician != nil)
        let normal = try #require(advice(MetricProfile.diastolic, 112, secondary: 72))
        #expect(normal.zone?.name == "Normal")
        #expect(normal.clinician == nil)
    }

    @Test("A missing value is a dash, never a zone")
    func missingValue() throws {
        for identifier in MetricCoaching.covered {
            let coaching = try #require(advice(identifier, nil, usual: 10...20))
            #expect(coaching.verdict == "-", "\(identifier)")
            #expect(coaching.zone == nil, "\(identifier)")
            #expect(coaching.marker == nil, "\(identifier)")
            #expect(coaching.clinician == nil, "\(identifier)")
        }
        #expect(advice("HKQuantityTypeIdentifierHeartRate", 60) == nil)
    }

    @Test("Without an age, adult ranges stand in")
    func unknownAge() throws {
        #expect(MetricCoaching.hrvBand(age: nil) == 30...65)
        #expect(try #require(advice(MetricProfile.sleep, nil)).target == 7...9)
        #expect(try #require(advice(MetricCoaching.steps, nil)).target == 7000...10000)
        #expect(try #require(advice(MetricCoaching.steps, nil, age: 70)).target == 6000...8000)
        #expect(try #require(advice(MetricProfile.sleep, nil, age: 70)).target == 7...8)
        let hrv = try #require(advice(MetricCoaching.hrv, 40))
        #expect(hrv.targetLine.contains("for adults"))
        #expect(MetricCoaching.vo2Percentiles(age: nil, sex: .male) == MetricCoaching.vo2Percentiles(age: 45, sex: .male))
    }

    @Test("A trend metric reads against the usual band, and waits for one")
    func trendMetrics() throws {
        let weight = try #require(advice(MetricCoaching.weight, 75, usual: 72...74))
        #expect(weight.direction == .trend)
        #expect(weight.zone?.name == "Above usual")
        #expect(weight.usualLine == nil)
        let early = try #require(advice(MetricCoaching.wristTemperature, 35.4))
        #expect(early.zones.isEmpty)
        #expect(early.verdict != "-")
    }

    @Test("The usual line places the value against the person's band")
    func usualLine() throws {
        let under = try #require(advice(MetricCoaching.hrv, 37, usual: 42...55, age: 40))
        #expect(under.usualLine == "Under your usual of 42 to 55 ms.")
        #expect(under.verdict == "Your 37 ms is in the usual range at 40 to 49. It is under your own usual of 42 to 55 ms.")
        let within = try #require(advice(MetricCoaching.hrv, 48, usual: 42...55, age: 40))
        #expect(within.usualLine == "Within your usual of 42 to 55 ms.")
    }
}
