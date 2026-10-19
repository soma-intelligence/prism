//
//  ToolsTripPlanner.swift
//  Prism
//
//  A trip's phase on a given day, and the signed time shift its arrival
//  imposes. Pure, no
//  store: it takes a `Trip` and returns a value.
//
//  `arrivalShiftHours` is the bridge to the jet-lag model: it is the signed
//  shift to hand `JetLagModel.state` once the traveller lands, so the trip
//  PRODUCES the jet-lag state instead of replacing it.
//

import Foundation

extension SomaTools {

    /// One flight of a trip. Everything after `id` is optional, so a persisted
    /// trip decodes whatever it was saved with.
    nonisolated struct TripLeg: Codable, Identifiable, Sendable, Equatable {
        let id: UUID
        var departAt: Date?
        var arriveAt: Date?
        var fromTimeZoneID: String?
        var toTimeZoneID: String?
        /// A flight that crosses the local night of departure. Set by the user
        /// or inferred from a calendar, never by the planner.
        var isRedEye: Bool?
        /// WHICH calendar event it came from. Never its content: a meeting title
        /// does not leave memory.
        var sourceEventID: String?

        /// Flight length in hours, nil when either end is missing.
        var durationHours: Double? {
            guard let departAt, let arriveAt, arriveAt > departAt else { return nil }
            return arriveAt.timeIntervalSince(departAt) / 3600
        }
    }

    /// A trip and its legs.
    nonisolated struct Trip: Codable, Identifiable, Sendable, Equatable {
        let id: UUID
        var startDate: Date
        var title: String?
        var destinationName: String?
        var destinationTimeZoneID: String?
        var endDate: Date?
        var legs: [TripLeg]?
        var updatedAt: Date?
        /// Tombstone. An upsert-only sync cannot propagate a deletion otherwise.
        var deletedAt: Date?

        var isDeleted: Bool { deletedAt != nil }

        /// The first leg, the outbound one.
        var outboundLeg: TripLeg? { legs?.first }

        /// The last leg when there are at least two, else nil: a one-leg trip is
        /// one way, not a return trip.
        var returnLegValue: TripLeg? {
            guard let legs, legs.count >= 2 else { return nil }
            return legs.last
        }
    }

    nonisolated enum TripPhase: Sendable, Equatable {
        case none
        case preDeparture(daysOut: Int)
        case outbound(legIndex: Int)
        /// `of` is nil for a trip with no end date.
        case atDestination(day: Int, of: Int?)
        case returnLeg
        case postReturn(day: Int)
    }

    nonisolated enum TripPlanner {

        /// Past this horizon a trip no longer weighs on the day. Seven days covers
        /// the forecast window without pulling next month's trip into this week.
        static let preDepartureHorizonDays = 7
        /// Past this, the return is digested.
        static let postReturnHorizonDays = 3

        static func phase(for date: Date,
                          trip: Trip,
                          calendar: Calendar = .current) -> TripPhase {
            guard !trip.isDeleted else { return .none }

            let day = calendar.startOfDay(for: date)
            let start = calendar.startOfDay(for: trip.startDate)
            let end = trip.endDate.map { calendar.startOfDay(for: $0) }

            // Before departure.
            if day < start {
                let out = calendar.dateComponents([.day], from: day, to: start).day ?? 0
                return out <= preDepartureHorizonDays ? .preDeparture(daysOut: out) : .none
            }

            // Departure day: the outbound leg.
            if day == start { return .outbound(legIndex: 0) }

            // Return day.
            if let end, day == end { return .returnLeg }

            // After the return.
            if let end, day > end {
                let since = calendar.dateComponents([.day], from: end, to: day).day ?? 0
                return since <= postReturnHorizonDays ? .postReturn(day: since) : .none
            }

            // At the destination. `of` stays nil for an open-ended trip.
            let dayIndex = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            let total = end.flatMap { calendar.dateComponents([.day], from: start, to: $0).day }
            return .atDestination(day: dayIndex, of: total)
        }

        /// The signed shift the arrival imposes, in hours. Positive going east
        /// (phase advance), negative going west. nil when the time zones are
        /// missing.
        ///
        /// Offsets are resolved AT THE ARRIVAL DATE, not now: a flight in August
        /// and one in January to the same airport do not give the same shift,
        /// because of daylight saving time.
        static func arrivalShiftHours(trip: Trip, currentTimeZone: TimeZone = .current) -> Double? {
            guard let leg = trip.outboundLeg else { return nil }
            let fromID = leg.fromTimeZoneID ?? currentTimeZone.identifier
            guard let from = TimeZone(identifier: fromID),
                  let toID = leg.toTimeZoneID ?? trip.destinationTimeZoneID,
                  let to = TimeZone(identifier: toID) else { return nil }
            let at = leg.arriveAt ?? trip.startDate
            let delta = to.secondsFromGMT(for: at) - from.secondsFromGMT(for: at)
            return Double(delta) / 3600
        }

        /// The red-eye leg that takes the night following `date`, if any. A leg
        /// counts for the night of its DEPARTURE day: that is the night whose
        /// sleep it cuts short.
        static func redEyeLeg(on date: Date,
                              trip: Trip,
                              calendar: Calendar = .current) -> TripLeg? {
            guard !trip.isDeleted, let legs = trip.legs else { return nil }
            let day = calendar.startOfDay(for: date)
            return legs.first { leg in
                guard leg.isRedEye == true, let depart = leg.departAt else { return false }
                return calendar.startOfDay(for: depart) == day
            }
        }

        /// The jet-lag state a trip imposes on `date`: the arrival shift fed to
        /// `JetLagModel.state`, counting days from the arrival day. nil before
        /// arrival, for a trip without time zones, or when no zone is crossed.
        static func jetLagState(for date: Date,
                                trip: Trip,
                                daylightMin: Double = 0,
                                calendar: Calendar = .current,
                                currentTimeZone: TimeZone = .current) -> JetLagState? {
            guard !trip.isDeleted,
                  let shift = arrivalShiftHours(trip: trip, currentTimeZone: currentTimeZone) else { return nil }
            let arrival = trip.outboundLeg?.arriveAt ?? trip.startDate
            let days = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: arrival),
                                               to: calendar.startOfDay(for: date)).day ?? 0
            guard days >= 0 else { return nil }
            return JetLagModel.state(shiftHours: shift, daysSinceArrival: days, daylightMin: daylightMin)
        }
    }
}
