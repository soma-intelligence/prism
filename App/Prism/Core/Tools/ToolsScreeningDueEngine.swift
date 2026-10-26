//
//  ToolsScreeningDueEngine.swift
//  Prism
//
//  Turns the catalog plus the user's age, sex, answered risk flags and
//  recorded screenings into one status per item. Pure static functions over
//  value types: no store, no HealthKit, no clock of its own.
//
//  The type level guarantee lives here: a `.discuss` item and an unanswered
//  gated item can only ever produce `.discussOnly`. Two early returns, both
//  covered by tests.
//

import Foundation

extension SomaTools {

    nonisolated enum ScreeningDueEngine {

        /// Days before the next due date at which an item reads as upcoming
        /// rather than simply up to date. Ninety days is when booking happens.
        static let upcomingHorizonDays = 90

        enum State: Sendable, Equatable {
            /// Too young yet. Carries the effective start age, which risk flags
            /// may have pulled earlier than the catalog's.
            case notYetEligible(startsAtAge: Int)
            /// Due now. `monthsLate` is 0 on the day it comes due.
            case due(monthsLate: Int)
            case upcoming(on: Date)
            case upToDate(until: Date)
            /// Past the age at which the app stops asserting anything.
            case pastStopAge
            /// Listed, never due: tier `.discuss`, or an item gated on a risk
            /// flag the user has not answered.
            case discussOnly
        }

        struct Status: Sendable, Equatable, Identifiable {
            let item: ScreeningItem
            let state: State
            let lastDone: Date?
            /// nil for `.discussOnly`, `.notYetEligible` and `.pastStopAge`.
            let nextDue: Date?
            let effectiveStartAge: Int
            let effectiveIntervalMonths: Int?
            /// Which answered flags actually moved this item. Empty means the
            /// general population cadence.
            let appliedFlags: [ScreeningRiskFlag]

            var id: String { item.id }

            var isDue: Bool {
                if case .due = state { return true }
                return false
            }

            /// Months late, or 0 for anything not due.
            var monthsLate: Int {
                if case .due(let months) = state { return months }
                return 0
            }
        }

        // MARK: Entry point

        /// - Parameters:
        ///   - age: calendar age in whole years. A non positive age returns an
        ///     empty list; without that guard an empty profile would announce
        ///     a colonoscopy 45 years overdue.
        ///   - sex: nil when unknown. Only `.any` items are then returned; the
        ///     caller says so rather than silently dropping mammography.
        ///   - birthday: when known, the age a screening was done at is read
        ///     from it exactly; without it, from `age` less the whole years
        ///     since. Only an item whose cadence changes with age reads it.
        static func statuses(age: Int,
                             sex: ScreeningEligibility?,
                             today: Date = Date(),
                             records: [ScreeningDone],
                             risk: [ScreeningRisk],
                             catalog: [ScreeningItem] = ScreeningCatalog.items,
                             birthday: Date? = nil,
                             calendar: Calendar = .current) -> [Status] {
            guard age > 0 else { return [] }

            let presentFlags = Dictionary(
                risk.filter(\.isPresent).map { ($0.flag, $0) },
                uniquingKeysWith: { first, _ in first })

            let latest = latestRecordByItem(records)

            let all = catalog
                .filter { $0.eligibility.applies(to: sex) }
                .map { item in
                    status(for: item, age: age, today: today, lastRecord: latest[item.id],
                           presentFlags: presentFlags, birthday: birthday, calendar: calendar)
                }

            return all.sorted { lhs, rhs in
                let l = sortRank(lhs), r = sortRank(rhs)
                if l != r { return l < r }
                if lhs.monthsLate != rhs.monthsLate { return lhs.monthsLate > rhs.monthsLate }
                return lhs.item.id < rhs.item.id
            }
        }

        /// Recommended items that are due, worst first.
        static func dueNow(_ statuses: [Status]) -> [Status] {
            statuses
                .filter { $0.item.tier == .recommended && $0.isDue }
                .sorted { $0.monthsLate > $1.monthsLate }
        }

        // MARK: One item

        private static func status(for item: ScreeningItem,
                                   age: Int,
                                   today: Date,
                                   lastRecord: ScreeningDone?,
                                   presentFlags: [ScreeningRiskFlag: ScreeningRisk],
                                   birthday: Date?,
                                   calendar: Calendar) -> Status {
            let applied = item.modifiers.map(\.flag).filter { presentFlags[$0] != nil }
            let startAge = effectiveStartAge(item: item, presentFlags: presentFlags)
            let interval = effectiveIntervalMonths(item: item, presentFlags: presentFlags, age: age)

            func status(_ state: State, nextDue: Date? = nil) -> Status {
                Status(item: item, state: state, lastDone: lastRecord?.performedOn,
                       nextDue: nextDue, effectiveStartAge: startAge,
                       effectiveIntervalMonths: interval, appliedFlags: applied)
            }

            // Guarantee one: a weakly evidenced screening is never called due.
            if item.tier == .discuss { return status(.discussOnly) }

            // Guarantee two: a gated screening is never called due until the
            // user has confirmed the risk it is gated on.
            if let gate = item.requiresRiskFlag, presentFlags[gate] == nil {
                return status(.discussOnly)
            }

            if let stopAge = item.stopAge, age > stopAge { return status(.pastStopAge) }

            guard age >= startAge else {
                return status(.notYetEligible(startsAtAge: startAge))
            }

            guard let last = lastRecord else {
                // Never recorded and already eligible: late by however long they
                // have been eligible, in whole years of age.
                return status(.due(monthsLate: max(0, (age - startAge) * 12)))
            }

            // The cadence of the age the screening was done at: a cytology at
            // 29 comes back in three years even once 30 has passed.
            let ageAtRecord = birthday.flatMap { born in
                calendar.dateComponents([.year], from: born, to: last.performedOn).year
            } ?? (age - wholeMonths(from: last.performedOn, to: today, calendar: calendar) / 12)
            let next: Date
            if let override = last.nextDueOverride {
                next = override
            } else if let interval = effectiveIntervalMonths(item: item, presentFlags: presentFlags, age: ageAtRecord) {
                next = calendar.date(byAdding: .month, value: interval, to: last.performedOn)
                    ?? last.performedOn
            } else {
                // Once in a lifetime, and it is done.
                return status(.upToDate(until: .distantFuture), nextDue: nil)
            }

            if next <= today {
                return status(.due(monthsLate: wholeMonths(from: next, to: today, calendar: calendar)),
                              nextDue: next)
            }
            let horizon = calendar.date(byAdding: .day, value: upcomingHorizonDays, to: today) ?? today
            if next <= horizon { return status(.upcoming(on: next), nextDue: next) }
            return status(.upToDate(until: next), nextDue: next)
        }

        // MARK: Modifier resolution

        /// The earliest start age any answered flag argues for. The catalog age
        /// is the ceiling, never the floor.
        static func effectiveStartAge(item: ScreeningItem,
                                      presentFlags: [ScreeningRiskFlag: ScreeningRisk]) -> Int {
            var start = item.startAge
            for modifier in item.modifiers {
                guard let answer = presentFlags[modifier.flag] else { continue }
                if let override = modifier.startAgeOverride {
                    start = min(start, override)
                }
                if let years = modifier.yearsBeforeRelativeDiagnosis,
                   let dx = answer.earliestDiagnosisAge {
                    start = min(start, dx - years)
                }
            }
            return max(0, start)
        }

        /// The shortest cadence any answered flag argues for, from the catalog
        /// cadence at `age` (nil reads the base cadence). A once in a lifetime
        /// item stays once in a lifetime.
        static func effectiveIntervalMonths(item: ScreeningItem,
                                            presentFlags: [ScreeningRiskFlag: ScreeningRisk],
                                            age: Int? = nil) -> Int? {
            guard var interval = item.intervalMonths(atAge: age) else { return nil }
            for modifier in item.modifiers {
                guard presentFlags[modifier.flag] != nil,
                      let override = modifier.intervalMonthsOverride else { continue }
                interval = min(interval, override)
            }
            return interval
        }

        // MARK: Helpers

        /// Most recent record per item id.
        static func latestRecordByItem(_ records: [ScreeningDone]) -> [String: ScreeningDone] {
            records.reduce(into: [:]) { acc, record in
                if let existing = acc[record.itemID], existing.performedOn >= record.performedOn { return }
                acc[record.itemID] = record
            }
        }

        /// Whole months elapsed, floored at zero.
        static func wholeMonths(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
            guard end > start else { return 0 }
            return max(0, calendar.dateComponents([.month], from: start, to: end).month ?? 0)
        }

        /// Display order: what needs doing, then what is coming, then what is
        /// settled, then what is only worth a conversation.
        private static func sortRank(_ status: Status) -> Int {
            switch status.state {
            case .due: return 0
            case .upcoming: return 1
            case .upToDate: return 2
            case .notYetEligible: return 3
            case .discussOnly: return 4
            case .pastStopAge: return 5
            }
        }

        // MARK: Page derivations

        /// 60 when something comes due, plus 4 per year late, capped at 80, so a
        /// screening card never outranks an acute health card.
        static func priority(monthsLate: Int) -> Int {
            min(80, 60 + 4 * (monthsLate / 12))
        }

        /// The recommended screenings that apply today: due, coming up, or done
        /// on time. The denominator of "3 / 9".
        static func applicableRecommended(_ statuses: [Status]) -> [Status] {
            statuses.filter { status in
                guard status.item.tier == .recommended else { return false }
                switch status.state {
                case .due, .upcoming, .upToDate: return true
                case .notYetEligible, .pastStopAge, .discussOnly: return false
                }
            }
        }

        /// When nothing is due, the applicable screening closest to its date.
        static func nextApplicable(_ statuses: [Status]) -> Status? {
            applicableRecommended(statuses)
                .compactMap { status in status.nextDue.map { (status, $0) } }
                .min { $0.1 < $1.1 }?
                .0
        }

        /// Where today sits on the rail from the last screening to its next due
        /// date: 0 the day it was done, 1 the day it comes due, past 1 when
        /// late. nil without both ends.
        static func railFraction(lastDone: Date?, nextDue: Date?, today: Date = Date()) -> Double? {
            guard let lastDone, let nextDue, nextDue > lastDone else { return nil }
            let span = nextDue.timeIntervalSince(lastDone)
            return max(0, today.timeIntervalSince(lastDone) / span)
        }

        /// A rail needs two ends.
        static func hasRail(_ status: Status) -> Bool {
            switch status.state {
            case .due, .upcoming: return true
            case .upToDate(let until): return until < .distantFuture
            case .notYetEligible, .pastStopAge, .discussOnly: return false
            }
        }

        /// Verdict severity, for the page to map onto its own palette.
        enum Severity: Sendable, Equatable {
            /// Due more than a year.
            case late
            /// Due under a year.
            case due
            case upcoming
            case upToDate
            /// Not coloured as a problem: a weakly evidenced screening is not a
            /// failing grade, and neither is an age not reached yet.
            case neutral
        }

        static func severity(_ status: Status) -> Severity {
            switch status.state {
            case .due(let monthsLate): return monthsLate >= 12 ? .late : .due
            case .upcoming: return .upcoming
            case .upToDate: return .upToDate
            case .notYetEligible, .pastStopAge, .discussOnly: return .neutral
            }
        }

        static func statusIcon(_ status: Status) -> String? {
            switch status.state {
            case .due: return "exclamationmark.circle.fill"
            case .upToDate: return "checkmark.circle.fill"
            case .upcoming: return "calendar"
            case .notYetEligible, .pastStopAge, .discussOnly: return nil
            }
        }

        // MARK: Copy

        /// "3 years late" past a year, "7 months late" under it, nil when on
        /// time.
        static func lateLabel(monthsLate: Int) -> String? {
            guard let value = lateValue(monthsLate: monthsLate) else { return nil }
            return "\(value) late"
        }

        /// "3 years" or "7 months", nil when on time.
        static func lateValue(monthsLate: Int) -> String? {
            guard monthsLate > 0 else { return nil }
            if monthsLate >= 12 {
                let years = monthsLate / 12
                return years == 1 ? "1 year" : "\(years) years"
            }
            return monthsLate == 1 ? "1 month" : "\(monthsLate) months"
        }

        /// "3 years late" when one is due, "Due, up to 3 years late" when
        /// several are, "Due now" when the worst came due this month.
        static func dueCaption(worst: Status, dueCount: Int) -> String {
            guard let late = lateLabel(monthsLate: worst.monthsLate) else { return "Due now" }
            return dueCount == 1 ? late : "Due, up to \(late)"
        }

        /// The row's status word. `monthYear` formats a date as the page wants
        /// ("March 2019").
        static func statusText(_ status: Status, monthYear: (Date) -> String) -> String {
            switch status.state {
            case .due(let monthsLate):
                return lateLabel(monthsLate: monthsLate) ?? "Due now"
            case .upcoming(let date):
                return "Next: \(monthYear(date))"
            case .upToDate(let until):
                return until < .distantFuture ? "Up to date" : "Done, once is enough"
            case .notYetEligible(let startsAtAge):
                return "From age \(startsAtAge)"
            case .pastStopAge:
                return "No longer routine at your age"
            case .discussOnly:
                return status.lastDone == nil ? "Ask your doctor" : "Up to date"
            }
        }

        /// Last recorded date, plus the reason a cadence was pulled forward.
        /// nil renders no second line.
        static func subline(_ status: Status, monthYear: (Date) -> String) -> String? {
            var parts: [String] = []
            if let last = status.lastDone {
                parts.append("Last: \(monthYear(last))")
            } else if status.item.tier == .recommended {
                parts.append("Never recorded")
            }
            if status.appliedFlags.contains(where: \.isFamilyHistory) {
                parts.append("Earlier because of your family history")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
        }
    }
}

// MARK: - Calendar

extension SomaTools {

