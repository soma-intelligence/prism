//
//  OnboardingEndSteps.swift
//  Prism
//

import SwiftUI
import SomaUI

// MARK: - Ready

/// The hand over: the run's orb back at full size where Today draws its own,
/// wearing Today's first move. Under it, up to three raw readings when Apple
/// Health already holds data, never a score, because a score needs seven
/// nights. With no data the title reads "You’re in." and no reading shows.
/// Enter opens Today with the orb already in place.
struct OnboardingReadyView: View {
    let model: OnboardingModel

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    private static let steps = "HKQuantityTypeIdentifierStepCount"
    private static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
    private static let variability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"

    private var stepsValue: String? { health.value(Self.steps) }
    private var asleepValue: String? {
        guard let seconds = health.durations[Self.sleep], seconds > 0 else { return nil }
        return SomaFormat.duration(seconds) as String
    }
    private var variabilityValue: String? { health.value(Self.variability) }

    private var hasReadings: Bool {
        stepsValue != nil || asleepValue != nil || variabilityValue != nil
    }

    private var title: String {
        let name = model.profile.firstName
        if hasReadings {
            return name.map { String(localized: "Here you are, \($0).") } ?? String(localized: "Here you are.")
        }
        return name.map { String(localized: "You’re in, \($0).") } ?? String(localized: "You’re in.")
    }

    var body: some View {
        OnboardingPage(title: title, centred: true) {
            if hasReadings {
                SomaStatRow([
                    SomaStat("Steps", value: stepsValue, unit: "today"),
                    SomaStat("Asleep", value: asleepValue, unit: "last night"),
                    SomaStat("HRV", value: variabilityValue, unit: "ms, latest"),
                ])
                .onboardingArrival(1)
            }
            Text("Scores start after seven nights.")
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .onboardingArrival(2)
        }
        .task {
            // Reads again only what was allowed; asks nothing new.
            if health.status == .ready { await health.load() }
        }
    }
}
