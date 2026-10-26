//
//  TrackLogStore.swift
//  Prism
//

import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

/// A drink poured on the water sheet.
nonisolated struct TrackDrinkEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var drink: TrackDrink
    var ml: Double
    var caffeineMg: Double
    var date: Date
}

/// The meal of the day a food entry belongs to.
nonisolated enum TrackMeal: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// The meal a clock hour most likely is.
    static func at(hour: Int) -> TrackMeal {
        switch hour {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<23: .dinner
        default: .snack
        }
    }
}

/// One meal, as the person described it: a name and what one portion holds.
nonisolated struct TrackMealEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var meal: TrackMeal
    /// Grams in one portion.
    var protein: Double
    var carbs: Double
    var fat: Double
    /// How many portions: 0.5, 1, 1.5.
    var portions: Double
    var date: Date

    /// Atwater: four kilocalories a gram of protein or carbohydrate, nine of fat.
    static func kilocalories(protein: Double, carbs: Double, fat: Double) -> Double {
        protein * 4 + carbs * 4 + fat * 9
    }

    var kilocalories: Double { Self.kilocalories(protein: protein, carbs: carbs, fat: fat) * portions }

    /// Grams eaten, every portion counted.
    var proteinEaten: Double { protein * portions }
    var carbsEaten: Double { carbs * portions }
    var fatEaten: Double { fat * portions }
}

/// Something taken on a rhythm: a supplement, a compound.
nonisolated struct TrackSupplement: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var amount: Double
    var unit: TrackDoseUnit
    /// Minutes after midnight it is usually taken at.
    var minute: Int
    var cadence: TrackCadence = .daily
    var startedOn: Date
    var isActive = true
    /// A reminder at `minute` on each due day, asked for on the dose page.
    /// Optional so a record written before reminders existed still reads:
    /// nil is no reminder.
    var reminds: Bool?
}

/// The units a dose is counted in.
nonisolated enum TrackDoseUnit: String, Codable, CaseIterable, Sendable {
    case grams, milligrams, micrograms, units, capsules

    var symbol: String {
        switch self {
        case .grams: "g"
        case .milligrams: "mg"
        case .micrograms: "mcg"
        case .units: "IU"
        case .capsules: "caps"
        }
    }

    /// The dial's reach and one detent.
    var range: ClosedRange<Double> {
        switch self {
        case .grams: 0...20
        case .milligrams: 0...1000
        case .micrograms: 0...1000
        case .units: 0...10000
        case .capsules: 0...6
        }
    }

    var step: Double {
        switch self {
        case .grams: 0.5
        case .milligrams: 25
        case .micrograms: 25
        case .units: 250
        case .capsules: 1
        }
    }
}

/// One dose taken.
nonisolated struct TrackDoseEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var supplementID: UUID?
    var name: String
    var amount: Double
    var unit: TrackDoseUnit
    var date: Date
}

/// A practice timed in minutes, logged by hand.
nonisolated enum TrackPractice: String, Codable, CaseIterable, Identifiable, Sendable {
    case coldPlunge
    case sauna
    case meditation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coldPlunge: "Cold plunge"
        case .sauna: "Sauna"
        case .meditation: "Meditation"
        }
    }

    /// The Journal tag a logged session taps, so the effects card measures it.
    var tagTitle: String { title }

    /// The dial's reach in minutes.
    var maxMinutes: Double {
        switch self {
        case .coldPlunge: 10
        case .sauna: 30
        case .meditation: 30
        }
    }

    var usualMinutes: Double {
        switch self {
        case .coldPlunge: 3
        case .sauna: 15
        case .meditation: 10
        }
    }
}

nonisolated struct TrackPracticeEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var practice: TrackPractice
    var minutes: Double
    var date: Date
}

/// A mood logged on the mood sheet.
nonisolated struct TrackMoodEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// Seven stops, 0 very unpleasant to 6 very pleasant, the Journal's own.
    var valence: Int
    /// The day as a whole, or the moment.
    var isDaily: Bool
    var words: [String]
    var contexts: [String]
    var date: Date
}

/// A body measurement typed or dragged in.
nonisolated enum TrackMeasure: String, Codable, Sendable {
    /// Kilograms.
    case weight
    /// Centimetres.
    case height
    /// Centimetres.
    case waist
}

nonisolated struct TrackMeasureEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var measure: TrackMeasure
    var value: Double
    var date: Date
}

