//
//  LocalDataErasure.swift
//  Prism
//

import Foundation

/// What "Delete my data" erases on the phone besides the sync database:
/// the files that hold where you sleep, your rituals, and the numbers
/// Longevity kept to open on. None of them is synced, so the server's
/// deletion cannot reach them.
///
/// - `longevity-snapshot.json` (``LongevitySnapshotStore``)
/// - `sleep-visits.json` (``SleepPlaceFinder``): stays, nights found, decisions
/// - `sleep-places.json` (``SleepPlaceStore``): nights set by hand, the
///   bedroom, the Weather city
/// - `rituals.json` (``TrackRitualStore``)
///
/// Mind's calendar lines are worked out in memory, kept for the day and
/// never written down; they are dropped too. Apple Health is never touched.
@MainActor
enum LocalDataErasure {
    static func run(snapshot: LongevitySnapshotStore = .shared,
                    sleepPlaces: SleepPlaceFinder = .shared,
                    nights: SleepPlaceStore = .shared,
                    rituals: TrackRitualStore = .shared) {
        snapshot.clear()
        sleepPlaces.erase()
        nights.erase()
        rituals.erase()
        MindCalendarDayCache.clear()
    }

    /// "Erase data on this iPhone", for local mode, where there is no account
    /// to delete: everything above, and the records that would otherwise
    /// only go with the app: mood notes and Mind's record (`mind.json`), the
    /// Explore interest log, the Track logs (`track-log.json`) and the
    /// Journal (`journal.json`). Apple Health is never touched.
    static func runOnDevice(journal: JournalStore,
                            snapshot: LongevitySnapshotStore = .shared,
                            sleepPlaces: SleepPlaceFinder = .shared,
                            nights: SleepPlaceStore = .shared,
                            rituals: TrackRitualStore = .shared,
                            mind: MindStore = .shared,
                            interest: ExploreInterest = .shared,
                            logs: TrackLogStore = .shared) {
        run(snapshot: snapshot, sleepPlaces: sleepPlaces, nights: nights, rituals: rituals)
        mind.deleteAll()
        interest.erase()
        logs.erase()
        journal.erase()
    }
}
