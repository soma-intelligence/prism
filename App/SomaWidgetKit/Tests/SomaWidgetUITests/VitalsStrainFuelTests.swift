import Foundation
import Testing
import SwiftUI
import SomaUI
import SomaWidgetKit
@testable import SomaWidgetUI

struct VitalsStrainFuelTests {
    @Test func sleepFormat() {
        #expect(VitalsText.sleep(hours: 7.2) == "7:12")
        #expect(VitalsText.sleep(hours: nil) == "-")
    }

    @Test func sleepFormatEdges() {
        #expect(VitalsText.sleep(hours: 7.999) == "8:00")
        #expect(VitalsText.sleep(hours: 0) == "0:00")
        #expect(VitalsText.sleep(hours: 6.05) == "6:03")
        #expect(VitalsText.sleep(hours: .nan) == "-")
        #expect(VitalsText.sleep(hours: -1) == "-")
    }

    @Test func vitalNumbersRoundOrDash() {
        #expect(VitalsText.whole(52.4) == "52")
        #expect(VitalsText.whole(nil) == "-")
        #expect(VitalsText.whole(.infinity) == "-")
    }

    @Test func inlineReadsAllThree() {
        let snapshot = SomaWidgetSnapshot.placeholder
        #expect(VitalsText.inline(snapshot) == "52 bpm  64 ms  7:12")
        var missing = snapshot
        missing.hrv.value = nil
        #expect(VitalsText.inline(missing) == "52 bpm  -  7:12")
    }

    @Test func labelsAreShort() {
        #expect(VitalsText.restingLabel == "Resting")
        #expect(VitalsText.hrvLabel == "HRV")
        #expect(VitalsText.sleepLabel == "Sleep")
        #expect(FuelText.burnedLabel == "Burned")
        #expect(FuelText.eatenLabel == "Eaten")
    }

    @Test func netRounds() {
        #expect(FuelText.net(burned: 2310, eaten: 1980) == "-330")
        #expect(FuelText.net(burned: 2000, eaten: 2124) == "+120")
    }

    @Test func netEdges() {
        #expect(FuelText.net(burned: nil, eaten: 1980) == "-")
        #expect(FuelText.net(burned: 2310, eaten: nil) == "-")
        #expect(FuelText.net(burned: 2000, eaten: 2004) == "0")
        #expect(FuelText.net(burned: .nan, eaten: 2000) == "-")
    }

    @Test func kcalReadsWholeOrDash() {
        #expect(FuelText.kcal(2310.4) == "2310")
        #expect(FuelText.kcal(nil) == "-")
    }

    @Test func fuelBarsScaleToTheLarger() {
        let bars = FuelText.fractions(burned: 2310, eaten: 1980)
        #expect(bars.burned == 1)
        #expect(abs((bars.eaten ?? 0) - 1980.0 / 2310.0) < 1e-9)
        let one = FuelText.fractions(burned: nil, eaten: 1980)
        #expect(one.burned == nil)
        #expect(one.eaten == 1)
        let none = FuelText.fractions(burned: 0, eaten: 0)
        #expect(none.burned == 0)
        #expect(none.eaten == 0)
    }

