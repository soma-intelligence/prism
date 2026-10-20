//
//  SomaMuscleFreshnessTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Muscle freshness")
struct SomaMuscleFreshnessTests {
    @Test("Every drawn muscle belongs to exactly one group")
    func groupsCoverTheMap() {
        for muscle in SomaMuscle.allCases {
            let owners = SomaMuscleGroup.allCases.filter { $0.muscles.contains(muscle) }
            #expect(owners.count == 1, "\(muscle)")
            #expect(SomaMuscleGroup.of(muscle) == owners.first)
        }
    }

    @Test("States read in calm tones, no data keeps the figure's grey")
    func tones() {
        #expect(SomaMuscleState.recovered.tone == SomaEnergyRamp.charge)
        #expect(SomaMuscleState.none.tone == nil)
        #expect(SomaMuscleState.fatigued.tone != SomaMuscleState.depleted.tone)
    }

    @Test("A tap on a muscle names it; a tap off the figure names nothing")
    func hitTesting() {
        let art = MuscleArtFigure.front
        let size = CGSize(width: 200, height: 400)
        let fit = art.fit(in: size)
        let chest = art.parts.first { $0.muscle == .chest }!
        let box = chest.path.boundingRect
        // A point inside the chest's own outline, in the frame's space.
        var inside: CGPoint?
        search: for fx in stride(from: 0.3, through: 0.7, by: 0.1) {
            for fy in stride(from: 0.3, through: 0.7, by: 0.1) {
                let local = CGPoint(x: box.minX + box.width * fx, y: box.minY + box.height * fy)
                if chest.path.contains(local) {
                    inside = CGPoint(x: local.x * fit.scale + fit.offset.x, y: local.y * fit.scale + fit.offset.y)
                    break search
                }
            }
        }
        #expect(inside.map { art.muscle(at: $0, in: size) } == .chest)
        #expect(art.muscle(at: CGPoint(x: 1, y: 1), in: size) == nil)
    }

    @Test("The card's line counts rested groups, leaving out those with no data")
    func summary() {
        func reading(_ group: SomaMuscleGroup, _ state: SomaMuscleState) -> SomaMuscleReading {
            SomaMuscleReading(group: group, state: state)
        }
        #expect(String(localized: SomaMuscleFreshness.summary([])) == "No workouts yet")
        #expect(String(localized: SomaMuscleFreshness.summary([reading(.legs, .recovered), reading(.arms, .recovered)])) == "All rested")
        #expect(String(localized: SomaMuscleFreshness.summary([reading(.legs, .depleted), reading(.arms, .recovered), reading(.back, .none)])) == "1 of 2 rested")
    }

    @Test("Time since a session and until fresh, in a few words")
    func times() {
        #expect(SomaMuscleTime.ago(3 * 3_600) == "today")
        #expect(SomaMuscleTime.ago(30 * 3_600) == "yesterday")
        #expect(SomaMuscleTime.ago(3 * 86_400) == "3 days ago")
        #expect(SomaMuscleTime.span(6 * 3_600) == "about 6 hours")
        #expect(SomaMuscleTime.span(26 * 3_600) == "about a day")
        #expect(SomaMuscleTime.span(52 * 3_600) == "about 2 days")
    }
}
