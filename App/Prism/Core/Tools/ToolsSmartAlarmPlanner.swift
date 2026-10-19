//
//  ToolsSmartAlarmPlanner.swift
//  Prism
//
//  Assembles SmartWakeEngine.Inputs from already resolved signals and adds no
//  science: all the computation lives in the engine and in
//  SmartAlarmCalendarConstraint, both pure and tested on fixtures. Reading the
//  signals (HealthKit, the calendar, the circadian history) is the caller's
//  job; this file is the pure rest of the planner.
//
//  The bounds follow one rule:
//   - `latest` = min(set time, bound of the first morning meeting)
//   - `earliest` = `latest` minus the early latitude
//
//  The `min` is the central guarantee: the calendar can only bring the ring
//  FORWARD, never push it back. A 14:00 meeting leaves a 07:00 alarm intact.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmPlanner {

        /// Tonight's recorded hypnogram and its onset (bed time).
        nonisolated struct ObservedNight: Sendable, Equatable {
            var spans: [SleepCycleModel.StageSpan]
            var onset: Date

            init(spans: [SleepCycleModel.StageSpan], onset: Date) {
                self.spans = spans
                self.onset = onset
            }
        }

        /// Everything the planner reads, already resolved by the caller.
        nonisolated struct Signals: Sendable, Equatable {
            /// Habitual wake hour (circular mean of recent nights), or nil when
            /// the history is too short.
            var anchorWakeHour: Double?
            /// Circadian regularity factor, 0...100, or nil when unknown.
            var regularity: Double?
            /// Measured CBTmin clock hour, or nil.
            var cbtMinHour: Double?
            /// Habitual bedtime clock hour (circular mean), or nil. Used to
            /// estimate tonight's onset and the habitual lights out.
            var habitualBedHour: Double?
            /// Raw derived sleep need. Floored at one hour by the planner.
            var sleepNeedSeconds: Int
            /// Sleep balance in hours; negative is a credit, read as zero debt.
            var sleepDebtHours: Double
            var hrvBaseline: Double
            var overnightHRV: Double
            /// Today's strain, on the same scale as `strainSeries`.
            var strainToday: Double
            /// Daily strain ending today (today last), nil entries for gaps,
            /// or nil when there is no history at all.
            var strainSeries: [Double?]?
            /// The most recent recorded night, if any. The planner keeps it only
            /// when it belongs to the night ending at the ring.
            var observedNight: ObservedNight?

            init(anchorWakeHour: Double? = nil,
                 regularity: Double? = nil,
                 cbtMinHour: Double? = nil,
                 habitualBedHour: Double? = nil,
                 sleepNeedSeconds: Int = 8 * 3600,
                 sleepDebtHours: Double = 0,
                 hrvBaseline: Double = 0,
                 overnightHRV: Double = 0,
                 strainToday: Double = 0,
                 strainSeries: [Double?]? = nil,
                 observedNight: ObservedNight? = nil) {
                self.anchorWakeHour = anchorWakeHour
                self.regularity = regularity
                self.cbtMinHour = cbtMinHour
                self.habitualBedHour = habitualBedHour
                self.sleepNeedSeconds = sleepNeedSeconds
                self.sleepDebtHours = sleepDebtHours
                self.hrvBaseline = hrvBaseline
                self.overnightHRV = overnightHRV
                self.strainToday = strainToday
                self.strainSeries = strainSeries
                self.observedNight = observedNight
            }
        }

        /// The plan of the coming night and what the calendar said about it.
        /// The calendar outcome and the bedtime travel next to the plan so no
        /// surface re-derives them and shows a different time.
        nonisolated struct Outcome: Sendable, Equatable {
            var plan: SmartWakeEngine.Plan
            var calendar: SmartAlarmCalendarConstraint.Outcome
            var bedtime: SmartAlarmBedtime.Reading
            /// The engine inputs the plan came from, for inspection.
            var inputs: SmartWakeEngine.Inputs
        }

        static func plan(settings: SmartAlarmSettings,
                         signals: Signals,
                         events: [SmartAlarmCalendarConstraint.Event] = [],
                         now: Date,
                         calendar: Calendar = .current) -> Outcome {
            let wake = nextOccurrence(ofMinutes: settings.wakeMinutes,
                                      after: now, weekdays: settings.activeWeekdays,
                                      calendar: calendar)
            let calendarOutcome = calendarOutcome(settings: settings, wake: wake,
                                                  events: events, calendar: calendar)
            let latest = hardBound(wake: wake, outcome: calendarOutcome)
            let earliest = latest.addingTimeInterval(-settings.earlyWindowMinutes * 60)

            // Yesterday's hypnogram never replaces tonight's estimate.
            let observed: ObservedNight? = signals.observedNight.flatMap { night in
                guard !night.spans.isEmpty,
                      belongsToNight(endingAt: latest, onset: night.onset) else { return nil }
                return night
            }

            // A credit must not shorten the night; it simply adds nothing.
            let debtHours: Double = max(0, signals.sleepDebtHours)
            let hrv: Double = hrvRatio(overnight: signals.overnightHRV, baseline: signals.hrvBaseline)
            let strain: Double = strainRatio(today: signals.strainToday, series: signals.strainSeries)
            let estimated: Date? = estimatedOnset(for: latest, habitualBedHour: signals.habitualBedHour,
                                                  calendar: calendar)
            let onset: Date? = observed?.onset ?? estimated
            let meanCycle: Double? = observed.flatMap { SleepCycleModel.meanCycleSeconds($0.spans) }
            // The engine AND the bedtime read this same floored value: one
            // night, not two.
            let sleepNeed: Int = max(SmartAlarmBedtime.minimumSleepNeedSeconds, signals.sleepNeedSeconds)

            var inputs = SmartWakeEngine.Inputs(
                earliest: earliest,
                latest: latest,
                anchorWakeHour: signals.anchorWakeHour,
                regularity: signals.regularity,
                cbtMinHour: signals.cbtMinHour,
                sleepNeedSeconds: sleepNeed,
                debtHours: debtHours,
                hrvRatio: hrv,
                strainRatio: strain,
                onset: onset,
                onsetLatencySeconds: SmartWakeEngine.defaultOnsetLatencySeconds,
                meanCycleSeconds: meanCycle,
                observedSpans: observed?.spans ?? [],
                observedOnset: observed?.onset,
                priority: settings.priority)
            inputs.calendar = calendar

            let resolved = SmartWakeEngine.plan(inputs)
            // The habitual bedtime is a comparison, not a source: the required
            // bedtime derives from the retained ring, never from the habit.
            let habitual = estimatedOnset(for: resolved.ring, habitualBedHour: signals.habitualBedHour,
                                          calendar: calendar)
            let bedtime = SmartAlarmBedtime.reading(
                ring: resolved.ring,
                sleepNeedSeconds: sleepNeed,
                onsetLatencySeconds: SmartWakeEngine.defaultOnsetLatencySeconds,
                habitualLightsOut: habitual)
            return Outcome(plan: resolved, calendar: calendarOutcome, bedtime: bedtime, inputs: inputs)
        }

        /// The bound retained for the coming night. Only `.bound` moves it;
        /// `.tooEarly` goes up to the surfaces but constrains nothing. The
        /// `min` is the central guarantee: the calendar can only bring the ring
        /// FORWARD.
        static func hardBound(wake: Date, outcome: SmartAlarmCalendarConstraint.Outcome) -> Date {
            guard case .bound(let constraint) = outcome else { return wake }
            return min(wake, constraint.bound)
        }

        /// The calendar outcome for the morning of `wake`, or `.none` when the
        /// toggle is off (checked BEFORE any event is read).
        static func calendarOutcome(settings: SmartAlarmSettings,
                                    wake: Date,
                                    events: [SmartAlarmCalendarConstraint.Event],
                                    calendar: Calendar = .current) -> SmartAlarmCalendarConstraint.Outcome {
            guard settings.calendarAware else { return .none }
            return SmartAlarmCalendarConstraint.outcome(
                events: events,
                wake: wake,
                prepSeconds: settings.calendarPrepMinutes * 60,
                calendar: calendar)
        }

        /// The one-line reason a compact surface shows (a stack card, a Live
        /// Activity, alarm metadata). The calendar leads when it set the
        /// bound; `.tooEarly` does NOT lead, since it did not place the ring.
        nonisolated enum ReasonKind: Sendable, Equatable {
            case calendar(eventTitle: String)
            case cycle
            case recovery
            case phase
            case regularity
            case shortfall
            case anchor
        }

        static func reasonKind(for plan: SmartWakeEngine.Plan,
                               calendarOutcome: SmartAlarmCalendarConstraint.Outcome = .none) -> ReasonKind {
            if case .bound(let constraint) = calendarOutcome {
                return .calendar(eventTitle: constraint.eventTitle)
            }
            for reason in plan.reasons.reversed() {
                switch reason {
                case .cycleAlignment: return .cycle
                case .recoveryExtension: return .recovery
                case .circadianFloor: return .phase
                case .regularityClamp: return .regularity
                case .sleepNeedShortfall: return .shortfall
                case .anchor, .hardBoundClamp: continue
                }
            }
            return .anchor
        }

        // MARK: Assembly

        /// Next occurrence of `minutes` after `after`, restricted to the active
        /// weekdays. An empty weekday set excludes nothing, so the occurrence
        /// can be today. The time is set by calendar COMPONENTS, never by
        /// adding seconds to midnight: the two daylight saving days do not have
        /// 86400 seconds.
        static func nextOccurrence(ofMinutes minutes: Int,
                                   after: Date,
                                   weekdays: Set<Int>,
                                   calendar: Calendar = .current) -> Date {
            let hour = (minutes / 60) % 24
            let minute = minutes % 60
            let day = calendar.startOfDay(for: after)
            for offset in 0...7 {
                guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: day),
                      let candidate = calendar.date(bySettingHour: hour, minute: minute,
                                                    second: 0, of: candidateDay)
                else { continue }
                guard candidate > after else { continue }
                let weekday = calendar.component(.weekday, from: candidate)
                if weekdays.isEmpty || weekdays.contains(weekday) { return candidate }
            }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
                ?? tomorrow
        }

        /// Beyond this age a hypnogram no longer describes the night ending at
        /// the ring. Sixteen hours cover the earliest bedtime that can belong
        /// to a given wake without ever reaching the night before.
        static let maxObservedNightSpanSeconds: TimeInterval = 16 * 3600

        /// Does a bedtime at `onset` belong to the night ending at `latest`?
        /// A bedtime after the ring is not a night, and one older than
        /// `maxObservedNightSpanSeconds` belongs to the previous night. This is
        /// the guarantee that the engine never works on last night's
        /// hypnogram, which would keep the ring stuck on the bound every day.
        static func belongsToNight(endingAt latest: Date, onset: Date) -> Bool {
            guard onset < latest else { return false }
            return latest.timeIntervalSince(onset) <= maxObservedNightSpanSeconds
        }

        /// Estimated onset of the coming night: the habitual bedtime, projected
        /// onto the night before `wake`.
        static func estimatedOnset(for wake: Date,
                                   habitualBedHour: Double?,
                                   calendar: Calendar = .current) -> Date? {
            guard let bedHour = habitualBedHour,
                  let candidate = SmartWakeEngine.instant(forClockHour: bedHour,
                                                          nearest: wake,
                                                          calendar: calendar) else { return nil }
            return candidate < wake ? candidate : candidate.addingTimeInterval(-86_400)
        }

        /// Overnight HRV over its baseline, or 1 (normal) without a baseline.
        static func hrvRatio(overnight: Double, baseline: Double) -> Double {
            baseline > 0 ? overnight / baseline : 1
        }

        /// Today's strain over the recent usual load. The mean excludes today
        /// (the last entry) so the denominator stays independent of the
        /// numerator, and keeps only positive days. 1.0 when unknown (no
        /// strain today, no series, fewer than three earlier days), which
        /// neutralises the term in the recovery budget.
        static func strainRatio(today: Double, series: [Double?]?) -> Double {
            guard today > 0, let series else { return 1 }
            let history = series.dropLast().compactMap { $0 }.filter { $0 > 0 }
            guard history.count >= 3 else { return 1 }
            let mean = history.reduce(0, +) / Double(history.count)
            guard mean > 0 else { return 1 }
            return today / mean
        }
    }
}
