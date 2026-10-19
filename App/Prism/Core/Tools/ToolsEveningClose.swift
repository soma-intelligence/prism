//
//  ToolsEveningClose.swift
//  Prism
//
//  Evening Close: the digital curfew, as a plain
//  schedule and its statistics. It closes the evening at a time derived from
//  bedtime and opens again at wake.
//
//  What was left out: actually blocking apps. That needs FamilyControls and
//  ManagedSettings, which this app does not have, so here the schedule is a
//  commitment the user keeps and logs, and the stats read those logs. The
//  rules below are the ones the blocking version used, so the day a shield is
//  wired the numbers do not change meaning.
//
//  Everything arrives as an argument: no clock, no store, no defaults. The
//  schedule and the sessions are Codable values the caller persists as JSON.
//

import Foundation

extension SomaTools {

    nonisolated enum EveningClose {

        // MARK: Closing time from bedtime

        /// Wind down starts this long before bedtime, the lead the circadian
        /// plan uses (45 minutes).
        static let windDownLeadHours = 0.75
        /// Sleep debt below this is noise, and a close time that drifted on
        /// noise would read as a bug rather than as care.
        static let debtFloorHours: Double = 2
        /// Half an hour earlier per hour of debt past the floor.
        static let debtShiftPerHour: Double = 0.5
        /// Never more than this. Nothing about being tired argues for closing
        /// three hours early, and an uncapped shift eventually wraps into
        /// daylight.
        static let debtShiftCapHours: Double = 1
        /// Shortest window worth scheduling. The blocking version could not arm
        /// anything shorter; the rule is kept so a window means the same thing.
        static let minimumWindowMinutes = 15

        /// Clock hour wrapped into [0, 24).
        static func wrap24(_ hour: Double) -> Double {
            let wrapped = hour.truncatingRemainder(dividingBy: 24)
            return wrapped < 0 ? wrapped + 24 : wrapped
        }

        /// When wind down starts for a given bedtime.
        static func windDownHour(bedtimeHour: Double) -> Double {
            wrap24(bedtimeHour - windDownLeadHours)
        }

        /// When the evening closes once sleep debt has had its say.
        ///
        /// THE SHIFT ONLY EVER GOES EARLIER. A sleep bank is not an argument for
        /// more screen at night, so a negative debt moves nothing.
        static func closeHour(windDownHour: Double?, sleepDebtHours: Double) -> Double? {
            guard let windDownHour else { return nil }
            let over = max(0, sleepDebtHours - debtFloorHours)
            let shift = min(debtShiftCapHours, over * debtShiftPerHour)
            return wrap24(windDownHour - shift)
        }

        /// Closing time straight from bedtime: wind down, then the debt shift.
        static func closeHour(bedtimeHour: Double, sleepDebtHours: Double = 0) -> Double {
            closeHour(windDownHour: windDownHour(bedtimeHour: bedtimeHour),
                      sleepDebtHours: sleepDebtHours) ?? bedtimeHour
        }

        /// Minutes the debt pulled the close earlier than plain wind down, 0 when
        /// it moved nothing. The page explains a shifted close with this.
        static func debtShiftMinutes(sleepDebtHours: Double) -> Int {
            let over = max(0, sleepDebtHours - debtFloorHours)
            return Int((min(debtShiftCapHours, over * debtShiftPerHour) * 60).rounded())
        }

        // MARK: Windows

        enum WindowKind: String, Codable, Sendable, CaseIterable {
            /// The evening close, from close time to wake.
            case curfew
            /// The vigilance peak, protected for deep work.
            case deepWork
        }

        /// One stretch of the day. Clock hours in [0, 24); an `endHour` below
        /// `startHour` wraps past midnight, which the curfew almost always does.
        struct Window: Sendable, Equatable, Identifiable {
            var kind: WindowKind
            var startHour: Double
            var endHour: Double
            var id: String { kind.rawValue }

            /// Length in hours, following the wrap.
            var lengthHours: Double {
                let raw = endHour - startHour
                return raw > 0 ? raw : raw + 24
            }
        }

        /// Today's readings, flattened, so the rules can be called from a test
        /// with numbers typed by hand.
        struct TriggerInputs: Sendable, Equatable {
            var windDownHour: Double?
            var wakeHour: Double?
            var deepWorkStartHour: Double?
            var deepWorkEndHour: Double?
            /// Hours of sleep debt today. Negative (a bank) is treated as zero.
            var sleepDebtHours: Double
            /// True when a peak exists today but the calendar leaves no stretch
            /// of it long enough (see AirlockDeepWorkPlanner). A separate flag,
            /// because "no peak" and "the day filled it" are two sentences.
            var deepWorkBookedOut: Bool

            init(windDownHour: Double? = nil, wakeHour: Double? = nil,
                 deepWorkStartHour: Double? = nil, deepWorkEndHour: Double? = nil,
                 sleepDebtHours: Double = 0, deepWorkBookedOut: Bool = false) {
                self.windDownHour = windDownHour
                self.wakeHour = wakeHour
                self.deepWorkStartHour = deepWorkStartHour
                self.deepWorkEndHour = deepWorkEndHour
                self.sleepDebtHours = sleepDebtHours
                self.deepWorkBookedOut = deepWorkBookedOut
            }
        }

        /// The windows for today. A trigger switched on with nothing to read
        /// produces NO window, and that is not an error: the page says what is
        /// missing rather than inventing an hour. A window under the minimum is
        /// dropped.
        static func triggerWindows(curfewEnabled: Bool,
                                   deepWorkEnabled: Bool,
                                   inputs: TriggerInputs) -> [Window] {
            var windows: [Window] = []
            if curfewEnabled,
               let start = closeHour(windDownHour: inputs.windDownHour, sleepDebtHours: inputs.sleepDebtHours),
               let end = inputs.wakeHour {
                windows.append(Window(kind: .curfew, startHour: start, endHour: end))
            }
            if deepWorkEnabled,
               let start = inputs.deepWorkStartHour,
               let end = inputs.deepWorkEndHour {
                windows.append(Window(kind: .deepWork, startHour: start, endHour: end))
            }
            let floor = Double(minimumWindowMinutes) / 60
            return windows.filter { $0.lengthHours >= floor }
        }

        // MARK: Schedule

        /// A one day change to the schedule: skip that evening, or move its
        /// hours.
        struct Exception: Codable, Sendable, Equatable, Identifiable {
            /// "yyyy-MM-dd" of the evening it changes, see `dayKey`.
            var dayKey: String
            /// Replacement close hour, nil to keep the schedule's.
            var closeHour: Double?
            /// Replacement open hour, nil to keep the schedule's.
            var openHour: Double?
            /// True to skip the evening entirely.
            var skip: Bool
            var note: String?
            var id: String { dayKey }

            init(dayKey: String, closeHour: Double? = nil, openHour: Double? = nil,
                 skip: Bool = false, note: String? = nil) {
                self.dayKey = dayKey
                self.closeHour = closeHour
                self.openHour = openHour
                self.skip = skip
                self.note = note
            }
        }

        /// The evening close schedule. Every field decodes leniently, so a field
        /// added later cannot wipe a schedule already stored.
        struct Schedule: Codable, Sendable, Equatable {
            var isEnabled: Bool
            /// Clock hour the evening closes, used as is unless
            /// `followsBedtime` and a bedtime is known.
            var closeHour: Double
            /// Clock hour it opens again (wake).
            var openHour: Double
            /// Calendar weekdays it runs on, 1 = Sunday through 7 = Saturday.
            var weekdays: Set<Int>
            /// When true the close hour is derived from bedtime and sleep debt
            /// each day (see `closeHour(bedtimeHour:sleepDebtHours:)`).
            var followsBedtime: Bool
            var exceptions: [Exception]

            static let allWeekdays: Set<Int> = Set(1...7)

            init(isEnabled: Bool = false,
                 closeHour: Double = 22,
                 openHour: Double = 7,
                 weekdays: Set<Int> = Schedule.allWeekdays,
                 followsBedtime: Bool = true,
                 exceptions: [Exception] = []) {
                self.isEnabled = isEnabled
                self.closeHour = EveningClose.wrap24(closeHour)
                self.openHour = EveningClose.wrap24(openHour)
                self.weekdays = weekdays.filter { (1...7).contains($0) }
                self.followsBedtime = followsBedtime
                self.exceptions = exceptions
            }

            private enum CodingKeys: String, CodingKey {
                case isEnabled, closeHour, openHour, weekdays, followsBedtime, exceptions
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let base = Schedule()
                self.init(
                    isEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? base.isEnabled,
                    closeHour: (try? c.decodeIfPresent(Double.self, forKey: .closeHour)) ?? base.closeHour,
                    openHour: (try? c.decodeIfPresent(Double.self, forKey: .openHour)) ?? base.openHour,
                    weekdays: (try? c.decodeIfPresent(Set<Int>.self, forKey: .weekdays)) ?? base.weekdays,
                    followsBedtime: (try? c.decodeIfPresent(Bool.self, forKey: .followsBedtime)) ?? base.followsBedtime,
                    exceptions: (try? c.decodeIfPresent([Exception].self, forKey: .exceptions)) ?? [])
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(isEnabled, forKey: .isEnabled)
                try c.encode(closeHour, forKey: .closeHour)
                try c.encode(openHour, forKey: .openHour)
                try c.encode(weekdays.sorted(), forKey: .weekdays)
                try c.encode(followsBedtime, forKey: .followsBedtime)
                try c.encode(exceptions, forKey: .exceptions)
            }

            // MARK: Edits

            mutating func setWeekday(_ weekday: Int, on: Bool) {
                guard (1...7).contains(weekday) else { return }
                if on { weekdays.insert(weekday) } else { weekdays.remove(weekday) }
            }

            /// Upserts the exception for its day.
            mutating func setException(_ exception: Exception) {
                exceptions.removeAll { $0.dayKey == exception.dayKey }
                exceptions.append(exception)
                exceptions.sort { $0.dayKey < $1.dayKey }
            }

            mutating func removeException(dayKey: String) {
                exceptions.removeAll { $0.dayKey == dayKey }
            }

            /// Drops exceptions for evenings before `date`, which can no longer
            /// change anything.
            mutating func pruneExceptions(before date: Date, calendar: Calendar = .current) {
                let key = EveningClose.dayKey(date, calendar: calendar)
                exceptions.removeAll { $0.dayKey < key }
            }

            func exception(on date: Date, calendar: Calendar = .current) -> Exception? {
                let key = EveningClose.dayKey(date, calendar: calendar)
                return exceptions.first { $0.dayKey == key }
            }

            // MARK: Reads

            /// Whether the evening of `date` is meant to close at all.
            func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
                guard isEnabled else { return false }
                if exception(on: date, calendar: calendar)?.skip == true { return false }
                return weekdays.contains(calendar.component(.weekday, from: date))
            }

            /// The close and open hours for the evening of `date`, exception
            /// first, then bedtime when followed and known, then the stored hour.
            func hours(on date: Date,
                       bedtimeHour: Double? = nil,
                       sleepDebtHours: Double = 0,
                       calendar: Calendar = .current) -> (close: Double, open: Double) {
                let exception = exception(on: date, calendar: calendar)
                var close = closeHour
                if followsBedtime, let bedtimeHour {
                    close = EveningClose.closeHour(bedtimeHour: bedtimeHour, sleepDebtHours: sleepDebtHours)
                }
                if let override = exception?.closeHour { close = EveningClose.wrap24(override) }
                let open = exception?.openHour.map(EveningClose.wrap24) ?? openHour
                return (close, open)
            }

            /// The evening's window, or nil when it is not scheduled.
            func window(on date: Date,
                        bedtimeHour: Double? = nil,
                        sleepDebtHours: Double = 0,
                        calendar: Calendar = .current) -> Window? {
                guard isScheduled(on: date, calendar: calendar) else { return nil }
                let h = hours(on: date, bedtimeHour: bedtimeHour, sleepDebtHours: sleepDebtHours,
                              calendar: calendar)
                let window = Window(kind: .curfew, startHour: h.close, endHour: h.open)
                return window.lengthHours * 60 >= Double(EveningClose.minimumWindowMinutes) ? window : nil
            }

            /// The absolute close and open instants for the evening of `date`. A
            /// close hour before noon belongs to the same evening, after
            /// midnight; the open always follows the close.
            func interval(on date: Date,
                          bedtimeHour: Double? = nil,
                          sleepDebtHours: Double = 0,
                          calendar: Calendar = .current) -> DateInterval? {
                guard let window = window(on: date, bedtimeHour: bedtimeHour,
                                          sleepDebtHours: sleepDebtHours, calendar: calendar) else { return nil }
                return EveningClose.interval(closeHour: window.startHour, openHour: window.endHour,
                                             evening: date, calendar: calendar)
            }
        }

