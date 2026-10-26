//
//  ToolsScreeningLedger.swift
//  Prism
//
//  The ledger of recorded screenings and answered risk flags, as one Codable
//  value. The caller persists it as JSON; this type computes no cadence of its
//  own, it only records. The due engine is the one home of the cadence math.
//
//  Every stored field is optional or defaulted on decode, so a field added
//  later cannot wipe a ledger already written.
//

import Foundation

extension SomaTools {

    nonisolated struct ScreeningLedger: Codable, Sendable, Equatable {
        /// Every recorded screening, in the order written.
        private(set) var records: [ScreeningDone]
        /// One answer per flag: answering twice revises, it does not pile up.
        private(set) var riskAnswers: [ScreeningRisk]
        /// The items the person asked to be reminded of, by item id, with the
        /// moment they asked. Opt in per item: nothing is reminded by default.
        private(set) var reminders: [String: Date]

        init(records: [ScreeningDone] = [], riskAnswers: [ScreeningRisk] = [], reminders: [String: Date] = [:]) {
            self.records = records
            self.riskAnswers = riskAnswers
            self.reminders = reminders
        }

        private enum CodingKeys: String, CodingKey { case records, riskAnswers, reminders }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            records = try c.decodeIfPresent([ScreeningDone].self, forKey: .records) ?? []
            riskAnswers = (try? c.decodeIfPresent([LossyRisk].self, forKey: .riskAnswers))?
                .compactMap(\.value) ?? []
            reminders = (try? c.decodeIfPresent([String: Date].self, forKey: .reminders)) ?? [:]
        }

        /// Decodes one risk row, dropping a flag a later version removed
        /// instead of failing the whole ledger.
        private struct LossyRisk: Decodable {
            let value: ScreeningRisk?
            init(from decoder: Decoder) throws {
                value = try? ScreeningRisk(from: decoder)
            }
        }

        // MARK: Records

        /// Records one screening. Returns the new record.
        @discardableResult
        mutating func log(itemID: String,
                          performedOn: Date,
                          note: String? = nil,
                          documentID: UUID? = nil,
                          nextDueOverride: Date? = nil,
                          id: UUID = UUID()) -> ScreeningDone {
            let record = ScreeningDone(id: id, itemID: itemID, performedOn: performedOn,
                                       note: note, documentID: documentID,
                                       nextDueOverride: nextDueOverride)
            records.append(record)
            return record
        }

        /// Attaches a document to an existing record. Separate from `log`: the
        /// row is written first, so a failed attachment leaves a row without a
        /// document, never a file without a row.
        mutating func attach(documentID: UUID, toRecord recordID: UUID) {
            guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
            records[index].documentID = documentID
        }

        /// Replaces a record in place (edit of date, note or override).
        mutating func update(_ record: ScreeningDone) {
            guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
            records[index] = record
        }

        mutating func delete(recordID: UUID) {
            records.removeAll { $0.id == recordID }
        }

        /// All records, most recent first.
        var recordsNewestFirst: [ScreeningDone] {
            records.sorted { $0.performedOn > $1.performedOn }
        }

        func records(for itemID: String) -> [ScreeningDone] {
            recordsNewestFirst.filter { $0.itemID == itemID }
        }

        /// The most recent record, not the last written.
        func lastRecord(for itemID: String) -> ScreeningDone? {
            records(for: itemID).first
        }

        // MARK: Risk answers

        /// Upserts one answer.
        mutating func answer(flag: ScreeningRiskFlag,
                             isPresent: Bool,
                             earliestDiagnosisAge: Int? = nil,
                             packYears: Int? = nil,
                             answeredAt: Date = Date()) {
            let row = ScreeningRisk(flag: flag, isPresent: isPresent,
                                    earliestDiagnosisAge: earliestDiagnosisAge,
                                    packYears: packYears, answeredAt: answeredAt)
            if let index = riskAnswers.firstIndex(where: { $0.flag == flag }) {
                riskAnswers[index] = row
            } else {
                riskAnswers.append(row)
            }
        }

        func answer(for flag: ScreeningRiskFlag) -> ScreeningRisk? {
            riskAnswers.first { $0.flag == flag }
        }

        /// True once anything at all was answered, which is what collapses the
        /// family history block.
        var hasAnsweredAnyRisk: Bool { !riskAnswers.isEmpty }

        // MARK: Reminders

        /// Turns the reminder for one item on or off. Turning it on again
        /// keeps the first moment it was asked for.
        mutating func setReminder(_ isOn: Bool, itemID: String, now: Date = Date()) {
            if isOn {
                if reminders[itemID] == nil { reminders[itemID] = now }
            } else {
                reminders[itemID] = nil
            }
        }

        func remindsOf(_ itemID: String) -> Bool { reminders[itemID] != nil }

        // MARK: Engine

        /// The statuses the page renders, straight from the engine.
        func statuses(age: Int,
                      sex: ScreeningEligibility?,
                      today: Date = Date(),
                      catalog: [ScreeningItem] = ScreeningCatalog.items,
                      birthday: Date? = nil,
                      calendar: Calendar = .current) -> [ScreeningDueEngine.Status] {
            ScreeningDueEngine.statuses(age: age, sex: sex, today: today,
                                        records: records, risk: riskAnswers,
                                        catalog: catalog, birthday: birthday, calendar: calendar)
        }
    }
}

extension SomaTools.ScreeningLedger {
    /// This ledger with results kept elsewhere in the app counted as done: a
    /// calcium score or a DEXA with a T-score saved in the Lab is that
    /// screening, so the person never logs it twice. A result already on the
    /// ledger, or one the person logged for the same item that day, adds
    /// nothing. Folded in as the ledger is read, never written to its file.
    nonisolated func withResults(_ done: [SomaTools.ScreeningDone], calendar: Calendar = .current) -> SomaTools.ScreeningLedger {
        var merged = records
        for record in done {
            let known = merged.contains { existing in
                existing.id == record.id
                    || (existing.itemID == record.itemID && calendar.isDate(existing.performedOn, inSameDayAs: record.performedOn))
            }
            if !known { merged.append(record) }
        }
        return SomaTools.ScreeningLedger(records: merged, riskAnswers: riskAnswers, reminders: reminders)
    }
}
