//
//  MetricInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

extension HealthDashboard {
    /// Asks for workouts, heart rate, recovery, distance and the date of
    /// birth, then reads `days` days of workouts with their zones.
    ///
    /// Nil when Health is not there or the request threw; the page then keeps
    /// its dashes and ``MetricLead`` says why.
    func fitnessHistory(days: Int, now: Date = .now) async -> FitnessHistory? {
        guard let source = await prepare(FitnessHistory.metrics) else { return nil }
        return await FitnessHistory.read(from: source, days: days, now: now, calendar: .current)
    }
}

extension FitnessWorkout {
    /// How a session is named in a list: the activity, and the distance on
    /// foot.
    func title(words: MetricWords) -> String {
        guard let distance, distance >= 100 else { return name }
        return "\(name), \(words.km(distance)) km"
    }

    /// The session's length as a list writes it: 48 min, or 1 h 05.
    var length: String {
        let minutes = Int((duration / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}