    /// One screening on the calendar: when it comes due, and where it stands.
    nonisolated struct ScreeningDue: Sendable, Equatable, Identifiable {
        enum State: String, Sendable, Equatable {
            /// The due date has passed, or it never was done and the age is
            /// reached.
            case overdue
            /// Comes due inside the next ninety days.
            case soon
            /// An age not reached yet, past ninety days.
            case later
            /// Done, and not due again for more than ninety days (or never).
            case done
        }

        let item: ScreeningItem
        /// nil for a once in a lifetime screening that is done.
        let dueDate: Date?
        let state: State
        let lastDone: Date?

        var id: String { item.id }

        init(item: ScreeningItem, dueDate: Date?, state: State, lastDone: Date?) {
            self.item = item
            self.dueDate = dueDate
            self.state = state
            self.lastDone = lastDone
        }
    }

    /// The due engine read against a profile: a date per screening instead of
    /// a status, for the calendar and its reminders.
    ///
    /// Only what can come due is listed: a `.discuss` item, an item gated on
    /// an unanswered risk, and an item past its stop age never reach the
    /// calendar, the same guarantees as the engine.
    nonisolated enum ScreeningSchedule {

        /// - Returns: nothing without a birthday. Without a sex, the items for
        ///   everyone only.
        static func due(for profile: SomaProfile,
                        ledger: ScreeningLedger,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> [ScreeningDue] {
            guard let birthday = profile.birthday,
                  let age = profile.age(on: now, calendar: calendar), age > 0 else { return [] }
            let statuses = ledger.statuses(age: age, sex: eligibility(profile.sex), today: now,
                                           birthday: birthday, calendar: calendar)
            return statuses
                .compactMap { entry($0, birthday: birthday, now: now, calendar: calendar) }
                .sorted { lhs, rhs in
                    let l = rank(lhs.state), r = rank(rhs.state)
                    if l != r { return l < r }
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (a?, b?) where a != b: return a < b
                    case (.some, nil): return true
                    case (nil, .some): return false
                    default: return lhs.item.id < rhs.item.id
                    }
                }
        }

        /// The catalog's side of a profile's sex. "Other, or prefer not to
        /// say" picks no side, like an unknown one.
        static func eligibility(_ sex: BiologicalSex?) -> ScreeningEligibility? {
            switch sex {
            case .male: .male
            case .female: .female
            case .other, nil: nil
            }
        }

        /// What the page still has to ask, once.
        static func missing(_ profile: SomaProfile) -> (age: Bool, sex: Bool) {
            (profile.birthday == nil, profile.sex == nil)
        }

        /// The profile the schedule reads: the person's own profile first,
        /// what the ledger asked to fill its gaps, then the age Apple Health
        /// holds as a last resort for the birthday.
        static func resolved(_ base: SomaProfile,
                             askedSex: String?,
                             askedBirthday: Date?,
                             healthAgeYears: Double?,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> SomaProfile {
            var profile = base
            if profile.sex == nil, let askedSex {
                profile.sex = BiologicalSex(rawValue: askedSex.lowercased())
                    ?? eligibility(fromLedger: askedSex)
            }
            if profile.birthday == nil {
                if let askedBirthday {
                    profile.birthday = askedBirthday
                } else if let years = healthAgeYears, years > 0 {
                    profile.birthday = calendar.date(byAdding: .day, value: -Int((years * 365.25).rounded()), to: now)
                }
            }
            return profile
        }

        private static func eligibility(fromLedger sex: String) -> BiologicalSex? {
            switch ScreeningEligibility.from(profileSex: sex) {
            case .male: .male
            case .female: .female
            case .any, nil: nil
            }
        }

        // MARK: One status

        private static func entry(_ status: ScreeningDueEngine.Status,
                                  birthday: Date,
                                  now: Date,
                                  calendar: Calendar) -> ScreeningDue? {
            let horizon = calendar.date(byAdding: .day, value: ScreeningDueEngine.upcomingHorizonDays, to: now) ?? now
            func reaching(_ age: Int) -> Date? { calendar.date(byAdding: .year, value: age, to: birthday) }
            func due(_ date: Date?, _ state: ScreeningDue.State) -> ScreeningDue {
                ScreeningDue(item: status.item, dueDate: date, state: state, lastDone: status.lastDone)
            }
            switch status.state {
            case .due:
                // Never done: due since the birthday that made it apply.
                return due(status.nextDue ?? reaching(status.effectiveStartAge), .overdue)
            case .upcoming(let date):
                return due(date, .soon)
            case .upToDate(let until):
                return due(until < .distantFuture ? until : nil, .done)
            case .notYetEligible(let startsAtAge):
                let date = reaching(startsAtAge)
                return due(date, (date.map { $0 <= horizon } ?? false) ? .soon : .later)
            case .pastStopAge, .discussOnly:
                return nil
            }
        }

        private static func rank(_ state: ScreeningDue.State) -> Int {
            switch state {
            case .overdue: 0
            case .soon: 1
            case .later: 2
            case .done: 3
            }
        }
    }
}
