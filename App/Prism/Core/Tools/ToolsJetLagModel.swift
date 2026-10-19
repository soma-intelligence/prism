//
//  ToolsJetLagModel.swift
//  Prism
//
//  Jet-lag detection and circadian re-entrainment, as pure functions.
//
//  The body clock re-entrains roughly 1 h/day after an eastward
//  (phase-advance) trip and 1.5 h/day after a westward (phase-delay)
//  trip, because the intrinsic period (~24.18 h) makes delays easier
//  than advances (Czeisler 1999; Waterhouse 2007). Bright daylight
//  speeds re-entrainment (engineering heuristic, capped ~2x), and very
//  large eastward shifts can re-entrain "the long way" by delaying
//  (antidromic, Lu 2016). Detection is free: the device UTC offset
//  changes on arrival.
//

import Foundation

extension SomaTools {

    /// Which way the body clock must move to re-align with local time.
    nonisolated enum ShiftDirection: String, Sendable {
        case advance   // eastward travel: the clock must move EARLIER
        case delay     // westward travel: the clock must move LATER
    }

    /// Phase-response-curve light timing (Khalsa 2003). Guidance should be
    /// anchored on the estimated, still-drifting body clock, not local
    /// clock time.
    nonisolated struct LightAdvice: Sendable, Equatable {
        /// Eastward (advance): seek morning light, avoid late-evening light.
        let seekMorningLight: Bool
        /// Westward (delay): seek evening light, avoid early-morning light.
        let seekEveningLight: Bool
        /// For large eastward jumps, light just before vs just after the
        /// core-body-temperature minimum (~2 to 3 h before habitual wake)
        /// shifts the clock in OPPOSITE directions, so mistimed "morning"
        /// light can delay rather than advance. Surface as a caveat.
        let cbtMinCaveat: Bool
    }

    /// The live jet-lag state for a day. `nil` from the model means no
    /// detectable travel (north-south, same zone, or DST).
    nonisolated struct JetLagState: Sendable, Equatable {
        /// zones > 0 and re-entrainment not yet complete.
        var active: Bool
        /// Time zones crossed (absolute).
        var zones: Int
        var direction: ShiftDirection
        /// Estimated days to fully re-entrain.
        var recoveryDays: Int
        /// 0 to 100, how far re-entrainment has progressed.
        var recoveryPct: Int
        /// Hours the body clock still leads/lags local time.
        var residualMisalignmentH: Double
        var daysSinceArrival: Int
        var lightGuidance: LightAdvice
        /// Low-dose melatonin near target bedtime is worthwhile from ~5
        /// zones, especially eastward (Herxheimer 2002). Information, not a
        /// prescription.
        var melatoninSuggested: Bool

        /// Days still to adjust, never negative.
        var daysLeft: Int { max(0, recoveryDays - daysSinceArrival) }

        /// 1-based day of the adjustment, capped at the last day.
        var dayNumber: Int { min(recoveryDays, daysSinceArrival + 1) }

        /// The residual misalignment rounded to whole hours, the figure a clock
        /// line quotes. 0 means caught up. The body clock is BEHIND local time
        /// after an eastward trip (`.advance`) and AHEAD after a westward one.
        var residualWholeHours: Int { max(0, Int(residualMisalignmentH.rounded())) }
        var bodyClockIsBehind: Bool { direction == .advance }
    }

    // MARK: Pure recovery model

