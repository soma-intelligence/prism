//
//  ToolsCircadianPhaseAlignment.swift
//  Prism
//
//  The phase-alignment readout's pure pieces: the next-window countdown, the three verdict bands
//  on the 0 to 100 alignment score, the 30-day trend mapped from the social
//  jetlag series, and the home-card gate.
//

import Foundation

extension SomaTools {

    nonisolated enum CircadianPhaseAlignment {

        // MARK: Timing

        /// The next window and how far away its start is.
        nonisolated struct NextWindow: Sendable, Equatable {
            let kind: CircadianWindow.Kind
            /// Hours until the window begins, in (0, 24].
            let hoursUntil: Double
            /// The window's start as a clock hour in [0, 24).
            let startHour: Double
        }

        /// Decimal clock hour in [0, 24) for a date (14:30 becomes 14.5).
        static func decimalHour(_ date: Date, calendar: Calendar = .current) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }

        /// The first window to BEGIN after `nowHour`, and how far away it is.
        /// Scans every window's start on the 24 hour circle and keeps the
        /// smallest strictly-forward gap, so a start sitting exactly on
        /// `nowHour` reads as a full day out rather than as the window we are
        /// standing in. nil only when `windows` is empty.
        static func nextWindow(after nowHour: Double, in windows: [CircadianWindow]) -> NextWindow? {
            var best: NextWindow?
            for window in windows {
                var gap = (window.startHour - nowHour).truncatingRemainder(dividingBy: 24)
                if gap <= 0 { gap += 24 }
                if best == nil || gap < best!.hoursUntil {
                    best = NextWindow(kind: window.kind,
                                      hoursUntil: gap,
                                      startHour: CircadianMath.wrap24(window.startHour))
                }
            }
            return best
        }

        /// A window's length in hours, wrapping past midnight with a modulo so a
        /// 22:00 to 01:00 window keeps a positive span (3 h). 0 for a point window.
        static func spanHours(startHour: Double, endHour: Double) -> Double {
            ((endHour - startHour) + 24).truncatingRemainder(dividingBy: 24)
        }

        // MARK: Bands

        /// The three words the alignment score reads as, on fixed cut points.
        /// No red: being out of phase with your own clock is a thing to correct
        /// this week, not an alarm.
        nonisolated enum Band: String, Sendable, CaseIterable {
            /// At or above `alignedFloor`.
            case aligned
            /// Between the two floors.
            case drift
            /// Below `driftFloor`.
            case misaligned
        }

        /// At or above this the day reads as aligned.
        static let alignedFloor = 80
        /// Below this it reads as out of phase; between the two, drifting. The
        /// home card speaks only below this floor.
        static let driftFloor = 55

        static func band(score: Int) -> Band {
            if score >= alignedFloor { return .aligned }
            if score >= driftFloor { return .drift }
            return .misaligned
        }

        /// Whether a home card should surface: only once the plan's score has
        /// fallen below the drift floor. nil score (rMEQ-only seed) never alerts.
        static func shouldAlert(score: Int?) -> Bool {
            guard let score else { return false }
            return score < driftFloor
        }

        // MARK: Trend

        /// Trailing window mapped into the trend chart, in days.
        static let trendDays = 30

        /// Minimum non-nil days before the trend chart and the baseline are worth
        /// showing: enough to say something, never enough to imply more
        /// confidence than three points support.
        static let trendMinimumDays = 3

        /// Maps a day-by-day social-jetlag series through the SAME pure formula
        /// the planner uses for today's headline number
        /// (`CircadianPlanner.alignmentScore(socialJetlagHours:)`), so the trend
        /// line can never disagree with the readout above it about what a given
        /// jetlag value means. Oldest first, gaps preserved: a nil day (a rolling
        /// window without enough free-day nights) stays nil. Mapping it to 0
        /// would print "perfectly aligned" for an unmeasured day.
        static func trend(fromSocialJetlag series: [Double?]) -> [Double?] {
            series.map { jetlag in
                jetlag.flatMap { CircadianPlanner.alignmentScore(socialJetlagHours: $0) }.map(Double.init)
            }
        }

        /// Convenience: the 30-day trend straight from the bed/wake series.
        static func trend(bedHours: [Double?],
                          wakeHours: [Double?],
                          endingOn: Date,
                          days: Int = trendDays,
                          calendar: Calendar = .current) -> [Double?] {
            trend(fromSocialJetlag: CircadianTrends.socialJetlagDailySeries(
                bedHours: bedHours, wakeHours: wakeHours,
                endingOn: endingOn, days: days, calendar: calendar))
        }

        /// True once there are enough mapped trend days to draw the chart and
        /// the baseline.
        static func hasTrend(_ values: [Double?]) -> Bool {
            values.compactMap { $0 }.count >= trendMinimumDays
        }

        /// Mean of the mapped trend's usable days, or nil when there are none.
        static func baselineAverage(_ values: [Double?]) -> Double? {
            let usable = values.compactMap { $0 }
            guard !usable.isEmpty else { return nil }
            return usable.reduce(0, +) / Double(usable.count)
        }
    }
}
