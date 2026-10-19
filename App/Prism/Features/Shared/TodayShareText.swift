//
//  TodayShareText.swift
//  Prism
//

import Foundation

/// What the share sheet hands over.
///
/// Built from what the store actually returned, so a share never claims a number
/// the app does not have.
struct TodayShareText {
    static func make(from health: HealthDashboard) -> String {
        var parts: [String] = []

        if let steps = health.value("HKQuantityTypeIdentifierStepCount") {
            parts.append("\(steps) steps")
        }
        if let energy = health.value("HKQuantityTypeIdentifierActiveEnergyBurned") {
            parts.append("\(energy) kcal active")
        }
        if let exercise = health.value("HKQuantityTypeIdentifierAppleExerciseTime") {
            parts.append("\(exercise) min of exercise")
        }

        guard !parts.isEmpty else {
            return "Nothing recorded in Apple Health today."
        }
        return "Today: " + parts.joined(separator: ", ") + "."
    }
}
