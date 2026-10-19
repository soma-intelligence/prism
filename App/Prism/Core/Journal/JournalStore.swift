//
//  JournalStore.swift
//  Prism
//

import Foundation
import Observation

/// One tag a person can tap in the Journal: something that happened, whose
/// effect Soma measures against their days.
struct JournalTag: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    /// Whether the Journal offers it. Switched in Track, Customize.
    var isOffered: Bool
}

/// What a person logged about one day.
///
/// Each tag is a yes or no question. A yes is in ``tags``, a no in
/// ``declined``, and a tag in neither was not answered. A no is kept rather
/// than left blank because it is data: a day without alcohol, said so, is the
/// day an effect is measured against.
struct JournalDay: Codable, Equatable, Sendable {
    /// The ids of the tags answered yes that day.
    var tags: Set<String> = []
    /// The ids of the tags answered no that day.
    var declined: Set<String> = []
    /// How they felt, on seven stops from very unpleasant (0) to very
    /// pleasant (6). Nil until asked.
    var feeling: Int?

    init(tags: Set<String> = [], declined: Set<String> = [], feeling: Int? = nil) {
        self.tags = tags
        self.declined = declined.subtracting(tags)
        self.feeling = feeling
    }

    private enum CodingKeys: String, CodingKey {
        case tags, declined, feeling
    }

    /// Reads a record written before the no answers existed, which has no
    /// `declined` key: every tag in it is then unanswered or yes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        declined = try container.decodeIfPresent(Set<String>.self, forKey: .declined) ?? []
        feeling = try container.decodeIfPresent(Int.self, forKey: .feeling)
    }

    /// The answer to one tag: yes, no, or nil for not answered.
    func answer(_ tagID: String) -> Bool? {
        if tags.contains(tagID) { return true }
        if declined.contains(tagID) { return false }
        return nil
    }

    /// Whether anything at all was logged.
    var isEmpty: Bool { tags.isEmpty && declined.isEmpty && feeling == nil }
}

/// The questions the Journal asks each day, and when.
struct JournalQuestions: Codable, Equatable, Sendable {
    var asksFeeling = true
    /// The hour the feeling question comes, 0...23.
    var feelingHour = 21
    var asksEnergy = false
    var asksStress = false
}

/// The Journal's record: the tags on offer, what each day holds, and the daily
/// questions.
///
/// Kept on the device as one JSON file in Application Support. It is the
/// person's own words about their days, so it never leaves the phone from
/// here; a sync, when there is one, reads it through this type.
@MainActor
@Observable
final class JournalStore {
    private(set) var tags: [JournalTag]
    /// Keyed by the day's stamp, `yyyy-MM-dd` in the person's calendar.
    private(set) var days: [String: JournalDay]
    var questions: JournalQuestions {
        didSet { save() }
    }

    private let url: URL?
    private let calendar: Calendar

    /// The tags a new Journal starts with: the ones the design offers, the
    /// last two switched off.
    static let starterTags: [JournalTag] = [
        ("coffee-late", "Coffee after 14:00", true),
        ("alcohol", "Alcohol", true),
        ("late-meal", "Late meal", true),
        ("hard-training", "Hard training", true),
        ("sauna", "Sauna", true),
        ("screens-in-bed", "Screens in bed", true),
        ("meditation", "Meditation", true),
        ("travel", "Travel", true),
        ("nap", "Nap", false),
        ("supplements", "Supplements", false),
    ].map { JournalTag(id: $0.0, title: $0.1, isOffered: $0.2) }

    private struct Stored: Codable {
        var tags: [JournalTag]
        var days: [String: JournalDay]
        var questions: JournalQuestions
    }

    /// - Parameter url: where the record lives. Nil keeps it in memory only,
    ///   which is what previews and tests use.
    init(url: URL? = JournalStore.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            tags = stored.tags
            days = stored.days
            questions = stored.questions
        } else {
            tags = Self.starterTags
            days = [:]
            questions = JournalQuestions()
        }
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "journal.json")
    }

    // MARK: Reading

    var offeredTags: [JournalTag] { tags.filter(\.isOffered) }

    func day(_ date: Date) -> JournalDay {
        days[stamp(date)] ?? JournalDay()
    }

    func title(of tagID: String) -> String {
        tags.first { $0.id == tagID }?.title ?? tagID
    }

    /// Every logged day as its start date, oldest first.
    var loggedDays: [(date: Date, day: JournalDay)] {
        days.compactMap { key, value in date(from: key).map { ($0, value) } }
            .sorted { $0.date < $1.date }
    }

    /// The start of each day a tag was tapped on.
    func dates(tagged tagID: String) -> Set<Date> {
        Set(loggedDays.filter { $0.day.tags.contains(tagID) }.map(\.date))
    }

    // MARK: Writing

    func toggle(_ tagID: String, on date: Date) {
        var entry = day(date)
        if entry.tags.contains(tagID) { entry.tags.remove(tagID) } else { entry.tags.insert(tagID) }
        entry.declined.remove(tagID)
        days[stamp(date)] = entry
        save()
    }

    /// Answers one tag for a day: yes, no, or nil to clear the answer.
    func answer(_ tagID: String, _ answer: Bool?, on date: Date) {
        var entry = day(date)
        entry.tags.remove(tagID)
        entry.declined.remove(tagID)
        switch answer {
        case true?: entry.tags.insert(tagID)
        case false?: entry.declined.insert(tagID)
        case nil: break
        }
        days[stamp(date)] = entry
        save()
    }

    /// Gives `target` the yes and no answers `source` holds, wherever
    /// `target` has not answered yet: an answer already given is kept. Only
    /// the answers travel; a feeling is that day's own.
    func copyTags(from source: Date, to target: Date) {
        let from = day(source)
        var entry = day(target)
        let answered = entry.tags.union(entry.declined)
        let yes = from.tags.subtracting(answered)
        let no = from.declined.subtracting(answered)
        guard !yes.isEmpty || !no.isEmpty else { return }
        entry.tags.formUnion(yes)
        entry.declined.formUnion(no)
        days[stamp(target)] = entry
        save()
    }

    func setFeeling(_ feeling: Int?, on date: Date) {
        var entry = day(date)
        entry.feeling = feeling.map { min(max($0, 0), 6) }
        days[stamp(date)] = entry
        save()
    }

    func setOffered(_ isOffered: Bool, tag tagID: String) {
        guard let index = tags.firstIndex(where: { $0.id == tagID }) else { return }
        tags[index].isOffered = isOffered
        save()
    }

    /// Adds a tag of the person's own, offered at once. A title already on the
    /// list, in any case, is switched on rather than added twice.
    @discardableResult
    func addTag(_ title: String) -> JournalTag? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let index = tags.firstIndex(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            tags[index].isOffered = true
            save()
            return tags[index]
        }
        let tag = JournalTag(id: "custom-\(UUID().uuidString.prefix(8).lowercased())", title: trimmed, isOffered: true)
        tags.append(tag)
        save()
        return tag
    }

    // MARK: Days

    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func date(from stamp: String) -> Date? {
        let parts = stamp.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func save() {
        guard let url else { return }
        let stored = Stored(tags: tags, days: days, questions: questions)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // A failed write keeps the day in memory; the next change tries
            // again. Nothing to show the person that would help them.
        }
    }
}
