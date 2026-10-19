//
//  ToolsCaffeineHabitualDay.swift
//  Prism
//
//  The user's OWN usual caffeine day, derived from the days they actually
//  logged.
//
//  Exists because a caffeine curve with nothing logged used to fall back to one
//  imaginary reference cup posed exactly at the deadline. That drew a full,
//  convincing day out of a number nobody had ever entered. The honest fallback
//  is the person's own history: the hours they really drink at, and the amounts
//  they really log.
//

import Foundation

extension SomaTools {

    nonisolated enum CaffeineHabitualDay {

        /// One cup of the typical day: the clock hour it usually lands on, and how
        /// much it usually carries.
        nonisolated struct Cup: Sendable, Equatable {
            /// Clock hour, 0 up to 24.
            var hour: Double
            var mg: Double
        }

        /// The shape of a usual day, plus the sample size behind it so a surface
        /// can say what it is built on instead of implying a measurement.
        nonisolated struct Profile: Sendable, Equatable {
            /// Cups in clock order.
            let cups: [Cup]
            /// How many logged days went into it. Days with nothing logged are
            /// gaps, never zeros, so they are not counted here.
            let dayCount: Int

            var totalMg: Double { cups.reduce(0) { $0 + $1.mg } }
        }

        /// How many logged days it takes before a "usual day" is worth drawing.
        /// Below this, one atypical Saturday IS the profile, and a curve built on
        /// two days would overstate what two days can say.
        static let minimumLoggedDays = 3

        /// The usual day behind `dosesByDay` (one slot per calendar day, oldest
        /// first, empty slot means nothing logged that day).
        ///
        /// Medians all the way down, never means: a single 400 mg pre-workout or
        /// one 03:00 flight coffee must not redefine what a usual cup is. The cup
        /// COUNT is the median of the per-day counts, and cup `i` of the profile is
        /// the median hour and median dose of every day's own `i`-th cup, so the
        /// first coffee is compared with first coffees and not with an afternoon
        /// espresso.
        ///
        /// Nil when too few days carry a log: no shape is the honest answer there,
        /// and the caller draws nothing rather than a curve built on two points.
        static func profile(dosesByDay: [[CaffeineModel.Dose]],
                            calendar: Calendar = .current,
                            minimumLoggedDays: Int = minimumLoggedDays) -> Profile? {
            let days = dosesByDay
                .filter { !$0.isEmpty }
                .map { $0.sorted { $0.time < $1.time } }
            guard days.count >= max(1, minimumLoggedDays) else { return nil }

            let cupCount = Int(median(days.map { Double($0.count) })?.rounded() ?? 0)
            guard cupCount >= 1 else { return nil }

            var cups: [Cup] = []
            cups.reserveCapacity(cupCount)
            for slot in 0..<cupCount {
                let atSlot = days.compactMap { $0.count > slot ? $0[slot] : nil }
                guard let hour = median(atSlot.map { clockHour($0.time, calendar: calendar) }),
                      let mg = median(atSlot.map(\.mg)),
                      mg > 0
                else { continue }
                cups.append(Cup(hour: hour, mg: mg))
            }
            guard !cups.isEmpty else { return nil }

            // Per-slot medians are usually already in clock order, but nothing
            // guarantees it (a day that skips its morning coffee shifts every
            // later cup down a slot). Sorting keeps the drawn curve monotonic in
            // time whatever the sample did.
            return Profile(cups: cups.sorted { $0.hour < $1.hour }, dayCount: days.count)
        }

        /// The profile's cups placed on one real day, so the same pharmacokinetics
        /// that draw a measured day draw this one: no second curve builder, no
        /// second convention.
        static func doses(for profile: Profile,
                          on day: Date,
                          calendar: Calendar = .current) -> [CaffeineModel.Dose] {
            let start = calendar.startOfDay(for: day)
            return profile.cups.map {
                CaffeineModel.Dose(mg: $0.mg, time: start.addingTimeInterval($0.hour * 3600))
            }
        }

        // MARK: Pure helpers

        /// Clock hour of an instant, 0 up to 24. Takes its calendar so a test can
        /// pin a timezone instead of inheriting the device's.
        static func clockHour(_ date: Date, calendar: Calendar = .current) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }

        /// Middle value, averaging the two middles on an even count. Nil on an
        /// empty sample rather than zero: "no data" and "zero" are different
        /// answers everywhere in this module.
        static func median(_ values: [Double]) -> Double? {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return nil }
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
    }
}
