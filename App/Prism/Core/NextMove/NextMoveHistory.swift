//
//  NextMoveHistory.swift
//  Prism
//

import Foundation

/// What the orb already said today, and what the person already did.
///
/// A move that has led for ``cooldown`` rests for the rest of the day, so the
/// orb does not repeat one piece of advice from breakfast to bedtime; an
/// urgent one never rests. A move the person acted on leaves the race. The
/// record belongs to its day: tomorrow starts clean.
struct NextMoveHistory: Codable, Equatable, Sendable {
    static let cooldown: TimeInterval = 3 * 60 * 60
    static let empty = NextMoveHistory()

    /// The day the record is for, as year-month-day.
    var day: String = ""
    /// When each move first led today.
    var firstShown: [String: Date] = [:]
    /// Moves the person acted on today.
    var acted: Set<String> = []

    func isResting(_ id: String, at now: Date) -> Bool {
        guard let first = firstShown[id] else { return false }
        return now.timeIntervalSince(first) >= Self.cooldown
    }

    /// The record as it stands on `now`'s day: yesterday's is dropped.
    func on(_ now: Date, calendar: Calendar) -> NextMoveHistory {
        let stamp = Self.stamp(now, calendar: calendar)
        return day == stamp ? self : NextMoveHistory(day: stamp)
    }

    /// The record with `id` leading at `now`, kept from the first time.
    func showing(_ id: String, at now: Date, calendar: Calendar) -> NextMoveHistory {
        var next = on(now, calendar: calendar)
        if let first = next.firstShown[id], first <= now { return next }
        next.firstShown[id] = now
        return next
    }

    func acting(on id: String, _ done: Bool = true, at now: Date, calendar: Calendar) -> NextMoveHistory {
        var next = on(now, calendar: calendar)
        if done { next.acted.insert(id) } else { next.acted.remove(id) }
        return next
    }

    /// The record without what was acted on: the card still lists those,
    /// ticked, while the orb moves on.
    var listing: NextMoveHistory {
        NextMoveHistory(day: day, firstShown: firstShown, acted: [])
    }

    static func stamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

/// The history kept in the app's defaults, on this device only.
@MainActor
final class NextMoveHistoryStore {
    static let shared = NextMoveHistoryStore()
    static let key = "nextmove.history"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func history(on now: Date, calendar: Calendar = .current) -> NextMoveHistory {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(NextMoveHistory.self, from: data) else {
            return NextMoveHistory.empty.on(now, calendar: calendar)
        }
        return stored.on(now, calendar: calendar)
    }

    func noteShown(_ id: String, at now: Date, calendar: Calendar = .current) {
        save(history(on: now, calendar: calendar).showing(id, at: now, calendar: calendar))
    }

    func noteActed(_ id: String, _ done: Bool = true, at now: Date, calendar: Calendar = .current) {
        save(history(on: now, calendar: calendar).acting(on: id, done, at: now, calendar: calendar))
    }

    private func save(_ history: NextMoveHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
