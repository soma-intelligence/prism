//
//  ToolsSupplementTiming.swift
//  Prism
//
//  When in the day each supplement should sit, and what should not sit next
//  to what.
//
//  SCOPE, deliberately narrow: SUPPLEMENTS ONLY. No prescription medication
//  appears in this catalog and none should be added. Telling someone when to
//  take levothyroxine or a statin is medical advice; telling them iron and
//  coffee compete for absorption is consumer nutrition. The first is a
//  liability and an App Review problem, the second is on the side of every
//  supplement bottle.
//
//  Pure and input driven. The catalog is static data, the engine is arithmetic
//  over it. No store, no I/O.
//
//  It is a PLANNER, not a reminder: the tool says where things belong in a
//  day and what clashes, rather than tapping you on the shoulder.
//

import Foundation

extension SomaTools {

    // MARK: Slots

    /// Where in the day a supplement belongs, relative to the user's own wake
    /// time rather than a clock hour: a shift worker waking at 16:00 gets the
    /// same ordering as everyone else.
    nonisolated enum SupplementSlot: String, Sendable, Equatable, CaseIterable, Comparable, Codable {
        case onWaking
        case withBreakfast
        case midday
        case withDinner
        case beforeBed

        var order: Int {
            switch self {
            case .onWaking: return 0
            case .withBreakfast: return 1
            case .midday: return 2
            case .withDinner: return 3
            case .beforeBed: return 4
            }
        }

        static func < (a: SupplementSlot, b: SupplementSlot) -> Bool {
            a.order < b.order
        }

        /// Hours after wake this slot usually falls at. Placement on a
        /// timeline, never a prescription.
        var hoursAfterWake: Double {
            switch self {
            case .onWaking: return 0
            case .withBreakfast: return 0.5
            case .midday: return 6
            case .withDinner: return 11
            case .beforeBed: return 15
            }
        }

        var label: String {
            switch self {
            case .onWaking: return "On waking"
            case .withBreakfast: return "With breakfast"
            case .midday: return "Midday"
            case .withDinner: return "With dinner"
            case .beforeBed: return "Before bed"
            }
        }
    }

    /// Whether the item needs food, and what kind.
    nonisolated enum SupplementFoodRule: String, Sendable, Equatable, Codable {
        case anyTime
        case withFood
        /// Needs dietary fat to absorb.
        case withFat
        case emptyStomach

        /// Short badge for a row. nil for `anyTime`: a badge saying "any time"
        /// is noise on every second row.
        var badge: String? {
            switch self {
            case .anyTime: return nil
            case .withFood: return "With food"
            case .withFat: return "With some fat"
            case .emptyStomach: return "Empty stomach"
            }
        }
    }

    // MARK: Catalog

