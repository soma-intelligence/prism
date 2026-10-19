//
//  ToolsNapArchitectEngine.swift
//  Prism
//
//  Pure derivation of today's optimal nap from a SAFTE alertness curve plus
//  the expected bedtime.
//
//  The three answers, from the sleep science:
//   1. WHEN: the post-lunch circadian dip, the afternoon trough of the SAFTE
//      curve, where sleep pressure and circadian propensity align (Lovato and
//      Lack, 2010).
//   2. HOW LONG: a short power nap by default (about 20 min) to skip slow-wave
//      sleep and wake without grogginess (Dinges et al., 1987). Only a heavy
//      sleep-pressure day earns a full 90 min cycle, which ends in light sleep
//      so the wake is still clean.
//   3. HARD CUTOFF: the latest a nap may start before it eats into night
//      sleep, bedtime minus a fixed guard window, so a nap always clears
//      enough wake time to rebuild night pressure.
//
//  Also holds the pure pieces of the nap page: the day curve built from last
//  night, the pressure word bands, the multi-day trend, the four week program
//  calendar and the agenda fit.
//

import Foundation

extension SomaTools {

    nonisolated enum NapArchitectEngine {

        private typealias Clock = SleepSupport.Clock

        // MARK: Tunables

        /// Sleep pressure (0..100, higher = sleepier) at or above which a nap
        /// is worth taking. Below it the afternoon dip is shallow enough to
        /// ride out.
        ///
        /// ANCHORED TO WHAT THE CURVE CAN REACH. This model's afternoon dip runs
        /// about 24 on a full night and about 36 on a four-hour one, so both
        /// bars sit inside that reachable band. A test recomputes those two
        /// anchors from SAFTE so a recalibration of the curve fails loudly.
        static let pressureThreshold = 26.0

        /// The default nap: short enough to stay out of deep sleep, long enough
        /// to clear the adenosine backlog (Dinges et al., 1987).
        static let powerNapMinutes = 20

        /// One full ultradian cycle. The upper bound the duration optimizer
        /// will ever recommend, so a nap never crosses two slow-wave gates.
        static let fullCycleMinutes = 90

        /// Sleep pressure above which a full cycle is preferred over a power
        /// nap. Above the normal-night dip, below the short-night one.
        static let heavyPressure = 34.0

        /// Hours before expected bedtime after which a nap starts stealing
        /// night sleep. Naps inside this guard blunt the evening rise in sleep
        /// pressure.
        static let bedtimeGuardHours = 6.0

        /// The afternoon band the circadian dip is searched inside (clock hours).
        static let dipSearchStart = 11.0
        static let dipSearchEnd = 17.0

        /// Reservoir seed of the day curve, as a share of SAFTE capacity.
        static let curveSeedFraction = 0.55

        // MARK: Plan

        nonisolated struct Plan: Sendable, Equatable {
            /// Clock hour of the afternoon circadian trough (the ideal nap onset).
            var dipHour: Double
            /// When the nap window opens (the dip) and the hard cutoff it closes at.
            var windowStartHour: Double
            var hardCutoffHour: Double
            /// False when the cutoff falls before the dip (very early bedtime):
            /// no safe afternoon window exists.
            var hasWindow: Bool
            /// Suggested nap length and the room left before night sleep is at risk.
            var recommendedMinutes: Int
            var maxMinutes: Int
            /// Sleep pressure at `nowHour`, 0..100, higher = sleepier.
            var currentPressure: Double
            /// True when now sits inside the window and pressure clears the bar.
            var isOpenNow: Bool
            /// True when now is past the hard cutoff (a nap here costs tonight).
            var pastCutoff: Bool
        }

        // MARK: Derivation

        /// - Parameters:
        ///   - samples: the SAFTE curve for the day, ordered by clock hour.
        ///   - nowHour: current wall clock hour, 0..24.
        ///   - expectedBedtimeHour: tonight's expected bedtime, 0..24.
        /// - Returns: nil when the curve holds no afternoon sample at all. An
        ///   invented fallback hour would present itself as a measured trough.
        static func plan(samples: [SAFTEEngine.Sample],
                         nowHour: Double,
                         expectedBedtimeHour: Double) -> Plan? {

            guard let dip = afternoonDip(samples) else { return nil }
            let dipHour = dip.clockHour

            // WRAPPED: `bedtime - 6` is negative for every bedtime between
            // 00:00 and 05:59, and unwrapped those readers were told "no safe
            // nap window" every single day.
            let hardCutoff = Clock.wrap24(expectedBedtimeHour - bedtimeGuardHours)

            // A cutoff that has wrapped all the way round to BEFORE the dip is
            // genuinely not a window: a 19:00 bedtime leaves no safe afternoon.
            let hasWindow = hardCutoff > dipHour

            let pressure = currentPressure(samples, at: nowHour)

            // Measured forward on the circle, so an after-midnight cutoff reads
            // as the couple of hours it is and not as twenty-two.
            let sinceCutoff = Clock.forward(from: hardCutoff, to: nowHour)
            let cutoffToBed = Clock.forward(from: hardCutoff, to: expectedBedtimeHour)
            let pastCutoff = hasWindow && sinceCutoff > 0 && sinceCutoff < cutoffToBed

            // The room actually left, not a constant 90.
            let roomHours = (hasWindow && !pastCutoff)
                ? Clock.forward(from: nowHour, to: hardCutoff)
                : 0
            let maxMinutes = min(fullCycleMinutes, max(0, Int((roomHours * 60).rounded())))

            let wanted = pressure >= heavyPressure ? fullCycleMinutes : powerNapMinutes
            // No room left is not a six minute nap: below one power nap the
            // honest answer is that there is no nap to recommend.
            let recommended = maxMinutes >= powerNapMinutes ? min(wanted, maxMinutes) : 0

            let sinceDip = Clock.forward(from: dipHour, to: nowHour)
            let dipToCutoff = Clock.forward(from: dipHour, to: hardCutoff)
            let openNow = hasWindow
                && sinceDip <= dipToCutoff
                && recommended > 0
                && pressure >= pressureThreshold

            return Plan(dipHour: dipHour,
                        windowStartHour: dipHour,
                        hardCutoffHour: hardCutoff,
                        hasWindow: hasWindow,
                        recommendedMinutes: recommended,
                        maxMinutes: maxMinutes,
                        currentPressure: pressure,
                        isOpenNow: openNow,
                        pastCutoff: pastCutoff)
        }

        /// The lowest-effectiveness sample inside the afternoon search band:
        /// the post-lunch circadian trough.
        private static func afternoonDip(_ samples: [SAFTEEngine.Sample]) -> SAFTEEngine.Sample? {
            samples
                .filter { $0.clockHour >= dipSearchStart && $0.clockHour <= dipSearchEnd }
                .min(by: { $0.effectiveness < $1.effectiveness })
        }

        /// Sleep pressure at a clock hour: the inverse of SAFTE effectiveness,
        /// so 100 is maximally sleepy and 0 fully alert. Nearest sample on the
        /// 24 h circle.
        private static func currentPressure(_ samples: [SAFTEEngine.Sample], at hour: Double) -> Double {
            guard let nearest = samples.min(by: {
                Clock.distance($0.clockHour, hour) < Clock.distance($1.clockHour, hour)
            }) else { return 0 }
            return min(100, max(0, 100 - nearest.effectiveness))
        }

        // MARK: Day curve from last night

        /// The SAFTE curve the nap page reads: last night asleep, then awake
        /// from the wake hour until the same bed hour tonight, reservoir seeded
        /// at `curveSeedFraction` of capacity.
        static func dayCurve(bedHour: Double,
                             wakeHour: Double,
                             sleepMinutes: Double,
                             cbtMinHour: Double = 4.0) -> [SAFTEEngine.Sample] {
            let awakeMinutes = Clock.forward(from: wakeHour, to: bedHour) * 60
            let segments = [
                SAFTEEngine.Segment(minutes: max(1, sleepMinutes), asleep: true, startClockHour: bedHour),
                SAFTEEngine.Segment(minutes: awakeMinutes, asleep: false, startClockHour: wakeHour)
            ]
            return SAFTEEngine.curve(over: segments,
                                     from: SAFTEEngine.reservoirCapacity * curveSeedFraction,
                                     cbtMinHour: cbtMinHour)
        }

        /// Today's plan from last night's recorded bed and wake instants.
        /// Tonight's bedtime is assumed to be last night's bed hour.
        static func plan(lastNightBed bed: Date,
                         wake: Date,
                         now: Date,
                         cbtMinHour: Double = SAFTEEngine.Chronotype.intermediate.seedCBTminHour,
                         calendar: Calendar = .current) -> Plan? {
            let bedHour = Clock.hour(of: bed, calendar: calendar)
            let wakeHour = Clock.hour(of: wake, calendar: calendar)
            let sleepMinutes = max(1, wake.timeIntervalSince(bed) / 60)
            let samples = dayCurve(bedHour: bedHour, wakeHour: wakeHour,
                                   sleepMinutes: sleepMinutes, cbtMinHour: cbtMinHour)
            return plan(samples: samples,
                        nowHour: Clock.hour(of: now, calendar: calendar),
                        expectedBedtimeHour: bedHour)
        }

        // MARK: Pressure bands

        /// Interpretation bands for today's sleep pressure (0..100), built on
        /// the engine's own thresholds so the word scale never drifts from the
        /// numbers the plan used.
        nonisolated enum PressureBand: String, Sendable, Equatable, CaseIterable {
            case light, moderate, heavy

            init(pressure: Double) {
                switch pressure {
                case ..<NapArchitectEngine.pressureThreshold: self = .light
                case ..<NapArchitectEngine.heavyPressure: self = .moderate
                default: self = .heavy
                }
            }

            /// Lower and upper bound of the band (nil means open ended).
            var bounds: (lower: Double?, upper: Double?) {
                switch self {
                case .light: return (nil, NapArchitectEngine.pressureThreshold)
                case .moderate: return (NapArchitectEngine.pressureThreshold, NapArchitectEngine.heavyPressure)
                case .heavy: return (NapArchitectEngine.heavyPressure, nil)
                }
            }
        }

        // MARK: Trend

        /// Trailing window for the personal pressure trend, in days.
        static let trendWindowDays = 14
        /// Minimum non-nil days before the trend is honest enough to draw
        /// (the reliable-baseline floor of 7 nights).
        static let trendMinimumDays = 7

        /// This same wall-clock hour's sleep pressure over the trailing window,
        /// oldest first, plus the personal mean excluding today.
        nonisolated struct Trend: Sendable, Equatable {
            /// A missing night is a genuine gap (nil), never a fabricated zero.
            let series: [Double?]
            /// Personal average over the same window, excluding today.
            let baselineMean: Double?
        }

        /// Nil below `trendMinimumDays` usable days in the window.
        static func trend(series fullSeries: [Double?]) -> Trend? {
            let window = Array(fullSeries.suffix(trendWindowDays))
            guard window.compactMap({ $0 }).count >= trendMinimumDays else { return nil }
            // The baseline excludes the trailing (today's) slot: comparing
            // today against a mean that already includes today flattens it.
            let prior = window.dropLast().compactMap { $0 }
            let baseline = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
            return Trend(series: window, baselineMean: baseline)
        }

        // MARK: Four week program

        /// Program length. Four phases, one week each.
        static let programWeeks = 4

        /// 0-based program week from the enrollment date, clamped to
        /// [0, programWeeks - 1].
        static func programWeekIndex(start: Date, now: Date, calendar: Calendar = .current) -> Int {
            min(programWeeks - 1, max(0, programDays(start: start, now: now, calendar: calendar) / 7))
        }

        /// True once the enrollment is older than the whole program. The
        /// clamped week index cannot answer this.
        static func programIsFinished(start: Date, now: Date, calendar: Calendar = .current) -> Bool {
            programDays(start: start, now: now, calendar: calendar) / 7 >= programWeeks
        }

        private static func programDays(start: Date, now: Date, calendar: Calendar) -> Int {
            let d0 = calendar.startOfDay(for: start)
            let d1 = calendar.startOfDay(for: now)
            return calendar.dateComponents([.day], from: d0, to: d1).day ?? 0
        }

        // MARK: Agenda fit

        /// What the day's agenda does to the nap window.
        nonisolated enum AgendaFit: Sendable, Equatable {
            /// A free gap long enough for the recommended nap, inside the
            /// window, as clock hours of `day`.
            case gap(start: Double, end: Double)
            /// The window is booked end to end.
            case full
        }

        /// The nap window crossed with the day's busy intervals. Nil when there
        /// is no window or no meeting at all (nothing more to say than the
        /// window itself). The gap must hold the RECOMMENDED length, not an
        /// absolute minimum.
        static func agendaFit(plan: Plan,
                              day: Date,
                              busy: [DateInterval],
                              calendar: Calendar = .current) -> AgendaFit? {
            guard plan.hasWindow, !busy.isEmpty else { return nil }
            let dayStart = calendar.startOfDay(for: day)
            guard let windowStart = calendar.date(byAdding: .second,
                                                  value: Int(plan.windowStartHour * 3600),
                                                  to: dayStart),
                  let windowEnd = calendar.date(byAdding: .second,
                                                value: Int(plan.hardCutoffHour * 3600),
                                                to: dayStart),
                  windowEnd > windowStart else { return nil }
            let window = DateInterval(start: windowStart, end: windowEnd)
            guard let gap = longestFreeGap(busy: busy,
                                           minimumMinutes: plan.recommendedMinutes,
                                           within: window) else { return .full }
            return .gap(start: gap.start.timeIntervalSince(dayStart) / 3600,
                        end: gap.end.timeIntervalSince(dayStart) / 3600)
        }

        /// Longest free stretch of `window` between merged busy intervals, or
        /// nil when none reaches `minimumMinutes`.
        static func longestFreeGap(busy: [DateInterval],
                                   minimumMinutes: Int,
                                   within window: DateInterval) -> DateInterval? {
            let minimum = TimeInterval(minimumMinutes * 60)
            var merged: [DateInterval] = []
            for span in busy.sorted(by: { $0.start < $1.start }) where span.end > span.start {
                if let last = merged.last, span.start <= last.end {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
                } else {
                    merged.append(span)
                }
            }
            var gaps: [DateInterval] = []
            var cursor = window.start
            for span in merged {
                guard span.end > window.start, span.start < window.end else { continue }
                let blockedStart = max(span.start, window.start)
                if blockedStart.timeIntervalSince(cursor) >= minimum {
                    gaps.append(DateInterval(start: cursor, end: blockedStart))
                }
                cursor = max(cursor, min(span.end, window.end))
            }
            if window.end.timeIntervalSince(cursor) >= minimum {
                gaps.append(DateInterval(start: cursor, end: window.end))
            }
            return gaps.max { $0.duration < $1.duration }
        }
    }
}
