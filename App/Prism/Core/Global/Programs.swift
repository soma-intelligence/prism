//
//  Programs.swift
//  Prism
//

import Foundation
import SomaUI

/// A guided program: a few weeks, one small ask a day.
///
/// A program has a name, a length, the ask, a way in and a way out, kept as one
/// plain catalog, so joining and leaving are the same two taps for every program.
nonisolated struct Program: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    /// What the program asks of you each day it runs.
    let dailyAsk: String
    let days: Int
    let aspect: SomaAspect

    /// Weeks, when the program counts in weeks.
    var weeks: Int { days / 7 }
    var countsInWeeks: Bool { days > 14 }

    var lengthText: String {
        weeks == 1 ? String(localized: "1 week") : String(localized: "\(weeks) weeks")
    }
}

nonisolated enum ProgramCatalog {
    static let all: [Program] = [
        Program(id: "sleep-debt-reset", title: String(localized: "Sleep debt reset"),
                summary: String(localized: "Pay back short nights, twenty minutes at a time"),
                dailyAsk: String(localized: "In bed twenty minutes earlier than your usual tonight."),
                days: 14, aspect: .sleep),
        Program(id: "zone-two-base", title: String(localized: "Zone 2 base"),
                summary: String(localized: "Easy aerobic minutes that build the engine"),
                dailyAsk: String(localized: "This week: your Zone 2 minutes, in two or three easy sessions."),
                days: 56, aspect: .activity),
        Program(id: "morning-light", title: String(localized: "Morning light"),
                summary: String(localized: "Daylight before 09:00 sets your clock"),
                dailyAsk: String(localized: "Ten minutes outside before 09:00."),
                days: 21, aspect: .sleep),
        Program(id: "calm-afternoons", title: String(localized: "Calm afternoons"),
                summary: String(localized: "A breathing break before 14:30"),
                dailyAsk: String(localized: "Five slow minutes of breathing before 14:30."),
                days: 14, aspect: .mind),
        Program(id: "earlier-dinners", title: String(localized: "Earlier dinners"),
                summary: String(localized: "Last meal by 20:00, five nights a week"),
                dailyAsk: String(localized: "Finish eating by 20:00 tonight."),
                days: 21, aspect: .gut),
        Program(id: "strength-base", title: String(localized: "Strength base"),
                summary: String(localized: "Two short sessions a week"),
                dailyAsk: String(localized: "This week: two short strength sessions."),
                days: 42, aspect: .body),
        Program(id: "screen-free-evenings", title: String(localized: "Screen-free evenings"),
                summary: String(localized: "The phone away an hour before bed"),
                dailyAsk: String(localized: "Phone away an hour before bed tonight."),
                days: 21, aspect: .mind),
    ]

    static func program(_ id: String) -> Program? { all.first { $0.id == id } }
}

/// That a person joined a program, and when.
nonisolated struct ProgramEnrollment: Codable, Hashable, Sendable {
    var programID: String
    var joined: Date
}

/// Where a joined program stands on a given day.
nonisolated struct ProgramProgress: Equatable, Sendable {
    /// The day of the program, from 1.
    var day: Int
    var totalDays: Int
    var isFinished: Bool { day > totalDays }
    /// 0 to 1, for the bar.
    var fraction: Double { min(1, Double(day) / Double(max(1, totalDays))) }

    static func of(_ enrollment: ProgramEnrollment, program: Program, on date: Date, calendar: Calendar) -> ProgramProgress {
        let start = calendar.startOfDay(for: enrollment.joined)
        let today = calendar.startOfDay(for: date)
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return ProgramProgress(day: max(1, elapsed + 1), totalDays: program.days)
    }

    /// "Day 5 of 14", or "Week 3 of 8" for a program that counts in weeks.
    func label(for program: Program) -> String {
        if program.countsInWeeks {
            let week = min(program.weeks, (day - 1) / 7 + 1)
            return String(localized: "Week \(week) of \(program.weeks)")
        }
        return String(localized: "Day \(min(day, totalDays)) of \(totalDays)")
    }
}
