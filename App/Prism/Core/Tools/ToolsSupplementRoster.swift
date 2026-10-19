//
//  ToolsSupplementRoster.swift
//  Prism
//
//  The supplements the user actually takes, as journal entry ids.
//
//  WHY THIS IS AN ALLOWLIST AND NOT A CATEGORY FILTER. A journal
//  "Medication" category mixes supplements with prescription medication.
//  The Supplement Window tool is supplements only: telling someone when to
//  take a statin is medical advice and an App Review problem. A category
//  filter would quietly break that boundary the next time a medication is
//  added. An allowlist cannot drift, and the tests fail if anything from the
//  denylist becomes trackable.
//
//  Pure: the roster is a plain [String] the caller persists. Every function
//  takes it in and hands a new one back. An id that later leaves the journal
//  catalog is dropped by `resolve` rather than crashing a decode.
//

import Foundation

extension SomaTools {

    nonisolated enum SupplementRoster {

        /// A journal entry as the roster needs it: an id, a name and the
        /// section the journal files it under ("Morning", "Daytime", "Evening").
        struct Entry: Sendable, Equatable, Identifiable, Codable {
            let id: String
            let title: String
            let section: String

            init(id: String, title: String, section: String = "Daytime") {
                self.id = id
                self.title = title
                self.section = section
            }
        }

        // MARK: The boundary

        /// Prescription medication in a journal "Medication" category. These can
        /// never enter the roster. Explicit rather than inferred, so adding a
        /// medication to the journal is a deliberate decision here too.
        static let prescriptionIDs: Set<String> = [
            "adhd-med", "anxiety-med", "birth-control",
            "pain-med", "sleep-med", "weightloss-med"
        ]

        /// Built in journal entries that ARE supplements. Everything else must
        /// be a `custom.` entry the user created.
        ///
        /// `caffeine` is deliberately absent. Coffee is in the timing catalog
        /// because it blocks iron, not because it is a supplement.
        static let builtInIDs: Set<String> = [
            "ashwagandha", "calcium", "cbd", "creatine", "fish-oil", "iron",
            "magnesium", "melatonin", "probiotic", "turmeric", "zinc",
            "vit-a", "vit-b6", "vit-b12", "vit-c", "vit-d", "vit-e", "vit-k"
        ]

        /// Timing catalog ids mapped onto their journal twins. `coffee` has no
        /// entry on purpose, so a migration drops it.
        static let legacyTwins: [String: String] = [
            "magnesium": "magnesium",
            "melatonin": "melatonin",
            "vitaminD": "vit-d",
            "iron": "iron",
            "calcium": "calcium",
            "zinc": "zinc",
            "omega3": "fish-oil",
            "creatine": "creatine"
        ]

        /// Whether a journal entry id may be tracked. The prescription check
        /// comes FIRST and is unconditional: an id in both sets is refused.
        static func canTrack(_ journalID: String) -> Bool {
            if prescriptionIDs.contains(journalID) { return false }
            if journalID.hasPrefix("custom.") { return true }
            return builtInIDs.contains(journalID)
        }

        // MARK: Pure list operations

        /// The stored roster, revalidated on the way out. Persisted state
        /// outlives the rules that admitted it; validating on read makes the
        /// rule retroactive. Duplicates collapse, first occurrence wins.
        static func sanitized(_ ids: [String]) -> [String] {
            var seen: Set<String> = []
            return ids.filter { canTrack($0) && seen.insert($0).inserted }
        }

        /// Appends, refusing anything `canTrack` rejects and anything already
        /// present. Order is preserved.
        static func adding(_ journalID: String, to ids: [String]) -> [String] {
            let current = sanitized(ids)
            guard canTrack(journalID), !current.contains(journalID) else { return current }
            return current + [journalID]
        }

        static func removing(_ journalID: String, from ids: [String]) -> [String] {
            sanitized(ids).filter { $0 != journalID }
        }

        /// Seeds the roster from a legacy selection of timing catalog ids, once.
        ///
        /// The guard is the PRESENCE of a stored roster, not its emptiness. A
        /// user who migrated and then deleted everything has an empty roster
        /// and a full legacy list; keying on emptiness would resurrect exactly
        /// what they removed. Pass nil when no roster was ever stored.
        static func migrated(roster: [String]?, legacy: [String]) -> [String] {
            if let roster { return sanitized(roster) }
            return sanitized(legacy.compactMap { legacyTwins[$0] })
        }

        // MARK: Resolution

        /// The roster as journal entries, in ROSTER order, dropping ids the
        /// catalog no longer knows.
        static func resolve(ids: [String], catalog: [Entry]) -> [Entry] {
            let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return ids.compactMap { byID[$0] }
        }

        /// Catalog entries that could be added: trackable and not yet tracked,
        /// in catalog order.
        static func suggestions(tracked ids: [String], catalog: [Entry]) -> [Entry] {
            let tracked = Set(ids)
            return catalog.filter { canTrack($0.id) && !tracked.contains($0.id) }
        }

        /// Display name of an id: the journal title, else the timing catalog
        /// name for the conflict only ids, else the id itself.
        static func name(forEntryID id: String, catalog: [Entry]) -> String {
            if let entry = catalog.first(where: { $0.id == id }) { return entry.title }
            return SupplementTimingCatalog.entry(journalID: id)?.name
                ?? SupplementTimingCatalog.entry(id: id)?.name
                ?? id
        }
    }
}
