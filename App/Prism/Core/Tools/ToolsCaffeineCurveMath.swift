//
//  ToolsCaffeineCurveMath.swift
//  Prism
//
//  The pure arithmetic behind the caffeine curve: the window it is drawn over,
//  and whether there is still an open stretch inside it.
//

import Foundation

extension SomaTools {

    nonisolated enum CaffeineCurveMath {

        // MARK: Is there still a window to draw

        /// Whether there is still an open stretch between waking and the deadline.
        /// Not just "under budget": a very heavy day can push the deadline before
        /// wake (or into yesterday), and a day strip wraps a band round the clock,
        /// so an inverted range would paint almost the whole day as fine.
        ///
        /// Shared on purpose: a tile and the page it opens draw the same rail from
        /// the same reading; a second copy of this rule is exactly how the two
        /// would end up disagreeing about whether today still has room.
        static func isOpen(reading: CaffeineWindowEngine.Reading,
                           wakeHour: Double,
                           bedtimeHour: Double) -> Bool {
            guard !reading.isOverBudget, let lastCallHour = reading.lastCallHour else { return false }
            let toDeadline = CircadianMath.wrap24(lastCallHour - wakeHour)
            let toBedtime = CircadianMath.wrap24(bedtimeHour - wakeHour)
            return toDeadline > 0 && toDeadline <= toBedtime
        }

        // MARK: The curve window

        /// The window a caffeine curve is drawn over: from just before the day's
        /// first cup (or from now on a day with none) to an hour past bedtime, so
        /// the curve always shows where it lands relative to the threshold
        /// instead of stopping at the deadline.
        static func window(doses: [CaffeineModel.Dose],
                           now: Date,
                           bedtime: Date) -> (start: Date, end: Date) {
            let anchor = min(doses.first?.time ?? now, now)
            return (anchor.addingTimeInterval(-30 * 60), bedtime.addingTimeInterval(3600))
        }
    }
}