        /// Absolute close and open instants for an evening.
        static func interval(closeHour: Double, openHour: Double,
                             evening date: Date, calendar: Calendar = .current) -> DateInterval {
            let dayStart = calendar.startOfDay(for: date)
            let closeAbs = closeHour < 12 ? closeHour + 24 : closeHour
            var openAbs = openHour
            while openAbs <= closeAbs { openAbs += 24 }
            let close = dayStart.addingTimeInterval(closeAbs * 3600)
            let open = dayStart.addingTimeInterval(openAbs * 3600)
            return DateInterval(start: close, end: open)
        }

        /// "yyyy-MM-dd" in the calendar's own time zone.
        static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }

        // MARK: Sessions

        /// One stretch of the evening kept closed. Running while `endedAt` is
        /// nil; a row of history once it is not.
        struct Session: Codable, Sendable, Equatable, Identifiable {
            enum EndReason: String, Codable, Sendable {
                /// Stopped with the ordinary control, or reached its open time.
                case completed
                /// Stopped through the emergency exit.
                case abandoned
                /// Ended by something other than the user.
                case expired
            }

            let id: UUID
            let startedAt: Date
            /// When the session is due to open, nil for one only the user ends.
            var endsAt: Date?
            var endedAt: Date?
            var endReason: EndReason?

            init(id: UUID = UUID(), startedAt: Date, endsAt: Date? = nil,
                 endedAt: Date? = nil, endReason: EndReason? = nil) {
                self.id = id
                self.startedAt = startedAt
                self.endsAt = endsAt
                self.endedAt = endedAt
                self.endReason = endReason
            }

            var isRunning: Bool { endedAt == nil }

            /// Seconds it stayed closed. An ended session stops at its own end:
            /// reading it against `now` would make every history row grow.
            func elapsed(at now: Date) -> TimeInterval {
                max(0, (endedAt ?? now).timeIntervalSince(startedAt))
            }

            /// Seconds before it opens, floored at zero, nil for a manual one.
            func remaining(at now: Date) -> TimeInterval? {
                guard let endsAt else { return nil }
                return max(0, endsAt.timeIntervalSince(now))
            }

            /// The session closed out.
            func ended(at date: Date, reason: EndReason) -> Session {
                var next = self
                next.endedAt = date
                next.endReason = reason
                return next
            }
        }

        /// What a stop the user asked for is recorded as.
        static func manualStopReason(isEmergency: Bool) -> Session.EndReason {
            isEmergency ? .abandoned : .completed
        }

        /// How a running session must be closed right now, or nil to leave it.
        static func forcedEnd(now: Date, running: Session?) -> Session.EndReason? {
            guard let running, running.isRunning, let endsAt = running.endsAt else { return nil }
            return now >= endsAt ? .completed : nil
        }

        // MARK: Days closed on time

        /// A close counts as on time when it starts no later than this after the
        /// close time.
        static let onTimeGraceMinutes = 15
        /// A session started this long before the close time still closes that
        /// evening (closing early is fine; a lunch time session is not an
        /// evening close).
        static let earlyWindowHours = 3.0

        enum DayOutcome: Sendable, Equatable {
            /// Closed within the grace, and not left through the emergency exit.
            case closedOnTime
            /// Closed, but after the grace.
            case closedLate
            /// Closed, then left through the emergency exit.
            case openedEarly
            /// Nothing closed and the evening is over.
            case missed
            /// The evening has not finished yet and nothing decides it.
            case pending
            /// Not scheduled (weekday off, skipped by an exception, or disabled).
            case notScheduled

            /// Whether the outcome keeps a streak going. Pending and unscheduled
            /// evenings neither count nor break.
            var breaksStreak: Bool {
                switch self {
                case .closedLate, .openedEarly, .missed: return true
                case .closedOnTime, .pending, .notScheduled: return false
                }
            }
        }

        struct DayRecord: Sendable, Equatable, Identifiable {
            let day: Date
            let outcome: DayOutcome
            /// Minutes kept closed that evening, across its sessions.
            let closedMinutes: Double
            var id: Date { day }
        }

        /// The outcome of the evening of `date`.
        ///
        /// `bedtimeHour` feeds a bedtime following schedule for every day read;
        /// pass nil to use the stored close hour. A session belongs to the
        /// evening it started in (from `earlyWindowHours` before the close to
        /// the open).
        static func outcome(on date: Date,
                            schedule: Schedule,
                            sessions: [Session],
                            now: Date,
                            bedtimeHour: Double? = nil,
                            calendar: Calendar = .current) -> DayOutcome {
            guard let interval = schedule.interval(on: date, bedtimeHour: bedtimeHour, calendar: calendar) else {
                return .notScheduled
            }
            let evening = eveningSessions(sessions, interval: interval)
            let grace = interval.start.addingTimeInterval(TimeInterval(onTimeGraceMinutes * 60))

            if evening.contains(where: { $0.endReason == .abandoned }) { return .openedEarly }
            if evening.contains(where: { $0.startedAt <= grace }) { return .closedOnTime }
            if !evening.isEmpty { return .closedLate }
            return now >= interval.end ? .missed : .pending
        }

        static func eveningSessions(_ sessions: [Session], interval: DateInterval) -> [Session] {
            let from = interval.start.addingTimeInterval(-earlyWindowHours * 3600)
            return sessions.filter { $0.startedAt >= from && $0.startedAt < interval.end }
        }

        /// The last `days` evenings, oldest first, today last.
        static func dayRecords(days: Int,
                               endingOn now: Date,
                               schedule: Schedule,
                               sessions: [Session],
                               bedtimeHour: Double? = nil,
                               calendar: Calendar = .current) -> [DayRecord] {
            guard days > 0 else { return [] }
            let today = calendar.startOfDay(for: now)
            return (0..<days).reversed().compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let outcome = outcome(on: day, schedule: schedule, sessions: sessions, now: now,
                                      bedtimeHour: bedtimeHour, calendar: calendar)
                let seconds = sessions
                    .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                    .reduce(0.0) { $0 + $1.elapsed(at: now) }
                return DayRecord(day: day, outcome: outcome, closedMinutes: (seconds / 60).rounded())
            }
        }

        /// Consecutive scheduled evenings closed on time, counting back from
        /// today. A pending tonight and unscheduled evenings are stepped over.
        /// `lookbackDays` bounds the walk.
        static func streak(endingOn now: Date,
                           schedule: Schedule,
                           sessions: [Session],
                           bedtimeHour: Double? = nil,
                           lookbackDays: Int = 366,
                           calendar: Calendar = .current) -> Int {
            let today = calendar.startOfDay(for: now)
            var count = 0
            for offset in 0..<max(0, lookbackDays) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
                let outcome = outcome(on: day, schedule: schedule, sessions: sessions, now: now,
                                      bedtimeHour: bedtimeHour, calendar: calendar)
                if outcome.breaksStreak { break }
                if outcome == .closedOnTime { count += 1 }
            }
            return count
        }

        /// The week in numbers.
        struct Summary: Sendable, Equatable {
            /// Sessions started in the window, the running one included.
            let sessionCount: Int
            /// Seconds kept closed over the window.
            let closedSeconds: TimeInterval
            /// Sessions left through the emergency exit.
            let emergencyExits: Int
            /// Evenings closed on time.
            let daysClosedOnTime: Int
            /// Evenings that were scheduled and are decided (pending excluded).
            let scheduledDays: Int
            let streak: Int

            /// Share of decided scheduled evenings closed on time, nil with none.
            var onTimeRate: Double? {
                scheduledDays > 0 ? Double(daysClosedOnTime) / Double(scheduledDays) : nil
            }
        }

        /// Summary over the last `days` days (a week by default). A session is
        /// attributed to the day it STARTED.
        static func summary(days: Int = 7,
                            endingOn now: Date,
                            schedule: Schedule,
                            sessions: [Session],
                            bedtimeHour: Double? = nil,
                            calendar: Calendar = .current) -> Summary {
            let today = calendar.startOfDay(for: now)
            let windowStart = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
            let week = sessions.filter { $0.startedAt >= windowStart }
            let records = dayRecords(days: max(1, days), endingOn: now, schedule: schedule,
                                     sessions: sessions, bedtimeHour: bedtimeHour, calendar: calendar)
            let decided = records.filter { $0.outcome != .notScheduled && $0.outcome != .pending }
            return Summary(sessionCount: week.count,
                           closedSeconds: week.reduce(0) { $0 + $1.elapsed(at: now) },
                           emergencyExits: week.filter { $0.endReason == .abandoned }.count,
                           daysClosedOnTime: records.filter { $0.outcome == .closedOnTime }.count,
                           scheduledDays: decided.count,
                           streak: streak(endingOn: now, schedule: schedule, sessions: sessions,
                                          bedtimeHour: bedtimeHour, calendar: calendar))
        }

        // MARK: Formatting

        /// "22:30" from a clock hour.
        static func clockLabel(_ hour: Double) -> String {
            let minutes = Int((wrap24(hour) * 60).rounded()) % (24 * 60)
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }

        /// "8h 30" or "45 min".
        static func durationLabel(hours: Double) -> String {
            let total = Int((hours * 60).rounded())
            guard total >= 60 else { return "\(total) min" }
            let m = total % 60
            return m == 0 ? "\(total / 60)h" : String(format: "%dh %02d", total / 60, m)
        }
    }
}
