import Foundation
import Testing
import SomaWidgetKit
@testable import SomaWidgetUI

struct ScoresLogicTests {
    @Test func ringValueNilShowsDash() { #expect(ScoreText.value(nil) == "-") }

    @Test func ringValueRounds() { #expect(ScoreText.value(81.6) == "82") }

    @Test func ringValueZeroIsZeroNotDash() { #expect(ScoreText.value(0) == "0") }

    @Test func ringValueClampsACorruptValue() {
        #expect(ScoreText.value(1e30) == "100")
        #expect(ScoreText.value(-1e30) == "0")
        #expect(ScoreText.value(.infinity) == "-")
        #expect(ScoreText.value(.nan) == "-")
    }

    @Test func accessibilityReadsTheAgeWhenStale() {
        let value = SomaWidgetSnapshot.placeholder.recovery.value
        #expect(ScoreText.accessibility(.recovery, value, .fresh) == "Recovery 82")
        #expect(ScoreText.accessibility(.recovery, value, .stale(hours: 6)) == "Recovery 82, 6 h ago")
        #expect(ScoreText.accessibility(.sleep, nil, .fresh) == "Sleep -")
    }

    @Test func labelsAreOneShortWord() {
        #expect(ScoreText.label(.sleep) == "Sleep")
        #expect(ScoreText.label(.recovery) == "Recovery")
        #expect(ScoreText.label(.strain) == "Strain")
        #expect(ScoreText.label(.stress) == "Stress")
    }

    @Test func fractionIsClampedAndNilStaysNil() {
        #expect(ScoreText.fraction(nil) == nil)
        #expect(ScoreText.fraction(82) == 0.82)
        #expect(ScoreText.fraction(140) == 1)
        #expect(ScoreText.fraction(-5) == 0)
    }

    @Test func staleAgeReadsHours() {
        #expect(StaleAge.text(.fresh) == nil)
        #expect(StaleAge.text(.stale(hours: 6)) == "6 h ago")
        #expect(StaleAge.text(.stale(hours: 30)) == "30 h ago")
    }

    @Test func scoreReadsTheRightField() {
        let snapshot = SomaWidgetSnapshot.placeholder
        #expect(snapshot.score(.sleep) == snapshot.sleep)
        #expect(snapshot.score(.recovery) == snapshot.recovery)
        #expect(snapshot.score(.strain) == snapshot.strain)
        #expect(snapshot.score(.stress) == snapshot.stress)
    }

    @Test func displayStateEmptyWithoutData() {
        let now = SomaWidgetSnapshot.placeholder.generatedAt
        #expect(WidgetDisplay(snapshot: nil, now: now) == .empty)
        var blank = SomaWidgetSnapshot.placeholder
        blank.hasData = false
        #expect(WidgetDisplay(snapshot: blank, now: now) == .empty)
        #expect(WidgetDisplay(snapshot: .placeholder, now: now) == .data(.fresh))
        let later = now.addingTimeInterval(14 * 3600)
        #expect(WidgetDisplay(snapshot: .placeholder, now: later) == .data(.stale(hours: 14)))
    }

    @Test func traceNormalisesAndKeepsGaps() {
        let points = HairlineTrace.normalised([10, nil, 30, 20])
        #expect(points == [0, nil, 1, 0.5])
        #expect(HairlineTrace.normalised([5, 5]) == [0.5, 0.5])
        #expect(HairlineTrace.normalised([nil, nil]) == [nil, nil])
    }
}
