//
//  ToolsSAFTEEngine.swift
//  Prism
//
//  SAFTE alertness model (Hursh et al. 2004): a 0 to 100 effectiveness score
//  from a homeostatic sleep reservoir, a two-harmonic circadian process, and
//  post-wake sleep inertia. The homeostatic and inertia parts are exact from
//  sleep timing; only the circadian phase (keyed to a 04:00 default CBTmin via
//  the published acrophases) is soft. Surfaced as a predicted-alertness curve.
//

import Foundation

extension SomaTools {

    /// SAFTE alertness model (Hursh et al. 2004). Pure: every value comes in
    /// through the arguments.
    nonisolated enum SAFTEEngine {

        static let reservoirCapacity = 2880.0    // Rc, arbitrary scale; only 0 to 100 is surfaced
        static let depletionPerMin = 0.5         // K, units/min awake
        static let feedback = 0.0026564          // reservoir-feedback constant
        static let sleepPropensityAmp = 0.55     // a_s
        static let maxSleepIntensity = 4.4       // SI cap, units/min
        static let inertiaMax = 5.0              // Imax, effectiveness points
        static let inertiaDecayPerMin = 0.04     // i
        static let inertiaWindowMin = 120.0      // inertia only in the first 120 min after wake
        static let circ24Acrophase = 18.0        // p, hours
        static let circ12Phase = 21.0            // p + p'
        static let circ12Amplitude = 0.5         // beta
        static let baselineCircAmplitude = 7.0   // a1
        static let debtCircAmplitude = 5.0       // a2

        /// One stretch of the timeline: awake or asleep, with its starting clock hour.
        nonisolated struct Segment: Sendable, Equatable {
            var minutes: Double
            var asleep: Bool
            var startClockHour: Double
            /// Multiplier on `depletionPerMin` for this stretch, awake only.
            ///
            /// SAFTE drains at a flat `depletionPerMin` for every waking
            /// minute, which makes six back to back meetings plus a hard
            /// session cost exactly what a day on the sofa costs. This is the
            /// one hook that lets a caller say a stretch was more expensive.
            ///
            /// Defaults to 1.0. IGNORED WHILE ASLEEP on purpose: sleep does not
            /// deplete, it recovers through the sleep intensity term.
            var depletionScale: Double = 1.0
        }

        /// Two-harmonic circadian process C(Td). Realized peak about 20:00, trough about 04:00.
        static func circadianTerm(clockHour: Double) -> Double {
            cos(2 * Double.pi * (clockHour - circ24Acrophase) / 24)
                + circ12Amplitude * cos(4 * Double.pi * (clockHour - circ12Phase) / 24)
        }

        /// Post-wake sleep inertia (already negative), nonzero only in the first 120 minutes.
        static func inertia(minutesSinceWake: Double, sleepIntensityAtWake: Double) -> Double {
            guard minutesSinceWake >= 0, minutesSinceWake < inertiaWindowMin else { return 0 }
            let si = max(0.0001, sleepIntensityAtWake)
            return -inertiaMax * exp(-(inertiaDecayPerMin * minutesSinceWake) / si)
        }

        /// Effectiveness (0 to 100). Circadian amplitude widens as the reservoir empties.
        static func effectiveness(reservoir: Double,
                                  clockHour: Double,
                                  minutesSinceWake: Double,
                                  sleepIntensityAtWake: Double) -> Double {
            let amplitude = baselineCircAmplitude
                + debtCircAmplitude * (reservoirCapacity - reservoir) / reservoirCapacity
            let e = 100 * (reservoir / reservoirCapacity)
                + amplitude * circadianTerm(clockHour: clockHour)
                + inertia(minutesSinceWake: minutesSinceWake, sleepIntensityAtWake: sleepIntensityAtWake)
            return min(100, max(0, e))
        }

        /// Integrate the reservoir over a timeline (Euler, default 1-minute
        /// step). Awake depletes linearly; sleep recovers by an additive sleep
        /// intensity that grows as the reservoir empties and is modulated by
        /// the circadian sleep-propensity term.
        static func reservoir(over segments: [Segment], from start: Double, stepMin: Double = 1) -> Double {
            var r = min(reservoirCapacity, max(0, start))
            // A non-positive step would never advance `elapsed` and spin forever.
            let step = max(0.01, stepMin)
            for segment in segments {
                var elapsed = 0.0
                while elapsed < segment.minutes {
                    let dt = min(step, segment.minutes - elapsed)
                    if segment.asleep {
                        let clock = (segment.startClockHour + elapsed / 60)
                            .truncatingRemainder(dividingBy: 24)
                        let si = min(maxSleepIntensity,
                                     sleepPropensityAmp * circadianTerm(clockHour: clock)
                                        + feedback * (reservoirCapacity - r))
                        r += max(0, si) * dt
                    } else {
                        r -= depletionPerMin * max(0, segment.depletionScale) * dt
                    }
                    r = min(reservoirCapacity, max(0, r))
                    elapsed += dt
                }
            }
            return r
        }

        /// One point of the surfaced alertness curve.
        nonisolated struct Sample: Sendable, Equatable {
            var clockHour: Double        // wall clock 0..24
            var minutesSinceWake: Double // -1 while asleep, else minutes since the last wake
            var effectiveness: Double    // 0..100
            /// Minutes since the START of the integrated timeline, not since
            /// midnight. It exists for a timeline that replays many nights:
            /// `clockHour` alone cannot say which day a sample belongs to.
            var minuteOffset: Double = 0
        }

        /// Walk the timeline and emit an effectiveness sample every `stepMin`
        /// minutes. Same Euler integration as `reservoir`, but it also tracks
        /// the sleep intensity at the last wake and the minutes since that wake
        /// so the post wake inertia term applies. `cbtMinHour` personalizes the
        /// circadian phase: the user's core body temperature minimum is aligned
        /// to the model's 4.0 default by shifting the clock fed into the
        /// circadian term.
        static func curve(over segments: [Segment],
                          from start: Double,
                          stepMin: Double = 10,
                          cbtMinHour: Double = 4.0) -> [Sample] {
            var r = min(reservoirCapacity, max(0, start))
            let step = max(1, stepMin)
            let phaseShift = 4.0 - cbtMinHour
            var minutesSinceWake = -1.0
            var siAtWake = maxSleepIntensity
            var out: [Sample] = []
            var timelineMinutes = 0.0
            for (index, segment) in segments.enumerated() {
                if !segment.asleep, index > 0, segments[index - 1].asleep {
                    minutesSinceWake = 0
                }
                var elapsed = 0.0
                while elapsed < segment.minutes {
                    let dt = min(step, segment.minutes - elapsed)
                    let clock = (segment.startClockHour + elapsed / 60).truncatingRemainder(dividingBy: 24)
                    let phased = clock + phaseShift
                    if segment.asleep {
                        let si = min(maxSleepIntensity,
                                     sleepPropensityAmp * circadianTerm(clockHour: phased)
                                        + feedback * (reservoirCapacity - r))
                        r += max(0, si) * dt
                        siAtWake = max(0.0001, si)
                        minutesSinceWake = -1
                    } else {
                        // `max(0, ...)` is deliberate: a negative scale would
                        // make waking RECHARGE the reservoir.
                        r -= depletionPerMin * max(0, segment.depletionScale) * dt
                        if minutesSinceWake >= 0 { minutesSinceWake += dt }
                    }
                    r = min(reservoirCapacity, max(0, r))
                    let msw = minutesSinceWake < 0 ? inertiaWindowMin : minutesSinceWake
                    timelineMinutes += dt
                    out.append(Sample(
                        clockHour: clock,
                        minutesSinceWake: minutesSinceWake,
                        effectiveness: effectiveness(reservoir: r,
                                                     clockHour: phased,
                                                     minutesSinceWake: msw,
                                                     sleepIntensityAtWake: siAtWake),
                        minuteOffset: timelineMinutes))
                    elapsed += dt
                }
            }
            return out
        }

        // MARK: Chronotype seed

        /// Seed CBTmin (core body temperature minimum) clock hour per
        /// chronotype, for callers without a measured circadian phase.
        nonisolated enum Chronotype: String, Sendable, Equatable, CaseIterable {
            case morning, intermediate, evening

            var seedCBTminHour: Double {
                switch self {
                case .morning: return 3.5
                case .intermediate: return 4.5
                case .evening: return 5.5
                }
            }
        }
    }
}
