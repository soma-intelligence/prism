//
//  OnboardingPermissionsTests.swift
//  PrismTests
//

import CoreLocation
import Foundation
import Testing
@testable import Prism

/// The onboarding reads each permission off the system rather than keeping an
/// answer of its own. A refusal and a restriction both mean Settings is the
/// only way back, so they read the same.
@Suite("Onboarding permissions")
@MainActor
struct OnboardingPermissionsTests {
    @Test("Location: never asked, allowed, or declined whether refused or restricted")
    func location() {
        #expect(OnboardingPermission.state(for: .notDetermined) == .notAsked)
        #expect(OnboardingPermission.state(for: .denied) == .declined)
        #expect(OnboardingPermission.state(for: .restricted) == .declined)
        #expect(OnboardingPermission.state(for: .authorizedAlways) == .allowed)
    }
}
