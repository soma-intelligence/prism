//
//  ChatHistory.swift
//  Prism
//

import CryptoKit
import Foundation
import SwiftData

/// One Ask conversation, kept on this phone.
///
/// The turns are stored as one JSON blob rather than as related models: a
/// conversation is always read and written whole, and a blob keeps the schema
/// to one entity that can change shape without a migration.
@Model
final class AskConversation {
    var id: UUID
    var title: String
    var created: Date
    var updated: Date
    var turnsData: Data

    init(id: UUID = UUID(), title: String, created: Date = Date(), turns: [StoredAskTurn] = []) {
        self.id = id
        self.title = title
        self.created = created
        self.updated = created
        self.turnsData = (try? JSONEncoder().encode(turns)) ?? Data()
    }

    var turns: [StoredAskTurn] {
        get { (try? JSONDecoder().decode([StoredAskTurn].self, from: turnsData)) ?? [] }
        set {
            turnsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updated = Date()
        }
    }
}

/// A question and the answer Soma gave, as they were on the day.
///
/// An answer is kept as written rather than asked again on reopening: the
/// numbers it read were that day's, and a history that rewrote itself with
/// today's would not be a history.
nonisolated struct StoredAskTurn: Codable, Equatable, Sendable {
    /// The turn's own id, the one its two messages carry in the account
    /// (`<id>:user`, `<id>:assistant`) whoever wrote them: the page, the
    /// `ask-soma` function or another phone.
    var id: UUID = UUID()
    var question: String
    var asked: Date
    var lead: String
    var rest: String?
    var signals: Int
    var sources: [String]
    var moveTitle: String?
    var moveReason: String?
    var moveAspect: String?
    var isModelMissing: Bool
}

extension StoredAskTurn {
    nonisolated private enum Keys: String, CodingKey {
        case id, question, asked, lead, rest, signals, sources, moveTitle, moveReason, moveAspect, isModelMissing
    }

    /// Reads a kept turn. Turns kept before they had an id get one from
    /// their question and the moment it was asked, the same on every read,
    /// so their upload stays one pair of rows.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        question = try container.decode(String.self, forKey: .question)
        asked = try container.decode(Date.self, forKey: .asked)
        lead = try container.decode(String.self, forKey: .lead)
        rest = try container.decodeIfPresent(String.self, forKey: .rest)
        signals = try container.decode(Int.self, forKey: .signals)
        sources = try container.decode([String].self, forKey: .sources)
        moveTitle = try container.decodeIfPresent(String.self, forKey: .moveTitle)
        moveReason = try container.decodeIfPresent(String.self, forKey: .moveReason)
        moveAspect = try container.decodeIfPresent(String.self, forKey: .moveAspect)
        isModelMissing = try container.decode(Bool.self, forKey: .isModelMissing)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.legacyID(question: question, asked: asked)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encode(asked, forKey: .asked)
        try container.encode(lead, forKey: .lead)
        try container.encodeIfPresent(rest, forKey: .rest)
        try container.encode(signals, forKey: .signals)
        try container.encode(sources, forKey: .sources)
        try container.encodeIfPresent(moveTitle, forKey: .moveTitle)
        try container.encodeIfPresent(moveReason, forKey: .moveReason)
        try container.encodeIfPresent(moveAspect, forKey: .moveAspect)
        try container.encode(isModelMissing, forKey: .isModelMissing)
    }

    /// A stable id for a turn kept without one.
    nonisolated static func legacyID(question: String, asked: Date) -> UUID {
        let digest = SHA256.hash(data: Data("ask-turn|\(asked.timeIntervalSince1970)|\(question)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// One conversation as a plain value: what the sync reads off the store and
/// writes back into it.
nonisolated struct AskConversationSnapshot: Equatable, Sendable {
    var id: UUID
    var title: String
    var created: Date
    var updated: Date
    var turns: [StoredAskTurn]
}

/// The history drawer's sections: this week, earlier this month, then a
/// section a month.
nonisolated enum ChatHistorySections {
    nonisolated struct Section: Equatable, Identifiable {
        var title: String
        var ids: [UUID]
        var id: String { title }
    }

    static func group(_ items: [(id: UUID, date: Date)], now: Date, calendar: Calendar) -> [Section] {
        let sorted = items.sorted { $0.date > $1.date }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? weekStart
        let monthName = Date.FormatStyle().month(.wide)

        var sections: [Section] = []
        func add(_ title: String, _ id: UUID) {
            if sections.last?.title == title {
                sections[sections.count - 1].ids.append(id)
            } else {
                sections.append(Section(title: title, ids: [id]))
            }
        }
        for item in sorted {
            if item.date >= weekStart {
                add(String(localized: "This week"), item.id)
            } else if item.date >= monthStart {
                add(String(localized: "Earlier in \(item.date.formatted(monthName))"), item.id)
            } else if calendar.component(.year, from: item.date) == calendar.component(.year, from: now) {
                add(item.date.formatted(monthName), item.id)
            } else {
                add(item.date.formatted(.dateTime.month(.wide).year()), item.id)
            }
        }
        return sections
    }

    /// "Today, 18:02", "Tuesday", "12 September": how far back decides how
    /// much of the date a row needs.
    static func stamp(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today, \(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))")
        }
        if let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start, date >= weekStart {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide))
    }
}

