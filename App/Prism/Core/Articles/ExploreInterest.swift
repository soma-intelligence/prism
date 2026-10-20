//
//  ExploreInterest.swift
//  Prism
//

import Foundation
import Observation

/// What a person does in the app that says what they like to read about:
/// the pages they open, the pieces they read and the ones they save.
///
/// Kept on this device only, in user defaults. It is not part of Cloud sync
/// or the data export, and nothing here is ever sent anywhere: Explore reads
/// it to order its own shelves, and that is all.
struct ExploreInterestLog: Codable, Equatable, Sendable {
    /// A page about a topic, opened: the sleep page, the heart readings.
    struct Visit: Codable, Equatable, Sendable {
        var topic: ArticleTopic
        var date: Date
    }

    /// A piece opened in the reader, or saved.
    struct Piece: Codable, Equatable, Sendable {
        var id: String
        var topic: ArticleTopic
        var date: Date
    }

    /// Oldest first.
    var visits: [Visit] = []
    /// Oldest first, one entry a piece (its latest read).
    var reads: [Piece] = []
    /// Newest first.
    var saved: [Piece] = []

    /// How many visits and reads are kept: enough for a month or two of use,
    /// little enough that the file stays small.
    static let cap = 200
    /// A page opened again within this long is the same visit: going back
    /// and forth between a page and its details is one look, not five.
    static let visitGap: TimeInterval = 60 * 60

    mutating func visit(_ topic: ArticleTopic, at date: Date) {
        if let last = visits.last(where: { $0.topic == topic }), date.timeIntervalSince(last.date) < Self.visitGap {
            return
        }
        visits.append(Visit(topic: topic, date: date))
        if visits.count > Self.cap { visits.removeFirst(visits.count - Self.cap) }
    }

    mutating func read(id: String, topic: ArticleTopic, at date: Date) {
        reads.removeAll { $0.id == id }
        reads.append(Piece(id: id, topic: topic, date: date))
        if reads.count > Self.cap { reads.removeFirst(reads.count - Self.cap) }
    }

    func isSaved(_ id: String) -> Bool {
        saved.contains { $0.id == id }
    }

    /// Saves the piece, or takes it off the list when it is on it. Returns
    /// whether it is saved now.
    @discardableResult
    mutating func toggleSaved(id: String, topic: ArticleTopic, at date: Date) -> Bool {
        if isSaved(id) {
            saved.removeAll { $0.id == id }
            return false
        }
        saved.insert(Piece(id: id, topic: topic, date: date), at: 0)
        return true
    }

    /// The ids of every piece read.
    var readIDs: Set<String> { Set(reads.map(\.id)) }
}

/// The app's one interest log, observed by Explore and written by the pages
/// that note a visit, a read or a save.
@MainActor
@Observable
final class ExploreInterest {
    private(set) var log: ExploreInterestLog

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let key: String

    static let shared = ExploreInterest(defaults: .standard)

    /// - Parameter defaults: where the log is kept; nil keeps it in memory,
    ///   for previews and tests.
    init(defaults: UserDefaults?, key: String = "explore.interest") {
        self.defaults = defaults
        self.key = key
        if let data = defaults?.data(forKey: key),
           let stored = try? JSONDecoder().decode(ExploreInterestLog.self, from: data) {
            log = stored
        } else {
            log = ExploreInterestLog()
        }
    }

    func noteVisit(_ topic: ArticleTopic, at date: Date = .now) {
        var next = log
        next.visit(topic, at: date)
        commit(next)
    }

    func noteRead(_ article: Article, at date: Date = .now) {
        var next = log
        next.read(id: article.id, topic: article.topic, at: date)
        commit(next)
    }

    func isSaved(_ article: Article) -> Bool {
        log.isSaved(article.id)
    }

    func toggleSaved(_ article: Article, at date: Date = .now) {
        var next = log
        next.toggleSaved(id: article.id, topic: article.topic, at: date)
        commit(next)
    }

    private func commit(_ next: ExploreInterestLog) {
        guard next != log else { return }
        log = next
        if let data = try? JSONEncoder().encode(next) {
            defaults?.set(data, forKey: key)
        }
    }
}
