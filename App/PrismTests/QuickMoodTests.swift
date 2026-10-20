//
//  QuickMoodTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
import HealthExportCore
@testable import Prism

@Suite("Quick mood")
struct QuickMoodTests {
    @Test("The five faces log the evening question's stops, and read back as themselves")
    func roundTrip() {
        #expect(SomaMood.allCases.map(MindQuickMood.stop) == [0, 2, 3, 4, 6])
        for mood in SomaMood.allCases {
            let valence = MindMoodEntry.valence(stop: MindQuickMood.stop(mood))
            #expect(MindQuickMood.mood(valence: valence) == mood)
        }
        #expect(MindQuickMood.mood(valence: MindMoodEntry.valence(stop: 5)) == .good || MindQuickMood.mood(valence: MindMoodEntry.valence(stop: 5)) == .great)
    }

    @Test("What the card says was logged is today's latest mood, logged just now included")
    func latestToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let yesterday = MindMoodEntry(date: now.addingTimeInterval(-86_400), kind: .momentary, valence: -1)
        let morning = MindMoodEntry(date: calendar.startOfDay(for: now).addingTimeInterval(60), kind: .momentary, valence: 0)
        let justNow = MindMoodEntry(date: now.addingTimeInterval(5), kind: .momentary, valence: 1, note: "A walk")
        #expect(MindQuickMood.latestToday([yesterday, morning, justNow], now: now, calendar: calendar) == justNow)
        #expect(MindQuickMood.latestToday([yesterday], now: now, calendar: calendar) == nil)
    }

    @Test("A mood saved before notes existed still reads")
    func oldEntriesDecode() throws {
        let json = #"{"id":"6F1C1C9E-6E2A-4C1B-9E50-1B2C3D4E5F60","date":0,"kind":"momentary","valence":0.5,"labels":[],"associations":[],"isInHealth":false}"#
        let entry = try JSONDecoder().decode(MindMoodEntry.self, from: Data(json.utf8))
        #expect(entry.note == nil)
        #expect(entry.valence == 0.5)
    }
}
