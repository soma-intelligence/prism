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
        static func statuses(age: Int,
                             sex: ScreeningEligibility?,
                             today: Date = Date(),
                             records: [ScreeningDone],
                             risk: [ScreeningRisk],
                             catalog: [ScreeningItem] = ScreeningCatalog.items,
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
                           presentFlags: presentFlags, calendar: calendar)
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
                                   calendar: Calendar) -> Status {
            let applied = item.modifiers.map(\.flag).filter { presentFlags[$0] != nil }
            let startAge = effectiveStartAge(item: item, presentFlags: presentFlags)
            let interval = effectiveIntervalMonths(item: item, presentFlags: presentFlags)

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

            let next: Date
            if let override = last.nextDueOverride {
                next = override
            } else if let interval {
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

        /// The shortest cadence any answered flag argues for. A once in a
        /// lifetime item stays once in a lifetime.
        static func effectiveIntervalMonths(item: ScreeningItem,
                                            presentFlags: [ScreeningRiskFlag: ScreeningRisk]) -> Int? {
            guard var interval = item.intervalMonths else { return nil }
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