    nonisolated enum JetLagModel {

        /// Unaided re-entrainment rate eastward (phase advance), h/day.
        static let advanceRate = 1.0          // Waterhouse 2007
        /// Unaided re-entrainment rate westward (phase delay), h/day.
        static let delayRate = 1.5            // ~50% faster than eastward
        /// At or above this many eastward zones the clock may re-entrain the
        /// long way round (by delaying), which can be faster.
        static let antidromicZones = 8        // Lu 2016
        /// Daylight minutes that give the full (capped) speed-up.
        static let daylightFullBoostMin = 120.0   // proposed heuristic, ~2x ceiling
        /// Crossing this many zones makes melatonin worthwhile.
        static let melatoninZones = 5         // Herxheimer 2002

        static func zones(shiftHours: Double) -> Int { Int(abs(shiftHours).rounded()) }

        /// East (positive shift) needs a phase ADVANCE.
        static func isEast(shiftHours: Double) -> Bool { shiftHours > 0 }

        /// Days to re-entrain `zones` zones, sped up by the daylight the
        /// user actually got. Daylight only approximates the timed-light
        /// dose, so the boost is capped at ~2x the unaided rate, well under
        /// the ~3 to 4 h/day timed-light ceiling.
        static func recoveryDays(zones: Int, east: Bool, daylightMin: Double) -> Int {
            guard zones > 0 else { return 0 }
            let base = east ? advanceRate : delayRate
            let boost = 1 + min(1, max(0, daylightMin / daylightFullBoostMin))
            let rate = base * boost
            var days = Int((Double(zones) / rate).rounded(.up))
            // Antidromic correction for very large eastward shifts.
            if east && zones >= antidromicZones {
                days = min(days, Int((Double(24 - zones) / delayRate).rounded(.up)))
            }
            return max(1, days)
        }

        /// The jet-lag state for a signed time-zone shift, `daysSinceArrival`
        /// days after landing. nil when no zones were crossed.
        static func state(shiftHours: Double,
                          daysSinceArrival: Int,
                          daylightMin: Double) -> JetLagState? {
            let z = zones(shiftHours: shiftHours)
            guard z > 0 else { return nil }
            let east = isEast(shiftHours: shiftHours)
            let days = recoveryDays(zones: z, east: east, daylightMin: daylightMin)
            let elapsed = max(0, daysSinceArrival)
            let frac = min(1, max(0, Double(elapsed) / Double(days)))
            return JetLagState(
                active: frac < 1,
                zones: z,
                direction: east ? .advance : .delay,
                recoveryDays: days,
                recoveryPct: Int((frac * 100).rounded()),
                residualMisalignmentH: (1 - frac) * Double(z),
                daysSinceArrival: elapsed,
                lightGuidance: LightAdvice(seekMorningLight: east,
                                           seekEveningLight: !east,
                                           cbtMinCaveat: east && z >= antidromicZones),
                melatoninSuggested: z >= melatoninZones)
        }

        // MARK: Travel detection from an offset history

        /// One daily sample of the device's UTC offset. The caller owns the
        /// storage; this engine only reads the history.
        nonisolated struct OffsetSample: Codable, Sendable, Equatable {
            /// Local-calendar day index (days in the era), so the day boundary
            /// rolls at local midnight.
            let day: Int
            /// Device UTC offset in hours.
            let offset: Double
            /// Time-zone identifier: distinguishes travel from a DST transition,
            /// which keeps the identifier while only the offset moves.
            let timeZoneID: String
        }

        /// The most recent travel event whose new offset has persisted across at
        /// least one overnight: the signed shift in hours and the arrival day.
        /// nil when there is no qualifying change. Samples are sorted by day
        /// first.
        static func latestTravel(_ samples: [OffsetSample]) -> (shiftHours: Double, arrivalDay: Int)? {
            let entries = samples.sorted { $0.day < $1.day }
            guard let current = entries.last else { return nil }
            // Walk back to the start of the current offset and zone block.
            var arrival = entries.count - 1
            while arrival > 0,
                  entries[arrival - 1].offset == current.offset,
                  entries[arrival - 1].timeZoneID == current.timeZoneID {
                arrival -= 1
            }
            guard arrival > 0 else { return nil }
            let prev = entries[arrival - 1]
            let shift = current.offset - prev.offset
            // Travel only: the zone identifier changed (excludes DST) and
            // the offset moved by at least ~1 zone.
            guard current.timeZoneID != prev.timeZoneID, abs(shift) >= 0.5 else { return nil }
            // Must have persisted across one overnight or more, so a sub-day
            // layover does not count.
            guard current.day - entries[arrival].day >= 1 else { return nil }
            return (shift, entries[arrival].day)
        }

        /// The local-calendar day index `OffsetSample.day` expects.
        static func dayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
            calendar.ordinality(of: .day, in: .era, for: date)
                ?? Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
        }

        /// The live state from an offset history, `today` being a day index as
        /// `dayIndex(_:)` returns it. nil when no qualifying travel is found.
        static func state(samples: [OffsetSample],
                          today: Int,
                          daylightMin: Double) -> JetLagState? {
            guard let travel = latestTravel(samples) else { return nil }
            return state(shiftHours: travel.shiftHours,
                         daysSinceArrival: today - travel.arrivalDay,
                         daylightMin: daylightMin)
        }
    }
}
