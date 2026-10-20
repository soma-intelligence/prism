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

    @Test("Both sides of the rendered figure load, the same size, every mask inside")
    func figureLoads() throws {
        let front = try #require(SomaMuscleFigureArt.front)
        let back = try #require(SomaMuscleFigureArt.back)
        #expect(front.size == back.size)
        #expect(front.size.height > front.size.width)
        let bounds = CGRect(origin: .zero, size: front.size)
        for art in [front, back] {
            #expect(art.image.width == Int(art.size.width))
            for mask in art.masks {
                #expect(bounds.contains(mask.frame), "\(mask.muscle) \(art.side)")
                #expect(mask.coverage.count == mask.image.width * mask.image.height)
            }
        }
    }

    @Test("Every muscle shows on one side at least, each where it should")
    func everyMuscleShows() throws {
        let front = try #require(SomaMuscleFigureArt.front)
        let back = try #require(SomaMuscleFigureArt.back)
        let shown = Set(front.masks.map(\.muscle)).union(back.masks.map(\.muscle))
        #expect(shown == Set(SomaMuscle.allCases))
        let onFront = Set(front.masks.map(\.muscle))
        let onBack = Set(back.masks.map(\.muscle))
        for muscle in [SomaMuscle.chest, .abs, .quads, .biceps] { #expect(onFront.contains(muscle), "\(muscle)") }
        for muscle in [SomaMuscle.lats, .glutes, .hamstrings, .lowerBack, .triceps] { #expect(onBack.contains(muscle), "\(muscle)") }
    }

    @Test("A tap on a muscle names it; a tap off the figure names nothing")
    func hitTesting() throws {
        let size = CGSize(width: 200, height: 480)
        for (side, muscle) in [(SomaMuscleFigureArt.Side.front, SomaMuscle.chest), (.back, .glutes)] {
            let art = try #require(SomaMuscleFigureArt.of(side))
            let mask = try #require(art.masks.first { $0.muscle == muscle })
            // The mask's most covered pixel, mapped to the frame.
            let width = Int(mask.frame.width)
            let index = try #require(mask.coverage.indices.max { mask.coverage[$0] < mask.coverage[$1] })
            let pixel = CGPoint(x: mask.frame.minX + CGFloat(index % width) + 0.5, y: mask.frame.minY + CGFloat(index / width) + 0.5)
            let rect = art.fit(in: size)
            let point = CGPoint(x: rect.minX + pixel.x / art.size.width * rect.width,
                                y: rect.minY + pixel.y / art.size.height * rect.height)
            #expect(art.muscle(at: point, in: size) == muscle)
            #expect(art.muscle(at: CGPoint(x: 1, y: 1), in: size) == nil)
        }
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

    @Test("The chest takes its own deeper tone in every state, and none without data")
    func chestStandsOut() {
        for state in [SomaMuscleState.recovered, .fatigued, .depleted] {
            #expect(state.chestTone != nil)
            #expect(state.chestTone != state.tone)
        }
        #expect(SomaMuscleState.none.chestTone == nil)
    }
}
