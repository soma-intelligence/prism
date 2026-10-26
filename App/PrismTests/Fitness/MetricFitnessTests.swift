//
//  MetricFitnessTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The fitness engines behind the metric pages (lane 4b): zones, cardio load,
/// cardio focus, heart rate recovery, muscle work, strain against its target,
/// sound exposure, steps and routes. A fixed calendar keeps every day
/// boundary the same on every machine.
@Suite("Metric fitness")
@MainActor
struct MetricFitnessTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Tuesday 29 September 2026 at noon.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))! }

    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func reading(_ value: Double, at date: Date, lasting seconds: TimeInterval = 0, metric: String = "m") -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .none, start: date, end: date.addingTimeInterval(seconds))
    }

    func workout(_ activity: Int, at date: Date, minutes: Double, zones: [Double] = [0, 0, 0, 0, 0]) -> FitnessWorkout {
        FitnessWorkout(start: date, end: date.addingTimeInterval(minutes * 60), activity: activity, zoneSeconds: zones)
    }

    // MARK: - Zones

    @Test("A heart rate lands in the zone its share of the highest names")
    func zones() {
        #expect(FitnessZones.zone(for: 90, maxHeartRate: 200) == nil)
        #expect(FitnessZones.zone(for: 100, maxHeartRate: 200) == 1)
        #expect(FitnessZones.zone(for: 125, maxHeartRate: 200) == 2)
        #expect(FitnessZones.zone(for: 140, maxHeartRate: 200) == 3)
        #expect(FitnessZones.zone(for: 185, maxHeartRate: 200) == 5)
        let ranges = FitnessZones.ranges(maxHeartRate: 174)
        #expect(ranges?.first == 87...104)
        #expect(ranges?.last == 157...174)
        #expect(FitnessZones.ranges(maxHeartRate: nil) == nil)
    }

    @Test("Every displayed integer belongs to exactly its classified zone", arguments: [125.0, 174.0, 180.0, 200.0, 207.5])
    func zoneRangesMatchClassification(maxHeartRate: Double) throws {
        let ranges = try #require(FitnessZones.ranges(maxHeartRate: maxHeartRate))
        for bpm in 1...Int(maxHeartRate.rounded(.down)) {
            let containing = ranges.indices.filter { ranges[$0].contains(bpm) }
            if let zone = FitnessZones.zone(for: Double(bpm), maxHeartRate: maxHeartRate) {
                #expect(containing == [zone - 1])
            } else {
                #expect(containing.isEmpty)
            }
        }
    }

    @Test("Each sample holds until the next one, capped at a minute")
    func zoneSeconds() {
        let start = daysAgo(1)
        let samples = [reading(130, at: start), reading(130, at: start.addingTimeInterval(30)), reading(95, at: start.addingTimeInterval(300))]
        let split = FitnessZones.seconds(samples: samples, start: start, end: start.addingTimeInterval(330), maxHeartRate: 200)
        // 130 of 200 is zone 2: 30 s, then 60 s capped; 95 is calm for 30 s.
        #expect(split.zones[1] == 90)
        #expect(split.calm == 30)
    }

    // MARK: - Cardio load

    @Test("TRIMP weighs each zone minute by the zone's number")
    func trimp() {
        #expect(TrainingLoad.trimp(zoneSeconds: [600, 600, 0, 0, 60]) == 10 + 20 + 5)
    }

    @Test("The ratio cut points decide the status")
    func loadStatus() {
        #expect(TrainingLoad.status(acute: 10, chronic: 2) == .calibrating)
        #expect(TrainingLoad.status(acute: 70, chronic: 100) == .detraining)
        #expect(TrainingLoad.status(acute: 90, chronic: 100) == .maintaining)
        #expect(TrainingLoad.status(acute: 140, chronic: 100) == .productive)
        #expect(TrainingLoad.status(acute: 160, chronic: 100) == .tooMuch)
    }

    @Test("Daily load buckets workouts by day, rest days at zero")
    func dailyLoad() {
        let workouts = [workout(37, at: daysAgo(0.1), minutes: 30, zones: [0, 1800, 0, 0, 0]),
                        workout(37, at: daysAgo(2), minutes: 10, zones: [600, 0, 0, 0, 0])]
        let daily = TrainingLoad.dailyTrimp(workouts, days: 5, now: now, calendar: calendar)
        #expect(daily == [0, 0, 10, 0, 60])
    }

    @Test("Steady training sits in the band; a spike above it reads as too much")
    func loadModel() {
        let steady = Array(repeating: 50.0, count: 60)
        let model = TrainingLoad.model(daily: steady, shown: 30)
        #expect(model?.todayStatus == .productive)
        #expect(model?.acute.count == 30)
        #expect(model.map { $0.todayBand.contains($0.today) } == true)

        let spiked = steady + Array(repeating: 200.0, count: 7)
        #expect(TrainingLoad.model(daily: spiked, shown: 30)?.todayStatus == .tooMuch)
        #expect(TrainingLoad.model(daily: spiked, shown: 30)?.longestSpike != nil)
        #expect(TrainingLoad.model(daily: [0, 0, 0], shown: 30) == nil)
    }

    // MARK: - Cardio focus

    @Test("Zones 1 and 2 are low aerobic, 3 and 4 high, 5 anaerobic")
    func cardioFocus() {
        let focus = CardioFocus(zoneMinutes: [200, 50, 40, 18, 3])
        #expect(focus.minutes(.low) == 250)
        #expect(focus.minutes(.high) == 58)
        #expect(focus.percent(.low) == 80)
        #expect(focus.percent(.anaerobic) == 1)
    }

    @Test("Only workouts inside the week count")
    func cardioFocusWindow() {
        let week = DateInterval(start: daysAgo(7), end: now)
        let focus = CardioFocus(
            workouts: [workout(37, at: daysAgo(1), minutes: 30, zones: [0, 1800, 0, 0, 0]),
                       workout(37, at: daysAgo(9), minutes: 30, zones: [0, 1800, 0, 0, 0])],
            in: week
        )
        #expect(focus.zoneMinutes[1] == 30)
    }

    // MARK: - Heart rate recovery

    @Test("Cole's bands and a rising trend")
    func recovery() {
        #expect(HeartRateRecovery.band(11) == .poor)
        #expect(HeartRateRecovery.band(15) == .fair)
        #expect(HeartRateRecovery.band(28) == .good)
        #expect(HeartRateRecovery.band(35) == .excellent)

        let rising = (0..<6).map { reading(20 + Double($0), at: daysAgo(Double(30 - $0 * 6))) }
        let slope = HeartRateRecovery.monthlySlope(rising)
        #expect(slope.map { abs($0 - 5) < 0.01 } == true)
        #expect(HeartRateRecovery.monthlySlope(Array(rising.prefix(4))) == nil)
    }

    @Test("The recovery reading after a workout is the one nearest its end")
    func recoveryAfterWorkout() {
        let run = workout(37, at: daysAgo(1), minutes: 40)
        let near = reading(28, at: run.end.addingTimeInterval(90))
        let far = reading(20, at: run.end.addingTimeInterval(3600))
        #expect(HeartRateRecovery.reading(after: run, in: [near, far]) == near)
    }

    // MARK: - Muscle work

    @Test("Zones outweigh MET, and MET stands in without heart rate")
    func workPoints() {
        #expect(MuscleWork.points(zoneSeconds: [0, 600, 0, 0, 0], calmSeconds: 0, duration: 600, met: 3) == 10)
        #expect(MuscleWork.points(zoneSeconds: [], calmSeconds: 0, duration: 600, met: 3) == 5)
        #expect(MuscleWork.points(zoneSeconds: [], calmSeconds: 0, duration: 0, met: 3) == 0)
    }

    @Test("A run loads the legs, a strength session splits wider")
    func muscleWork() {
        let work = MuscleWork(workouts: [
            workout(37, at: daysAgo(2), minutes: 30, zones: [0, 1800, 0, 0, 0]),
            workout(83, at: daysAgo(1), minutes: 10),
        ])
        #expect(work.share(MuscleWork.Group.legs).map { abs($0 - 0.75) < 0.001 } == true)
        #expect(work.unattributed == 1)
        #expect(work.ranked.first == .legs)
        #expect(MuscleWork(workouts: []).share(MuscleWork.Group.legs) == nil)
    }

    @Test("Every activity split sums to one")
    func activitySplits() {
        for activity in FitnessActivities.table.values where !activity.shares.isEmpty {
            let sum = activity.shares.values.reduce(0, +)
            #expect(abs(sum - 1) < 0.001, "\(activity.name) sums to \(sum)")
        }
    }

    // MARK: - Strain

    @Test("Finished days count against the target, today does not")
    func strainStudy() {
        let study = StrainStudy(series: [10, 40, 60, 80, nil, 0, 5], target: 40...70)
        #expect(study.below == 1)
        #expect(study.inside == 2)
        #expect(study.above == 1)
        #expect(StrainStudy.average([nil, 10, 20], days: 7) == 15)
    }

    // MARK: - Sound

    @Test("A day's level is weighted by how long each sample held")
    func soundMean() {
        let readings = [reading(60, at: daysAgo(0.1), lasting: 300), reading(90, at: daysAgo(0.1), lasting: 100)]
        #expect(SoundExposure.mean(readings) == 67.5)
        #expect(SoundExposure.timeAbove(80, in: readings) == 100)
    }

    @Test("Forty hours at 80 dB is a whole safe week; 3 dB louder halves it")
    func soundDose() {
        let week = reading(80, at: daysAgo(3), lasting: 40 * 3600)
        #expect(abs(SoundExposure.weeklyDose([week]) - 1) < 0.0001)
        let louder = reading(83, at: daysAgo(3), lasting: 20 * 3600)
        #expect(abs(SoundExposure.weeklyDose([louder]) - 1) < 0.0001)
    }

    @Test("Changes read as signed decibels, Level under half a decibel")
    func soundChange() {
        #expect(SoundExposure.changeText(0.3) == "Level")
        #expect(SoundExposure.changeText(1.2) == "+1 dB")
        #expect(SoundExposure.changeText(nil) == "-")
        #expect(SoundExposure.duration(14 * 60) == "14 min")
        #expect(SoundExposure.duration(680 * 60) == "11 h 20")
    }

    // MARK: - Steps

    @Test("Weeks average the days counted, newest first")
    func stepWeeks() {
        var totals: [Date: Double] = [:]
        for back in 0..<14 {
            let day = calendar.startOfDay(for: daysAgo(Double(back)))
            totals[day] = back < 2 ? 10_000 : 6_000
        }
        let weeks = StepsMath.weeks(totals, count: 2, now: now, calendar: calendar)
        #expect(weeks.first?.isCurrent == true)
        #expect(weeks.first?.perDay == 10_000)
        #expect(weeks.last?.perDay == 6_000)
    }

    @Test("The month adds up day by day")
    func stepMonth() {
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let totals = [first: 1_000.0, calendar.startOfDay(for: now): 2_000]
        let curve = StepsMath.monthToDate(totals, now: now, calendar: calendar)
        #expect(curve.count == 29)
        #expect(curve.first == 1_000)
        #expect(curve.last == 3_000)
    }

    // MARK: - Territory

    @Test("Routes gather into places, and home is the common start")
    func territory() {
        func route(_ lat: Double, _ lon: Double, at date: Date, climb: Double = 0) -> Territory.Route {
            Territory.Route(start: date, end: date.addingTimeInterval(1800), activity: 52, points: [
                .init(latitude: lat, longitude: lon, altitude: 10),
                .init(latitude: lat + 0.01, longitude: lon, altitude: 10 + climb),
            ])
        }
        let routes = [route(37.44, -122.14, at: daysAgo(3), climb: 40),
                      route(37.44, -122.14, at: daysAgo(2)),
                      route(37.40, -122.18, at: daysAgo(1))]
        #expect(Territory.places(routes).count == 2)
        #expect(Territory.home(routes)?.latitude == 37.44)
        #expect(Territory.fromDoor(routes, home: Territory.home(routes)) == 2)
        #expect(abs(routes[0].distance - 1112) < 5)
        #expect(routes[0].climb == 40)
    }

    // MARK: - Routines

    @Test("A routine counts its sets without the warm-up")
    func routines() {
        #expect(TrainingRoutines.upperBody.exerciseCount == 5)
        #expect(TrainingRoutines.upperBody.sets == 14)
        #expect(TrainingRoutines.routine("lower")?.name == "Lower body")
    }
}
