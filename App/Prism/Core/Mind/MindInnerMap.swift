//
//  MindInnerMap.swift
//  Prism
//
//  The inner map: which feelings a person names week by week, whether the
//  body agreed with them, and what pulls on them. A pull is stated only once
//  it held on enough entries, and each says how often it held.
//

import Foundation

nonisolated struct MindInnerMap: Equatable, Sendable {
    /// Weeks the map spans.
    static let weeks = 8
    /// Mentions an item needs before its pull is stated.
    static let minimumMentions = 3

    /// One feeling's count, week by week, oldest first.
    struct Row: Equatable, Sendable, Identifiable {
        var feeling: MindFeeling
        var counts: [Int]
        var id: String { feeling.id }
        var total: Int { counts.reduce(0, +) }
    }

    /// One day felt and measured.
    struct Point: Equatable, Sendable, Identifiable {
        var day: Date
        /// The day's mean valence, -1 to 1.
        var felt: Double
        /// The day's HRV less the usual, in ms.
        var measured: Double
        var id: Date { day }
        /// Both on the same side of the usual.
        var agrees: Bool { (felt >= 0) == (measured >= 0) }
    }

    /// Something that pulls, and how often it held.
    struct Pull: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable { case person, place, theme }
        var title: String
        var kind: Kind
        var lifts: Bool
        var held: Int
        var mentions: Int
        var id: String { kind.rawValue + title }
    }

    var weekStarts: [Date]
    var rows: [Row]
    var checkIns: Int
    var points: [Point]
    var pulls: [Pull]
    var headline: String
    var reason: String

    var agreeing: Int { points.filter(\.agrees).count }

    static func make(
        moods: [MindMoodEntry],
        notes: [MindDayNote],
        hrvByDay: [Date: Double],
        usualHRV: Double?,
        now: Date,
        calendar: Calendar
    ) -> MindInnerMap {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let starts = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        let first = starts.first ?? thisWeek
        let recent = moods.filter { $0.date >= first && $0.date <= now }

        func week(of date: Date) -> Int? {
            starts.lastIndex { $0 <= date }
        }
        var counts: [String: [Int]] = [:]
        for entry in recent {
            guard let index = week(of: entry.date) else { continue }
            for label in entry.labels where MindFeeling.named(label) != nil {
                counts[label, default: Array(repeating: 0, count: starts.count)][index] += 1
            }
        }
        let ranked = counts.sorted { $0.value.reduce(0, +) > $1.value.reduce(0, +) }
        func top(_ pleasant: Bool) -> [Row] {
            ranked.compactMap { id, values -> Row? in
                guard let feeling = MindFeeling.named(id), feeling.isPleasant == pleasant else { return nil }
                return Row(feeling: feeling, counts: values)
            }
            .prefix(3).map { $0 }
        }
        let rows = top(true) + top(false)

        // Felt and measured, day by day.
        var feltByDay: [Date: [Double]] = [:]
        for entry in recent { feltByDay[calendar.startOfDay(for: entry.date), default: []].append(entry.valence) }
        let points: [Point] = usualHRV.map { usual in
            feltByDay.compactMap { day, values -> Point? in
                guard let hrv = hrvByDay[day], let felt = MindUsual.mean(values) else { return nil }
                return Point(day: day, felt: felt, measured: hrv - usual)
            }
            .sorted { $0.day < $1.day }
        } ?? []

        let pulls = pulls(moods: recent, notes: notes.filter { $0.day >= first }, calendar: calendar)

        // The words.
        let pleasantTop = rows.filter(\.feeling.isPleasant).prefix(2).map(\.feeling.title.localizedLowercase)
        let unpleasantTop = rows.filter { !$0.feeling.isPleasant }.first
        let pleasantTotal = recent.filter { $0.valence > 0 }.count
        let headline: String
        if recent.isEmpty {
            headline = "Nothing named yet."
        } else if pleasantTotal * 2 >= recent.count {
            headline = unpleasantTop.map { "Mostly \(pleasantTop.first ?? "pleasant"), sometimes \($0.feeling.title.localizedLowercase)." } ?? "Mostly \(pleasantTop.first ?? "pleasant")."
        } else {
            headline = "A heavier stretch, mostly \(unpleasantTop?.feeling.title.localizedLowercase ?? "unpleasant")."
        }
        var sentences: [String] = []
        if pleasantTop.count == 2 {
            sentences.append("\(pleasantTop[0].capitalized) and \(pleasantTop[1]) lead your check-ins.")
        }
        if let rising = rows.first(where: { row in
            let tail = row.counts.suffix(3)
            return tail.count == 3 && zip(tail, tail.dropFirst()).allSatisfy { $0 < $1 }
        }) {
            sentences.append("\(rising.feeling.title) has grown three weeks running.")
        }
        let reason = recent.isEmpty
            ? "Name how you feel, one word a day is enough. Apple Health’s State of Mind entries count here too."
            : (sentences.isEmpty ? "Every word you log fills this map a little more." : sentences.joined(separator: " "))

        return MindInnerMap(
            weekStarts: starts, rows: rows, checkIns: recent.count, points: points,
            pulls: pulls, headline: headline, reason: reason
        )
    }

    /// Each mention is a vote: the entry felt above or below the person's
    /// own average, or the moment lifted or weighed. An item pulls the way
    /// most of its votes went, once it has enough of them.
    static func pulls(moods: [MindMoodEntry], notes: [MindDayNote], calendar: Calendar) -> [Pull] {
        let average = MindUsual.mean(moods.map(\.valence)) ?? 0
        var votes: [String: (kind: Pull.Kind, up: Int, down: Int)] = [:]
        func vote(_ title: String, _ kind: Pull.Kind, up: Bool) {
            let key = kind.rawValue + "|" + title
            var current = votes[key] ?? (kind, 0, 0)
            if up { current.up += 1 } else { current.down += 1 }
            votes[key] = current
        }
        for entry in moods {
            for id in entry.associations {
                guard let association = MindAssociation.named(id) else { continue }
                vote(association.title, .theme, up: entry.valence >= average)
            }
        }
        for note in notes {
            let day = moods.filter { calendar.isDate($0.date, inSameDayAs: note.day) }.map(\.valence)
            let dayUp = MindUsual.mean(day).map { $0 >= average }
            for person in note.people { if let dayUp { vote(person, .person, up: dayUp) } }
            for place in note.places { if let dayUp { vote(place, .place, up: dayUp) } }
            for moment in note.moments where moment.pull != .none {
                vote(moment.title, .theme, up: moment.pull == .lifted)
            }
        }
        return votes.compactMap { key, value -> Pull? in
            let mentions = value.up + value.down
            guard mentions >= minimumMentions, value.up != value.down else { return nil }
            let title = String(key.split(separator: "|", maxSplits: 1).last ?? "")
            return Pull(title: title, kind: value.kind, lifts: value.up > value.down, held: max(value.up, value.down), mentions: mentions)
        }
        .sorted { lhs, rhs in
            lhs.lifts != rhs.lifts ? lhs.lifts : (lhs.held != rhs.held ? lhs.held > rhs.held : lhs.title < rhs.title)
        }
    }
}
