//
//  ToolsCaffeineDayBuckets.swift
//  Prism
//
//  Which logged doses belong to ONE day.
//

import Foundation

extension SomaTools {

    nonisolated enum CaffeineDayBuckets {

        /// The doses of one calendar day, oldest first.
        ///
        /// A dose is attributed to the day it was LOGGED on, never to a waking
        /// stretch: a coffee at 00:30 belongs to the day that just started, which is
        /// also the day whose curve will carry it.
        static func doses(_ all: [CaffeineModel.Dose],
                          on day: Date,
                          calendar: Calendar = .current) -> [CaffeineModel.Dose] {
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
            return all
                .filter { $0.time >= start && $0.time < end }
                .sorted { $0.time < $1.time }
        }

        /// The same attribution over a whole trailing window, oldest first, one
        /// slot per calendar day and the last slot being `endingOn`. An empty slot
        /// is a day nobody logged, never a day at zero.
        ///
        /// ONE pass over `all`, bucketed by start-of-day, rather than one filter
        /// per day: the habitual profile asks for thirty days at once, and thirty
        /// linear scans of the same array is how a card build becomes a stall.
        static func byDay(_ all: [CaffeineModel.Dose],
                          days: Int,
                          endingOn day: Date,
                          calendar: Calendar = .current) -> [[CaffeineModel.Dose]] {
            guard days > 0 else { return [] }
            var buckets: [Date: [CaffeineModel.Dose]] = [:]
            for dose in all {
                buckets[calendar.startOfDay(for: dose.time), default: []].append(dose)
            }
            let last = calendar.startOfDay(for: day)
            return (0..<days).reversed().map { offset in
                guard let start = calendar.date(byAdding: .day, value: -offset, to: last) else { return [] }
                return (buckets[start] ?? []).sorted { $0.time < $1.time }
            }
        }
    }
}