/// Everything Track logs that is not a Journal tag or feeling: drinks, meals,
/// doses, fasts, timed practices, the morning's rating, moods and body
/// measures.
///
/// The one record of water, caffeine, meals, moods and how the person woke:
/// Pulse, Track and the Tools all read and write these entries here, so what
/// is logged on one tab shows on every other.
///
/// One JSON file in Application Support beside `journal.json`, kept on the
/// device. Whatever Apple Health can hold is also written there when the
/// person allows it (see ``TrackHealthWriter``); this file is what Soma reads
/// back, so a refusal in Health loses nothing here.
@MainActor
@Observable
final class TrackLogStore {
    static let shared = TrackLogStore()

    private(set) var drinks: [TrackDrinkEntry] = []
    private(set) var meals: [TrackMealEntry] = []
    private(set) var supplements: [TrackSupplement] = []
    private(set) var doses: [TrackDoseEntry] = []
    private(set) var fasts: [TrackFast] = []
    private(set) var practices: [TrackPracticeEntry] = []
    /// How the person woke, 1...10, keyed by the morning's day stamp.
    private(set) var wakeRatings: [String: Int] = [:]
    private(set) var moods: [TrackMoodEntry] = []
    private(set) var measures: [TrackMeasureEntry] = []
    var waterGoalMl: Double = TrackIntake.defaultGoalMl {
        didSet { save() }
    }
    /// The camera scan's "Don't show this again".
    var skipsScanIntro = false {
        didSet { save() }
    }

    private let url: URL?
    private let calendar: Calendar
    /// True after a read of an existing file failed: what is in memory is not
    /// the record, so `save()` refuses to write until a read succeeds.
    @ObservationIgnored private var unread = false
    @ObservationIgnored private var readableObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var applying = false

    private struct Stored: Codable {
        var drinks: [TrackDrinkEntry] = []
        var meals: [TrackMealEntry] = []
        var supplements: [TrackSupplement] = []
        var doses: [TrackDoseEntry] = []
        var fasts: [TrackFast] = []
        var practices: [TrackPracticeEntry] = []
        var wakeRatings: [String: Int] = [:]
        var moods: [TrackMoodEntry] = []
        var measures: [TrackMeasureEntry] = []
        var waterGoalMl: Double?
        var skipsScanIntro: Bool?
    }

