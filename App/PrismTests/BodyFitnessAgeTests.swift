//
//  BodyFitnessAgeTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Fitness age is read off the watch's VO2 max against the typical value for
/// each age, and says what it needs when there is no VO2 max to read.
@Suite("Body fitness age")
@MainActor
struct BodyFitnessAgeTests {
    @Test("A VO2 max on a decade's typical value reads as that decade's middle")
    func onTheCurve() {
        #expect(BodyFitnessAge.estimate(vo2Max: 44, sex: .male) == 35)
        #expect(BodyFitnessAge.estimate(vo2Max: 30, sex: .female) == 55)
    }

    @Test("Between two decades the age is read off the straight line joining them")
    func betweenDecades() {
        #expect(BodyFitnessAge.estimate(vo2Max: 42, sex: .male) == 40)
        #expect(BodyFitnessAge.estimate(vo2Max: 24.5, sex: .female) == 70)
    }

    @Test("Past either end the line carries on, and the answer stays between 20 and 90")
    func beyondTheTable() {
        #expect(BodyFitnessAge.estimate(vo2Max: 50, sex: .male) == 20)
        #expect(BodyFitnessAge.estimate(vo2Max: 70, sex: .male) == 20)
        #expect(BodyFitnessAge.estimate(vo2Max: 26, sex: .male) == 80)
        #expect(BodyFitnessAge.estimate(vo2Max: 5, sex: .female) == 90)
    }

    @Test("Without a sex the two curves are averaged")
    func unknownSex() {
        #expect(BodyFitnessAge.estimate(vo2Max: 45, sex: .unknown) == 25)
        #expect(BodyFitnessAge.estimate(vo2Max: 43.4, sex: .unknown) == 29)
    }

    @Test("Without a VO2 max the stat is a dash that says what it needs")
    func needsVO2Max() {
        let stat = BodyFitnessAge.stat(vo2Max: nil, age: 46, sex: .male)
        #expect(stat.value == nil)
        #expect(stat.cue == "Needs VO2 max")
        #expect(!stat.isGood)
    }

    @Test("The age is read against yours when it is known, and stands alone when it is not")
    func againstYourAge() {
        #expect(BodyFitnessAge.stat(vo2Max: 44, age: 46, sex: .male) == .init(value: "35", cue: "11 under your age", isGood: true))
        #expect(BodyFitnessAge.stat(vo2Max: 44, age: 35, sex: .male) == .init(value: "35", cue: "Your age"))
        #expect(BodyFitnessAge.stat(vo2Max: 36, age: 46, sex: .male) == .init(value: "55", cue: "9 over your age"))
        #expect(BodyFitnessAge.stat(vo2Max: 44, age: nil, sex: .male) == .init(value: "35", cue: nil))
    }

    @Test("The Body overview carries the fitness age from the latest VO2 max in Health")
    func overviewCarriesIt() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func vo2(_ value: Double, daysAgo: Double) -> HealthReading {
            let date = now.addingTimeInterval(-daysAgo * 86_400)
            return HealthReading(metric: BodyMetric.vo2Max, value: value, unit: .none, start: date, end: date)
        }
        let page = BodyOverview.make(from: BodyOverviewInputs(
            now: now, vo2Max: [vo2(40, daysAgo: 60), vo2(44, daysAgo: 2)], age: 46, sex: .male
        ))
        #expect(page.fitnessAge.value == "35")
        #expect(BodyOverview.make(from: BodyOverviewInputs(now: now, age: 46)).fitnessAge.cue == "Needs VO2 max")
    }
}
