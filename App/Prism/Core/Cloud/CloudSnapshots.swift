//
//  CloudSnapshots.swift
//  Prism
//

import Foundation

/// The app's local stores read as cloud records.
///
/// Each function turns what a store holds now into the records that should be
/// on the server. The mirror (``CloudMirror``) compares that with what was
/// last pushed and saves only the difference into SyncCore's outbox. The
/// stores themselves do not know the cloud exists: they keep their own files,
/// and nothing here writes to them.
enum CloudSnapshots {
    /// Dates to whole milliseconds, the precision a payload keeps, so a record
    /// read back from the outbox compares equal to the one made from the store.
    nonisolated static func ms(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    nonisolated static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    // MARK: Journal

    static func journal(_ days: [String: JournalDay], userID: String) -> [JournalDayRecord] {
        days.compactMap { key, day in
            guard !day.isEmpty else { return nil }
            return JournalDayRecord(
                id: CloudRecords.id(CloudRecords.journalDays, userID: userID, key: key),
                day: key,
                tagsYes: day.tags.sorted(),
                tagsNo: day.declined.sorted(),
                feeling: day.feeling
            )
        }
    }

    // MARK: Soma asks

    static func checkIns(_ days: [String: CheckInDayRecord], userID: String) -> [CheckInAnswerRecord] {
        var records: [CheckInAnswerRecord] = []
        for (day, record) in days {
            for (question, answer) in record.answers {
                let (kind, value) = Self.answer(answer)
                records.append(CheckInAnswerRecord(
                    id: CloudRecords.id(CloudRecords.checkInAnswers, userID: userID, key: "\(day)|\(question)"),
                    day: day, questionID: question, answerKind: kind, answerValue: value,
                    skipped: false, questionText: record.asked[question]
                ))
            }
            for question in record.skipped where record.answers[question] == nil {
                records.append(CheckInAnswerRecord(
                    id: CloudRecords.id(CloudRecords.checkInAnswers, userID: userID, key: "\(day)|\(question)"),
                    day: day, questionID: question, answerKind: nil, answerValue: nil,
                    skipped: true, questionText: record.asked[question]
                ))
            }
        }
        return records
    }

    nonisolated static func answer(_ answer: CheckInAnswer) -> (String, Int?) {
        switch answer {
        case .yes: ("yes", nil)
        case .no: ("no", nil)
        case .scale(let value): ("scale", value)
        case .number(let value): ("number", value)
        }
    }

    // MARK: Mood and Mind

    static func moods(mind: [MindMoodEntry], track: [TrackMoodEntry]) -> [MoodLogRecord] {
        let fromMind = mind.map { entry in
            MoodLogRecord(
                id: CloudRecords.id(entry.id), loggedAt: ms(entry.date),
                kind: entry.kind == .daily ? "daily" : "momentary",
                valence: min(max(entry.valence, -1), 1),
                labels: entry.labels, associations: entry.associations, origin: "mind"
            )
        }
        let fromTrack = track.map { entry in
            MoodLogRecord(
                id: CloudRecords.id(entry.id), loggedAt: ms(entry.date),
                kind: entry.isDaily ? "daily" : "momentary",
                valence: MindMoodEntry.valence(stop: entry.valence),
                labels: entry.words, associations: entry.contexts, origin: "track"
            )
        }
        return fromMind + fromTrack
    }

    static func mindCheckIns(_ checkIns: [MindCheckIn]) -> [MindCheckInRecord] {
        checkIns.map { entry in
            MindCheckInRecord(
                id: CloudRecords.id(entry.id), loggedAt: ms(entry.date),
                energy: entry.energy, mood: entry.mood, focus: entry.focus,
                question: entry.question, answer: entry.answer?.rawValue
            )
        }
    }

    // MARK: Track

    struct TrackInput {
        var drinks: [TrackDrinkEntry] = []
        var meals: [TrackMealEntry] = []
        var supplements: [TrackSupplement] = []
        var doses: [TrackDoseEntry] = []
        var fasts: [TrackFast] = []
        var practices: [TrackPracticeEntry] = []
        var measures: [TrackMeasureEntry] = []
        var wakeRatings: [String: Int] = [:]
    }

    static func track(_ input: TrackInput, userID: String, calendar: Calendar) -> [TrackLogRecord] {
        var records: [TrackLogRecord] = []
        for drink in input.drinks {
            records.append(TrackLogRecord(
                id: CloudRecords.id(drink.id), kind: "drink", loggedAt: ms(drink.date), endedAt: nil,
                value: drink.ml, unit: "ml", label: drink.drink.rawValue,
                detail: ["caffeine_mg": .number(drink.caffeineMg)]
            ))
        }
        for meal in input.meals {
            records.append(TrackLogRecord(
                id: CloudRecords.id(meal.id), kind: "meal", loggedAt: ms(meal.date), endedAt: nil,
                value: meal.kilocalories, unit: "kcal", label: meal.name,
                detail: [
                    "meal": .text(meal.meal.rawValue),
                    "protein_g": .number(meal.protein), "carbs_g": .number(meal.carbs), "fat_g": .number(meal.fat),
                    "portions": .number(meal.portions),
                ]
            ))
        }
        for supplement in input.supplements {
            records.append(TrackLogRecord(
                id: CloudRecords.id(supplement.id), kind: "supplement", loggedAt: ms(supplement.startedOn), endedAt: nil,
                value: supplement.amount, unit: supplement.unit.rawValue, label: supplement.name,
                detail: [
                    "minute": .number(Double(supplement.minute)),
                    "cadence": .text(String(describing: supplement.cadence)),
                    "active": .flag(supplement.isActive),
                ]
            ))
        }
        for dose in input.doses {
            var detail: [String: CloudValue] = [:]
            if let supplement = dose.supplementID { detail["supplement_id"] = .text(supplement.uuidString.lowercased()) }
            records.append(TrackLogRecord(
                id: CloudRecords.id(dose.id), kind: "dose", loggedAt: ms(dose.date), endedAt: nil,
                value: dose.amount, unit: dose.unit.rawValue, label: dose.name, detail: detail
            ))
        }
        for fast in input.fasts {
            records.append(TrackLogRecord(
                id: CloudRecords.id(fast.id), kind: "fast", loggedAt: ms(fast.start), endedAt: fast.end.map(ms),
                value: fast.objectiveHours, unit: "h", label: nil, detail: [:]
            ))
        }
        for practice in input.practices {
            records.append(TrackLogRecord(
                id: CloudRecords.id(practice.id), kind: "practice", loggedAt: ms(practice.date), endedAt: nil,
                value: practice.minutes, unit: "min", label: practice.practice.rawValue, detail: [:]
            ))
        }
        for measure in input.measures {
            records.append(TrackLogRecord(
                id: CloudRecords.id(measure.id), kind: "measure", loggedAt: ms(measure.date), endedAt: nil,
                value: measure.value, unit: measure.measure == .weight ? "kg" : "cm", label: measure.measure.rawValue, detail: [:]
            ))
        }
        for (day, rating) in input.wakeRatings {
            guard let date = date(fromDayKey: day, calendar: calendar) else { continue }
            records.append(TrackLogRecord(
                id: CloudRecords.id(CloudRecords.trackLogs, userID: userID, key: "wake_rating|\(day)"),
                kind: "wake_rating", loggedAt: ms(date), endedAt: nil,
                value: Double(rating), unit: "of 10", label: nil, detail: ["day": .text(day)]
            ))
        }
        return records
    }

    // MARK: Lab

    static func labs(_ panels: [BloodPanel], calendar: Calendar) -> [LabResultRecord] {
        panels.map { panel in
            LabResultRecord(
                id: CloudRecords.id(panel.id),
                collectedOn: dayKey(panel.date, calendar: calendar),
                labName: nil,
                markers: panel.markers.map { LabResultRecord.Marker(marker: $0.key, value: $0.value, unit: $0.enteredUnit) }
            )
        }
    }

    // MARK: Scores

    /// The 30 day series ending `today`, one record per day that has any score.
    nonisolated static func scores(_ scores: SomaScores?, today: Date, userID: String, calendar: Calendar) -> [ScoreDayRecord] {
        guard let scores else { return [] }
        let count = max(scores.sleepSeries.count, scores.recoverySeries.count, scores.strainSeries.count,
                        scores.stressSeries.count, scores.energySeries.count)
        func value(_ series: [Double?], _ index: Int) -> Int? {
            // Every series ends today; a shorter one starts later.
            let offset = count - series.count
            let position = index - offset
            guard position >= 0, position < series.count, let number = series[position], number.isFinite else { return nil }
            return Int(number.rounded())
        }
        var records: [ScoreDayRecord] = []
        let start = calendar.startOfDay(for: today)
        for index in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: index - (count - 1), to: start) else { continue }
            let key = dayKey(day, calendar: calendar)
            var record = ScoreDayRecord(
                id: CloudRecords.id(CloudRecords.scoresDaily, userID: userID, key: key), day: key,
                sleep: value(scores.sleepSeries, index), recovery: value(scores.recoverySeries, index),
                strain: value(scores.strainSeries, index), stress: value(scores.stressSeries, index),
                energy: value(scores.energySeries, index)
            )
            // Today's headline numbers are the freshest reading of today.
            if index == count - 1 {
                record.sleep = scores.sleep ?? record.sleep
                record.recovery = scores.recovery ?? record.recovery
                record.strain = scores.strain ?? record.strain
                record.stress = scores.stress ?? record.stress
                record.energy = scores.energy ?? record.energy
            }
            if record.sleep != nil || record.recovery != nil || record.strain != nil || record.stress != nil || record.energy != nil {
                records.append(record)
            }
        }
        return records
    }

    // MARK: Notifications

    static func inbox(_ items: [InboxItem], userID: String) -> [NotificationInboxRecord] {
        items.map { item in
            NotificationInboxRecord(
                id: CloudRecords.id(CloudRecords.notificationInbox, userID: userID, key: item.id),
                deliveredAt: ms(item.date), kind: item.kind.rawValue, title: item.title, body: item.body,
                isRead: item.isRead, deepLink: item.link?.url.absoluteString
            )
        }
    }

    // MARK: Providers

    /// - Parameter connectedAt: when each provider was linked, by its id; a
    ///   connection made through Open Health Sync has no date on the phone.
    static func providers(_ states: [String: ProviderConnectionState], connectedAt: [String: Date] = [:],
                          userID: String) -> [ProviderConnectionRecord] {
        states.compactMap { provider, state in
            let record: (String, String?, Date?)
            switch state {
            case .notConnected: return nil
            case .connecting: return nil
            case .connected(let account, let lastSync): record = ("connected", account, lastSync.map(ms))
            case .failed: record = ("failed", nil, nil)
            }
            return ProviderConnectionRecord(
                id: CloudRecords.id(CloudRecords.providerConnections, userID: userID, key: provider),
                provider: provider, status: record.0, accountLabel: record.1, lastSyncAt: record.2,
                connectedAt: connectedAt[provider].map(ms)
            )
        }
    }
}