    /// - Parameter url: where the record lives. Nil keeps it in memory, for
    ///   previews and tests.
    init(url: URL? = TrackLogStore.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        guard let url else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // A file that exists but cannot be read (a locked phone in a
            // background wake): nothing is written over it until it reads.
            if !Self.isMissing(error) { holdUntilReadable() }
            return
        }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        apply(stored)
    }

    /// Loads a read record. The observers' saves wait: writing back what was
    /// just read is a wasted write.
    private func apply(_ stored: Stored) {
        applying = true
        defer { applying = false }
        drinks = stored.drinks
        meals = stored.meals
        supplements = stored.supplements
        doses = stored.doses
        fasts = stored.fasts
        practices = stored.practices
        wakeRatings = stored.wakeRatings
        moods = stored.moods
        measures = stored.measures
        waterGoalMl = stored.waterGoalMl ?? TrackIntake.defaultGoalMl
        skipsScanIntro = stored.skipsScanIntro ?? false
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "track-log.json")
    }

    /// Forgets every entry and setting, file and all, for "Erase data on
    /// this iPhone".
    func erase() {
        apply(Stored())
        unread = false
        if let readableObserver { NotificationCenter.default.removeObserver(readableObserver) }
        readableObserver = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Days

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool { calendar.isDate(lhs, inSameDayAs: rhs) }

    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Drinks

    func drinks(on day: Date) -> [TrackDrinkEntry] {
        drinks.filter { isSameDay($0.date, day) }.sorted { $0.date < $1.date }
    }

    /// Millilitres poured on a day, or nil when nothing was.
    func waterMl(on day: Date) -> Double? {
        let poured = drinks(on: day)
        return poured.isEmpty ? nil : poured.reduce(0) { $0 + $1.ml }
    }

    /// Every caffeine dose of the last day and a half, for the model.
    func caffeineDoses(before now: Date) -> [TrackCaffeine.Dose] {
        let floor = now.addingTimeInterval(-36 * 3600)
        return drinks.filter { $0.caffeineMg > 0 && $0.date >= floor && $0.date <= now }
            .map { TrackCaffeine.Dose(mg: $0.caffeineMg, time: $0.date) }
    }

    /// Caffeine drunk on a day in milligrams, or nil when no caffeinated
    /// drink was logged.
    func caffeineMg(on day: Date) -> Double? {
        let cups = drinks(on: day).filter { $0.caffeineMg > 0 }
        return cups.isEmpty ? nil : cups.reduce(0) { $0 + $1.caffeineMg }
    }

    /// When the day's last caffeinated drink was logged.
    func lastCaffeine(on day: Date) -> Date? {
        drinks(on: day).filter { $0.caffeineMg > 0 }.map(\.date).max()
    }

    /// Adds a drink. `caffeineMg` overrides the drink's own caffeine per
    /// millilitre, for a cup whose dose is known (an espresso, a cola). `id`
    /// lets a drink logged elsewhere (a widget) keep its own identity, so it
    /// can be recognised and never added twice.
    @discardableResult
    func addDrink(_ drink: TrackDrink, ml: Double, caffeineMg: Double? = nil, at date: Date, id: UUID = UUID()) -> TrackDrinkEntry {
        let entry = TrackDrinkEntry(id: id, drink: drink, ml: ml, caffeineMg: caffeineMg ?? drink.caffeine(ml: ml), date: date)
        drinks.append(entry)
        save()
        return entry
    }

    func removeDrink(_ id: UUID) {
        drinks.removeAll { $0.id == id }
        save()
    }

    /// Takes back the day's last drink that matches, for a tap too many.
    func removeLastDrink(on day: Date, where matches: (TrackDrinkEntry) -> Bool) {
        guard let last = drinks(on: day).last(where: matches) else { return }
        removeDrink(last.id)
    }

    // MARK: Meals

    func meals(on day: Date) -> [TrackMealEntry] {
        meals.filter { isSameDay($0.date, day) }.sorted { $0.date < $1.date }
    }

    /// The last meal logged under a name, any case, for filling a repeat.
    func lastMeal(named name: String) -> TrackMealEntry? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return meals.last { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    func addMeal(_ entry: TrackMealEntry) {
        meals.append(entry)
        save()
    }

    // MARK: Supplements and doses

    var activeSupplements: [TrackSupplement] {
        supplements.filter(\.isActive).sorted { $0.minute < $1.minute }
    }

    @discardableResult
    func addSupplement(name: String, amount: Double, unit: TrackDoseUnit, minute: Int, startedOn: Date) -> TrackSupplement? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let index = supplements.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            supplements[index].amount = amount
            supplements[index].unit = unit
            supplements[index].minute = minute
            supplements[index].isActive = true
            save()
            return supplements[index]
        }
        let supplement = TrackSupplement(name: trimmed, amount: amount, unit: unit, minute: minute, startedOn: startedOn)
        supplements.append(supplement)
        save()
        return supplement
    }

    func setActive(_ isActive: Bool, supplement id: UUID) {
        guard let index = supplements.firstIndex(where: { $0.id == id }) else { return }
        supplements[index].isActive = isActive
        save()
    }

    /// Turns the dose reminder of a supplement on or off. The phone's
    /// pending requests follow through ``MedicationReminders/sync(asking:)``.
    func setReminds(_ reminds: Bool, supplement id: UUID) {
        guard let index = supplements.firstIndex(where: { $0.id == id }) else { return }
        supplements[index].reminds = reminds
        save()
    }

    func doses(on day: Date) -> [TrackDoseEntry] {
        doses.filter { isSameDay($0.date, day) }.sorted { $0.date < $1.date }
    }

    /// The dose of a supplement taken on a day, if one was.
    func dose(of supplement: TrackSupplement, on day: Date) -> TrackDoseEntry? {
        doses.first { $0.supplementID == supplement.id && isSameDay($0.date, day) }
    }

    @discardableResult
    func logDose(name: String, amount: Double, unit: TrackDoseUnit, supplementID: UUID?, at date: Date) -> TrackDoseEntry {
        let entry = TrackDoseEntry(supplementID: supplementID, name: name, amount: amount, unit: unit, date: date)
        doses.append(entry)
        save()
        return entry
    }

    func removeDose(_ id: UUID) {
        doses.removeAll { $0.id == id }
        save()
    }

    /// Where a supplement stands against the rhythm it was declared on.
    func adherence(of supplement: TrackSupplement, now: Date) -> TrackAdherence.Plan {
        TrackAdherence.plan(
            cadence: supplement.cadence,
            startedOn: supplement.startedOn,
            doseDates: doses.filter { $0.supplementID == supplement.id }.map(\.date),
            now: now,
            calendar: calendar
        )
    }

    // MARK: Fasts

    /// The fast running now, if one is.
    var currentFast: TrackFast? { fasts.last { $0.end == nil } }

    func startFast(at start: Date, objectiveHours: Double?, now: Date) {
        if currentFast != nil { endFast(at: now) }
        fasts.append(TrackFast(start: start, objectiveHours: objectiveHours))
        save()
    }

    /// Ends the running fast. Returns it, finished, or nil when none ran.
    @discardableResult
    func endFast(at now: Date) -> TrackFast? {
        guard let index = fasts.lastIndex(where: { $0.end == nil }) else { return nil }
        fasts[index].end = max(now, fasts[index].start)
        save()
        return fasts[index]
    }

    /// Drops the running fast without keeping it: a start by mistake.
    func cancelFast() {
        fasts.removeAll { $0.end == nil }
        save()
    }

    // MARK: Practices

    func practices(_ practice: TrackPractice, since: Date) -> [TrackPracticeEntry] {
        practices.filter { $0.practice == practice && $0.date >= since }
    }

    func logPractice(_ practice: TrackPractice, minutes: Double, at date: Date) {
        practices.append(TrackPracticeEntry(practice: practice, minutes: minutes, date: date))
        save()
    }

    // MARK: Wake rating

    func wakeRating(on day: Date) -> Int? { wakeRatings[stamp(day)] }

    func setWakeRating(_ rating: Int?, on day: Date) {
        wakeRatings[stamp(day)] = rating.map { min(max($0, 1), 10) }
        save()
    }

    /// The morning on Pulse's five words, awful (1) to great (5), read from
    /// the same rating: two stops of ten make one word.
    func wakeFeel(on day: Date) -> Int? {
        wakeRating(on: day).map { ($0 + 1) / 2 }
    }

    func setWakeFeel(_ feel: Int?, on day: Date) {
        setWakeRating(feel.map { min(max($0, 1), 5) * 2 }, on: day)
    }

    // MARK: Moods

    func addMood(_ entry: TrackMoodEntry) {
        moods.append(entry)
        save()
    }

    func moods(on day: Date) -> [TrackMoodEntry] {
        moods.filter { isSameDay($0.date, day) }.sorted { $0.date < $1.date }
    }

    // MARK: Measures

    func addMeasure(_ measure: TrackMeasure, value: Double, at date: Date) {
        measures.append(TrackMeasureEntry(measure: measure, value: value, date: date))
        save()
    }

    /// The latest entry of a measure logged here.
    func latest(_ measure: TrackMeasure) -> TrackMeasureEntry? {
        measures.filter { $0.measure == measure }.max { $0.date < $1.date }
    }

    // MARK: Saving

    /// Whether a read error means the file is not there yet, as on a first
    /// launch, rather than there but closed.
    nonisolated private static func isMissing(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == CocoaError.fileReadNoSuchFile.rawValue { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOENT)
        }
        return false
    }

    /// Blocks saving, and on iOS reads again once the phone unlocks.
    private func holdUntilReadable() {
        unread = true
        #if os(iOS)
        guard readableObserver == nil else { return }
        readableObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfUnread() }
        }
        #endif
    }

    /// After a failed read, reads the file again. On success the record
    /// loads, what was logged meanwhile is kept on top, and saving resumes.
    func reloadIfUnread() {
        guard unread, let url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let pending = Stored(
            drinks: drinks, meals: meals, supplements: supplements, doses: doses, fasts: fasts,
            practices: practices, wakeRatings: wakeRatings, moods: moods, measures: measures
        )
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            apply(stored)
        }
        drinks = Self.merged(drinks, pending.drinks)
        meals = Self.merged(meals, pending.meals)
        supplements = Self.merged(supplements, pending.supplements)
        doses = Self.merged(doses, pending.doses)
        fasts = Self.merged(fasts, pending.fasts)
        practices = Self.merged(practices, pending.practices)
        moods = Self.merged(moods, pending.moods)
        measures = Self.merged(measures, pending.measures)
        wakeRatings.merge(pending.wakeRatings) { _, new in new }
        unread = false
        if let readableObserver { NotificationCenter.default.removeObserver(readableObserver) }
        readableObserver = nil
        save()
    }

    private static func merged<Entry: Identifiable>(_ base: [Entry], _ extra: [Entry]) -> [Entry] {
        let known = Set(base.map(\.id))
        return base + extra.filter { !known.contains($0.id) }
    }

    private func save() {
        guard let url, !unread, !applying else { return }
        let stored = Stored(
            drinks: drinks, meals: meals, supplements: supplements, doses: doses, fasts: fasts,
            practices: practices, wakeRatings: wakeRatings, moods: moods, measures: measures,
            waterGoalMl: waterGoalMl, skipsScanIntro: skipsScanIntro
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // Kept in memory; the next change tries the write again.
        }
    }
}