    @Test func fuelReadsOnlyTheSnapshotsOwnDay() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let snapshot = SomaWidgetSnapshot.placeholder
        let sameDay = FuelText.today(snapshot, now: snapshot.generatedAt.addingTimeInterval(3600), calendar: utc)
        #expect(sameDay.burnedKcal == snapshot.burnedKcal)
        #expect(sameDay.eatenKcal == snapshot.eatenKcal)
        // 01:00 the next day: yesterday's totals must not read as today's.
        let nextDay = FuelText.today(snapshot, now: snapshot.generatedAt.addingTimeInterval(13 * 3600), calendar: utc)
        #expect(nextDay.burnedKcal == nil)
        #expect(nextDay.eatenKcal == nil)
        #expect(FuelText.net(burned: nextDay.burnedKcal, eaten: nextDay.eatenKcal) == "-")
        #expect(FuelText.kcal(nextDay.burnedKcal) == "-")
    }

    @Test func axisReachesNowOnAnOldSnapshot() throws {
        let snapshot = SomaWidgetSnapshot.placeholder
        let now = snapshot.generatedAt.addingTimeInterval(5 * 3600)
        let axis = try #require(EnergyAxis.bounds(snapshot, now: now))
        #expect(axis.upperBound == now)
        let fraction = EnergyAxis.nowFraction(
            curve: snapshot.energyCurve, start: axis.lowerBound, end: axis.upperBound,
            now: now.addingTimeInterval(-3600)
        )
        #expect(fraction < 1)
    }

    @Test func nowFractionClamps() {
        let curve = SomaWidgetSnapshot.placeholder.energyCurve
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(3600)
        #expect(EnergyAxis.nowFraction(curve: curve, start: start, end: end, now: start.addingTimeInterval(-60)) == 0)
        #expect(EnergyAxis.nowFraction(curve: curve, start: start, end: end, now: end.addingTimeInterval(60)) == 1)
        #expect(EnergyAxis.nowFraction(curve: curve, start: start, end: end, now: start.addingTimeInterval(1800)) == 0.5)
    }

    @Test func nowFractionFallsBackToTheCurveSpan() throws {
        let curve = SomaWidgetSnapshot.placeholder.energyCurve
        let first = try #require(curve.first).date
        let last = try #require(curve.last).date
        let middle = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
        #expect(EnergyAxis.nowFraction(curve: curve, start: last, end: last, now: middle) == 0.5)
        #expect(EnergyAxis.nowFraction(curve: [], start: last, end: last, now: middle) == 1)
    }

    @Test func axisRunsFromBedtimeToTheLastEntry() throws {
        let snapshot = SomaWidgetSnapshot.placeholder
        let axis = try #require(EnergyAxis.bounds(snapshot, now: snapshot.generatedAt))
        #expect(axis.lowerBound == snapshot.sleepBand?.lowerBound)
        #expect(axis.upperBound == snapshot.generatedAt.addingTimeInterval(StrainTimeline.horizon))
    }

    @Test func energyLevelBetweenPointsAndHeldAfter() throws {
        let curve = SomaWidgetSnapshot.placeholder.energyCurve
        let last = try #require(curve.last)
        #expect(EnergyAxis.level(curve: curve, at: last.date.addingTimeInterval(3600)) == last.level)
        let a = curve[3], b = curve[4]
        let mid = a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) / 2)
        let expected = (a.level + b.level) / 2
        #expect(abs((EnergyAxis.level(curve: curve, at: mid) ?? 0) - expected) < 1e-9)
        #expect(EnergyAxis.level(curve: [], at: mid) == nil)
    }

    @Test func hypnogramRowsAndOpacities() {
        #expect(Hypnogram.rows == [.awake, .rem, .core, .deep])
        let metrics = SomaMetrics.touch
        #expect(Hypnogram.opacity(.awake, metrics) == 1.0)
        #expect(Hypnogram.opacity(.rem, metrics) == 0.7)
        #expect(Hypnogram.opacity(.core, metrics) == 0.45)
        #expect(Hypnogram.opacity(.deep, metrics) == 0.25)
        #expect(metrics.widgetBandOpacity == 0.06)
    }

    @Test func accessibilityAddsUnitsAndAge() {
        let snapshot = SomaWidgetSnapshot.placeholder
        #expect(VitalsText.accessibility(snapshot, .fresh) == "Resting 52 bpm, HRV 64 ms, Sleep 7:12")
        #expect(FuelText.accessibility(snapshot, .stale(hours: 14)) == "Net -330 kcal, Burned 2310, Eaten 1980, 14 h ago")
    }

    @Test func lineKeepsOnlyPointsOnTheAxis() throws {
        let snapshot = SomaWidgetSnapshot.placeholder
        let axis = try #require(EnergyAxis.bounds(snapshot, now: snapshot.generatedAt))
        var early = snapshot
        early.energyCurve.insert(
            SomaWidgetSnapshot.EnergyPoint(date: axis.lowerBound.addingTimeInterval(-3600), level: 20), at: 0
        )
        let points = EnergyAxis.linePoints(early, axis: axis)
        #expect(points.count == snapshot.energyCurve.count)
        #expect(points.allSatisfy { $0.x >= 0 && $0.x <= 1 })
    }

    @Test func dotFollowsTheHeader() {
        var snapshot = SomaWidgetSnapshot.placeholder
        let later = snapshot.generatedAt.addingTimeInterval(3600)
        #expect(EnergyAxis.dotLevel(snapshot, now: snapshot.generatedAt) == snapshot.energyNow)
        #expect(EnergyAxis.dotLevel(snapshot, now: later) == snapshot.energyNow)
        snapshot.energyNow = nil
        #expect(EnergyAxis.dotLevel(snapshot, now: later) == nil)
    }

    @Test func smoothLinePassesThroughEveryPoint() {
        let points = [CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 5), CGPoint(x: 30, y: 5)]
        var path = Path()
        SmoothLine.add(points, to: &path)
        #expect(path.currentPoint == points.last)
        #expect(!path.isEmpty)
    }

    @Test func smoothTangentsDoNotOvershoot() {
        // Monotone: a flat or turning point gets a flat tangent, so the curve
        // never leaves the range of the values around it.
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)]
        let slopes = SmoothLine.tangents(points)
        #expect(slopes[1] == 0)
    }
}