    nonisolated struct SupplementTimingEntry: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let preferredSlot: SupplementSlot
        let foodRule: SupplementFoodRule
        /// Ids this competes with for absorption when taken in the same slot.
        /// Symmetry is asserted by the tests rather than assumed.
        let competesWith: [String]
        /// Why the slot is what it is. One plain sentence, no clinical claim.
        let reason: String
        /// The journal entry this supplement is tracked as, when one exists.
        /// The journal owns the LIST; this catalog only decorates it with a
        /// slot, a food rule and its conflicts.
        let journalEntryID: String?
    }

    nonisolated enum SupplementTimingCatalog {

        static let all: [SupplementTimingEntry] = [
            .init(id: "magnesium", name: "Magnesium",
                  preferredSlot: .beforeBed, foodRule: .anyTime,
                  competesWith: ["calcium", "zinc", "iron"],
                  reason: "Tends to sit better in the evening, and competes with calcium, zinc and iron for the same transporters.",
                  journalEntryID: "magnesium"),

            .init(id: "melatonin", name: "Melatonin",
                  preferredSlot: .beforeBed, foodRule: .anyTime,
                  competesWith: [],
                  reason: "Timing is the whole point: taken late it shifts the body clock the wrong way.",
                  journalEntryID: "melatonin"),

            .init(id: "vitaminD", name: "Vitamin D",
                  preferredSlot: .withBreakfast, foodRule: .withFat,
                  competesWith: [],
                  reason: "Fat soluble, so it needs a meal with some fat in it to be absorbed.",
                  journalEntryID: "vit-d"),

            .init(id: "iron", name: "Iron",
                  preferredSlot: .onWaking, foodRule: .emptyStomach,
                  competesWith: ["calcium", "magnesium", "zinc", "coffee"],
                  reason: "Absorbs best on an empty stomach, and coffee, calcium, zinc and magnesium all get in the way.",
                  journalEntryID: "iron"),

            .init(id: "calcium", name: "Calcium",
                  preferredSlot: .withDinner, foodRule: .withFood,
                  competesWith: ["iron", "zinc", "magnesium"],
                  reason: "Competes with iron, zinc and magnesium, so it wants its own slot away from them.",
                  journalEntryID: "calcium"),

            .init(id: "zinc", name: "Zinc",
                  preferredSlot: .withDinner, foodRule: .withFood,
                  competesWith: ["iron", "calcium", "magnesium"],
                  reason: "Hard on an empty stomach, and it competes with iron, calcium and magnesium.",
                  journalEntryID: "zinc"),

            .init(id: "omega3", name: "Omega-3",
                  preferredSlot: .withDinner, foodRule: .withFat,
                  competesWith: [],
                  reason: "Fat soluble, and taking it with the largest meal usually settles it best.",
                  journalEntryID: "fish-oil"),

            .init(id: "creatine", name: "Creatine",
                  preferredSlot: .midday, foodRule: .anyTime,
                  competesWith: [],
                  reason: "Timing barely matters; total daily intake and consistency do.",
                  journalEntryID: "creatine"),

            .init(id: "coffee", name: "Coffee",
                  preferredSlot: .midday, foodRule: .anyTime,
                  competesWith: ["iron"],
                  reason: "Included because it blocks iron absorption, not as a supplement.",
                  journalEntryID: nil)
        ]

        static let byID: [String: SupplementTimingEntry] =
            Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        /// Reverse index: journal entry id to timing entry. An entry with none
        /// (coffee) is simply absent.
        static let byJournalID: [String: SupplementTimingEntry] =
            Dictionary(all.compactMap { entry in entry.journalEntryID.map { ($0, entry) } },
                       uniquingKeysWith: { first, _ in first })

        static func entry(id: String) -> SupplementTimingEntry? { byID[id] }

        static func entry(journalID: String) -> SupplementTimingEntry? { byJournalID[journalID] }

        /// Where a tracked supplement belongs in the day.
        ///
        /// The catalog wins when it knows the id: magnesium is an evening item
        /// for absorption reasons, whatever section the journal files it under.
        /// Then the user's own choice for a custom entry. Otherwise the journal
        /// section decides, which invents nothing: no food rule, no competitor.
        static func slot(forJournalID id: String,
                         section: String,
                         custom: SupplementCustomSlots = SupplementCustomSlots()) -> SupplementSlot {
            if let entry = byJournalID[id] { return entry.preferredSlot }
            if let chosen = custom.slots[id] { return chosen }
            return section == "Evening" ? .beforeBed : .withBreakfast
        }

        static func foodRule(forJournalID id: String,
                             custom: SupplementCustomSlots = SupplementCustomSlots()) -> SupplementFoodRule {
            byJournalID[id]?.foodRule ?? custom.foodRules[id] ?? .anyTime
        }
    }

    // MARK: Custom slots

    /// The slot and food rule chosen for a custom supplement, keyed by journal
    /// entry id. Two plain dictionaries, persisted by the caller: a missing key
    /// falls back to the section derived slot, the same answer the catalog
    /// gives any id it does not know.
    nonisolated struct SupplementCustomSlots: Codable, Sendable, Equatable {
        var slots: [String: SupplementSlot]
        var foodRules: [String: SupplementFoodRule]

        init(slots: [String: SupplementSlot] = [:], foodRules: [String: SupplementFoodRule] = [:]) {
            self.slots = slots
            self.foodRules = foodRules
        }

        private enum CodingKeys: String, CodingKey { case slots, foodRules }

        /// Lenient decode: an unknown raw value drops that one entry instead of
        /// wiping every choice.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let rawSlots = (try? c.decodeIfPresent([String: String].self, forKey: .slots)) ?? [:]
            let rawFood = (try? c.decodeIfPresent([String: String].self, forKey: .foodRules)) ?? [:]
            slots = rawSlots.compactMapValues(SupplementSlot.init(rawValue:))
            foodRules = rawFood.compactMapValues(SupplementFoodRule.init(rawValue:))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(slots.mapValues(\.rawValue), forKey: .slots)
            try c.encode(foodRules.mapValues(\.rawValue), forKey: .foodRules)
        }

        mutating func set(slot: SupplementSlot, foodRule: SupplementFoodRule, for id: String) {
            slots[id] = slot
            foodRules[id] = foodRule
        }

        mutating func remove(_ id: String) {
            slots[id] = nil
            foodRules[id] = nil
        }
    }

    // MARK: Engine

    nonisolated enum SupplementTimingEngine {

        /// Two items that compete but landed in the same slot.
        struct Conflict: Sendable, Equatable, Identifiable {
            let firstID: String
            let secondID: String
            let slot: SupplementSlot
            /// Stable and order independent, so the same pair never renders
            /// twice under two ids.
            var id: String { "\(slot.rawValue).\(min(firstID, secondID)).\(max(firstID, secondID))" }
        }

        struct PlannedSlot: Sendable, Equatable, Identifiable {
            let slot: SupplementSlot
            /// Entry ids in this slot, alphabetical so renders are stable.
            let entryIDs: [String]
            var id: String { slot.rawValue }
        }

        struct Plan: Sendable, Equatable {
            /// Only slots that actually hold something, in day order.
            let slots: [PlannedSlot]
            let conflicts: [Conflict]
            /// Ids asked for but not in the catalog.
            let unknownIDs: [String]
            var isEmpty: Bool { slots.isEmpty }

            /// The conflicts that sit in one slot.
            func conflicts(in slot: SupplementSlot) -> [Conflict] {
                conflicts.filter { $0.slot == slot }
            }
        }

        /// The day's plan from timing catalog ids.
        static func plan(forSelectedIDs ids: [String]) -> Plan {
            let unique = Array(Set(ids)).sorted()
            let known = unique.compactMap { SupplementTimingCatalog.entry(id: $0) }
            let unknown = unique.filter { SupplementTimingCatalog.entry(id: $0) == nil }

            var bySlot: [SupplementSlot: [String]] = [:]
            for entry in known {
                bySlot[entry.preferredSlot, default: []].append(entry.id)
            }
            let slots = bySlot
                .map { PlannedSlot(slot: $0.key, entryIDs: $0.value.sorted()) }
                .sorted { $0.slot < $1.slot }
            return Plan(slots: slots, conflicts: conflicts(in: slots), unknownIDs: unknown)
        }

        /// The day's plan from tracked journal entries.
        ///
        /// The ids here are JOURNAL ids, not timing catalog ids: the journal
        /// carries the list, this engine decorates it. Conflicts are declared in
        /// timing catalog ids, so they are translated on the way in rather than
        /// leaking two id spaces into the view layer.
        static func plan(forJournalEntries entries: [(id: String, section: String)],
                         custom: SupplementCustomSlots = SupplementCustomSlots()) -> Plan {
            var bySlot: [SupplementSlot: [String]] = [:]
            for entry in entries {
                let slot = SupplementTimingCatalog.slot(forJournalID: entry.id,
                                                        section: entry.section,
                                                        custom: custom)
                bySlot[slot, default: []].append(entry.id)
            }
            let slots = bySlot
                .map { PlannedSlot(slot: $0.key, entryIDs: $0.value.sorted()) }
                .sorted { $0.slot < $1.slot }
            return Plan(slots: slots, conflicts: journalConflicts(in: slots), unknownIDs: [])
        }

        /// Competing pairs among JOURNAL ids that share a slot. An id the timing
        /// catalog does not know competes with nothing, which is the correct
        /// answer rather than a cautious guess.
        static func journalConflicts(in slots: [PlannedSlot]) -> [Conflict] {
            var seen: Set<String> = []
            var found: [Conflict] = []
            for planned in slots {
                for first in planned.entryIDs {
                    guard let entry = SupplementTimingCatalog.entry(journalID: first) else { continue }
                    for second in planned.entryIDs where second != first {
                        guard let other = SupplementTimingCatalog.entry(journalID: second) else { continue }
                        let mutual = entry.competesWith.contains(other.id)
                            || other.competesWith.contains(entry.id)
                        guard mutual else { continue }
                        let conflict = Conflict(firstID: first, secondID: second, slot: planned.slot)
                        guard !seen.contains(conflict.id) else { continue }
                        seen.insert(conflict.id)
                        found.append(conflict)
                    }
                }
            }
            return found.sorted { $0.id < $1.id }
        }

        /// Competing pairs that ended up in the same slot, each reported once
        /// whichever direction the catalog declares it in.
        static func conflicts(in slots: [PlannedSlot]) -> [Conflict] {
            var seen: Set<String> = []
            var found: [Conflict] = []
            for planned in slots {
                for first in planned.entryIDs {
                    guard let entry = SupplementTimingCatalog.entry(id: first) else { continue }
                    for second in planned.entryIDs where second != first {
                        let mutual = entry.competesWith.contains(second)
                            || (SupplementTimingCatalog.entry(id: second)?.competesWith.contains(first) ?? false)
                        guard mutual else { continue }
                        let conflict = Conflict(firstID: first, secondID: second, slot: planned.slot)
                        guard !seen.contains(conflict.id) else { continue }
                        seen.insert(conflict.id)
                        found.append(conflict)
                    }
                }
            }
            return found.sorted { $0.id < $1.id }
        }

        /// The clock time a slot lands at, given the wake time.
        static func time(for slot: SupplementSlot,
                         wake: Date,
                         calendar: Calendar = .current) -> Date {
            calendar.date(byAdding: .minute, value: Int(slot.hoursAfterWake * 60), to: wake) ?? wake
        }

        /// The wake time slots are derived from: the user's wake minutes after
        /// midnight when known, 07:00 otherwise.
        static func wake(on date: Date, wakeMinutes: Int?, calendar: Calendar = .current) -> Date {
            let minutes = wakeMinutes ?? 7 * 60
            return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                 second: 0, of: date) ?? date
        }

        /// "Calcium and Zinc compete: space them apart." `name` resolves an id
        /// to a display name.
        static func conflictSentence(_ conflict: Conflict, name: (String) -> String) -> String {
            "\(name(conflict.firstID)) and \(name(conflict.secondID)) compete: space them apart."
        }
    }

    // MARK: One day, read once

    /// What every surface of the tool knows about one day, resolved once, so
    /// the count on one surface is the count on all of them.
    nonisolated struct SupplementDayRead: Sendable, Equatable {
        struct TimedSlot: Sendable, Equatable {
            let slot: SupplementSlot
            let time: Date
        }

        let plan: SupplementTimingEngine.Plan
        /// Each planned slot at the clock time it lands at for this day's wake.
        let times: [TimedSlot]
        /// The next slot still to come, otherwise the first of the day: the plan
        /// replays every day, so after the last dose the next is tomorrow's.
        let next: TimedSlot?
        let wake: Date
        let taken: Int
        let total: Int
        let takenIDs: Set<String>
        /// True when the day read is the day being lived.
        let isToday: Bool
        let isFuture: Bool

        var isEmpty: Bool { plan.isEmpty }

        /// Builds the read from plain inputs.
        /// - Parameters:
        ///   - entries: the tracked journal entries, roster order.
        ///   - answers: the day's yes or no answers by journal id. A "no" counts
        ///     as answered but not taken.
        ///   - wakeMinutes: wake time in minutes after midnight, nil for 07:00.
        static func make(entries: [SupplementRoster.Entry],
                         answers: [String: Bool],
                         date: Date,
                         now: Date,
                         wakeMinutes: Int?,
                         custom: SupplementCustomSlots = SupplementCustomSlots(),
                         calendar: Calendar = .current) -> SupplementDayRead {
            let plan = SupplementTimingEngine.plan(
                forJournalEntries: entries.map { (id: $0.id, section: $0.section) }, custom: custom)
            let wake = SupplementTimingEngine.wake(on: date, wakeMinutes: wakeMinutes, calendar: calendar)
            let times = plan.slots.map {
                TimedSlot(slot: $0.slot,
                          time: SupplementTimingEngine.time(for: $0.slot, wake: wake, calendar: calendar))
            }
            let next = times.first(where: { $0.time >= now }) ?? times.first
            let takenIDs = Set(entries.map(\.id).filter { answers[$0] == true })
            let today = calendar.startOfDay(for: now)
            let day = calendar.startOfDay(for: date)
            return SupplementDayRead(plan: plan, times: times, next: next, wake: wake,
                                     taken: takenIDs.count, total: entries.count,
                                     takenIDs: takenIDs, isToday: day == today, isFuture: day > today)
        }

        /// Decimal clock hour of an instant. An evening dose on a late wake
        /// lands the next morning; reading the calendar hour places it right.
        static func clockHour(_ date: Date, calendar: Calendar = .current) -> Double {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        }
    }
}