/// The conversations on this phone, in their own small SwiftData store.
///
/// Its own container rather than a model added to the app's shared schema:
/// Ask's history is the only thing in it, and a store of its own can be
/// erased from Settings without touching anything else.
///
/// Once someone is signed in, ``AskHistorySync`` mirrors it with the
/// account both ways: what is kept here is uploaded, conversations from
/// other phones are merged in, and a deletion here is remembered in
/// ``pendingDeletes`` until the account has forgotten it too.
@MainActor
@Observable
final class AskHistoryStore: AskHistoryLocal {
    static let shared = AskHistoryStore()

    private(set) var conversations: [AskConversation] = []
    /// Conversations deleted here that the account may still hold.
    private(set) var pendingDeletes: Set<UUID> = []
    private let context: ModelContext?
    private let defaults: UserDefaults?

    private static let pendingDeletesKey = "ask.history.pendingDeletes"

    init(inMemory: Bool = false) {
        let configuration = inMemory
            ? ModelConfiguration("AskHistory", isStoredInMemoryOnly: true)
            : ModelConfiguration("AskHistory")
        if let container = try? ModelContainer(for: AskConversation.self, configurations: configuration) {
            context = ModelContext(container)
        } else {
            context = nil
        }
        defaults = inMemory ? nil : .standard
        let kept = defaults?.stringArray(forKey: Self.pendingDeletesKey) ?? []
        pendingDeletes = Set(kept.compactMap(UUID.init(uuidString:)))
        reload()
    }

    func reload() {
        let descriptor = FetchDescriptor<AskConversation>(sortBy: [SortDescriptor(\.updated, order: .reverse)])
        conversations = (try? context?.fetch(descriptor)) ?? []
    }

    func conversation(_ id: UUID) -> AskConversation? {
        conversations.first { $0.id == id }
    }

    /// Adds a turn to the conversation `id`, starting one when `id` is nil or
    /// names no conversation yet (the page picks a conversation's id before
    /// its first answer, so the account files the turn under the same one).
    /// Returns the conversation's id.
    @discardableResult
    func append(_ turn: StoredAskTurn, to id: UUID?) -> UUID? {
        guard let context else { return nil }
        if let id, let existing = conversation(id) {
            existing.turns = existing.turns + [turn]
            try? context.save()
            reload()
            return id
        }
        let created = AskConversation(id: id ?? UUID(), title: Self.title(turn.question), created: turn.asked, turns: [turn])
        context.insert(created)
        try? context.save()
        reload()
        return created.id
    }

    func delete(_ id: UUID) {
        guard let context, let existing = conversation(id) else { return }
        context.delete(existing)
        try? context.save()
        remember(deleted: [id])
        reload()
    }

    func deleteAll() {
        guard let context else { return }
        let ids = conversations.map(\.id)
        for conversation in conversations { context.delete(conversation) }
        try? context.save()
        remember(deleted: ids)
        reload()
    }

    /// A conversation's title from its first question, as the account makes
    /// it: one line, at most 80 characters.
    nonisolated static func title(_ question: String) -> String {
        String(question.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
    }

    // MARK: Sync

    func snapshot() -> [AskConversationSnapshot] {
        conversations.map { AskConversationSnapshot(id: $0.id, title: $0.title, created: $0.created, updated: $0.updated, turns: $0.turns) }
    }

    /// Writes what the account sent: each snapshot replaces the conversation
    /// with its id or joins as a new one, and `removing` leaves (deleted on
    /// another phone). Nothing is saved, and nobody is told, when nothing
    /// changed.
    func apply(_ merged: [AskConversationSnapshot], removing: Set<UUID>) {
        guard let context else { return }
        var changed = false
        for snapshot in merged where !pendingDeletes.contains(snapshot.id) {
            if let existing = conversation(snapshot.id) {
                let current = AskConversationSnapshot(id: existing.id, title: existing.title, created: existing.created, updated: existing.updated, turns: existing.turns)
                guard current != snapshot else { continue }
                existing.title = snapshot.title
                existing.created = snapshot.created
                existing.turnsData = (try? JSONEncoder().encode(snapshot.turns)) ?? existing.turnsData
                existing.updated = snapshot.updated
            } else {
                let created = AskConversation(id: snapshot.id, title: snapshot.title, created: snapshot.created, turns: snapshot.turns)
                created.updated = snapshot.updated
                context.insert(created)
            }
            changed = true
        }
        for id in removing {
            guard let existing = conversation(id) else { continue }
            context.delete(existing)
            changed = true
        }
        guard changed else { return }
        try? context.save()
        reload()
    }

    /// The account has forgotten these.
    func clearPendingDeletes(_ ids: Set<UUID>) {
        guard !ids.isDisjoint(with: pendingDeletes) else { return }
        pendingDeletes.subtract(ids)
        persistPendingDeletes()
    }

    private func remember(deleted ids: [UUID]) {
        guard !ids.isEmpty else { return }
        pendingDeletes.formUnion(ids)
        persistPendingDeletes()
    }

    private func persistPendingDeletes() {
        defaults?.set(pendingDeletes.map(\.uuidString).sorted(), forKey: Self.pendingDeletesKey)
    }
}
