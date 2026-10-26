//
//  AppearanceModeTests.swift
//  PrismTests
//

import SwiftUI
import Testing
@testable import Prism

@Suite("Appearance mode")
struct AppearanceModeTests {
    @Test("Every mode round trips through the name it is stored under")
    func storedNameRoundTrips() {
        for mode in AppearanceMode.allCases {
            #expect(AppearanceMode(storedName: mode.rawValue) == mode)
        }
    }

    @Test("A name that means nothing resolves to nothing, not to a default")
    func unknownNameIsNil() {
        #expect(AppearanceMode(storedName: "editorial") == nil)
        #expect(AppearanceMode(storedName: "") == nil)
    }

    @Test("System forces no scheme; light and dark force their own")
    func schemes() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test("A fresh install follows the phone")
    func freshInstallFollowsTheSystem() {
        #expect(AppearanceMode.fallback == .system)
    }

    @Test("The storage key never changes: renaming it would reset every choice")
    func storageKeyIsStable() {
        #expect(AppearanceMode.storageKey == "appearance.mode")
    }

    @Test("Each mode has a title a person can read, in the order they are offered")
    func titles() {
        #expect(AppearanceMode.allCases.map(\.title) == ["System", "Light", "Dark"])
    }
}
