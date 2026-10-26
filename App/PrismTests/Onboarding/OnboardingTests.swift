//
//  OnboardingTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The first run's arithmetic: the chronotype the five answers place, the
/// first week's count, the age a birthday gives, the profile surviving a
/// write, and the run's order and gates.
@Suite("Onboarding")
@MainActor
struct OnboardingTests {
    @Test("rMEQ totals land on the published cutoffs")
    func chronotypeCutoffs() {
        #expect(RMEQAnswers(items: [1, 1, 1, 1, 0]).category == .evening)
        #expect(RMEQAnswers(items: [2, 2, 2, 3, 2]).category == .evening)
        #expect(RMEQAnswers(items: [3, 2, 3, 2, 2]).category == .intermediate)
        // Sam in the Figma: 4, 3, 3, 3 and 4 make 17, still intermediate.
        #expect(RMEQAnswers(items: [4, 3, 3, 3, 4]).total == 17)
        #expect(RMEQAnswers(items: [4, 3, 3, 3, 4]).category == .intermediate)
        #expect(RMEQAnswers(items: [4, 3, 3, 4, 4]).category == .morning)
        #expect(RMEQAnswers(items: [5, 4, 5, 5, 6]).total == 25)
    }

    @Test("The catalogue spans 4 to 25, five questions")
    func catalogueRange() {
        #expect(RMEQCatalog.items.count == 5)
        let lowest = RMEQCatalog.items.map { $0.options.map(\.points).min() ?? 0 }.reduce(0, +)
        let highest = RMEQCatalog.items.map { $0.options.map(\.points).max() ?? 0 }.reduce(0, +)
        #expect(lowest == 4)
        #expect(highest == 25)
        #expect(!RMEQAnswers(items: [1, 2, 3]).isComplete)
    }

    @Test("The first week counts nights and stops at seven")
    func firstWeek() {
        #expect(FirstWeek(nightsRecorded: 2).headline == "Two nights in, five to go.")
        #expect(FirstWeek(nightsRecorded: 1).headline == "One night in, six to go.")
        #expect(FirstWeek(nightsRecorded: 0).isLearning)
        #expect(FirstWeek(nightsRecorded: 6).toGo == 1)
        #expect(!FirstWeek(nightsRecorded: 7).isLearning)
        #expect(!FirstWeek(nightsRecorded: 40).isLearning)
        #expect(FirstWeek(nightsRecorded: -3).nights == 0)
    }

    @Test("Age is whole years, not before the birthday")
    func age() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let born = calendar.date(from: DateComponents(year: 1980, month: 3, day: 12))!
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11))!
        let on = calendar.date(from: DateComponents(year: 2026, month: 3, day: 12))!
        #expect(SomaProfile.age(born: born, on: before, calendar: calendar) == 45)
        #expect(SomaProfile.age(born: born, on: on, calendar: calendar) == 46)
    }

    @Test("The profile survives a write and a fresh read")
    func profileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SomaProfileStore(url: url)
        store.update {
            $0.name = "Sam"
            $0.focus = [.sleep, .longevity]
            $0.sex = .female
            $0.chronotype = RMEQAnswers(items: [4, 3, 3, 3, 4])
        }
        let reread = SomaProfileStore(url: url)
        #expect(reread.profile.firstName == "Sam")
        #expect(reread.profile.focus == [.sleep, .longevity])
        #expect(reread.profile.chronotypeCategory == .intermediate)
    }

    @Test("Five screens, in order")
    func order() {
        let model = OnboardingModel(store: SomaProfileStore(url: nil)) {}
        #expect(model.step == .signIn)
        #expect(model.step.progressIndex == 0)
        model.advance()
        #expect(model.step == .focus)
        model.back()
        #expect(model.step == .signIn)
        model.advance()
        #expect(model.step == .focus)
        model.focus = [.sleep]
        model.advance()
        #expect(model.step == .about)
        model.advance()
        #expect(model.step == .connect)
        model.advance()
        #expect(model.step == .ready)
        model.back()
        #expect(model.step == .connect)
    }

    @Test("Continue waits for a focus, then for a birthday and a sex")
    func gates() {
        let store = SomaProfileStore(url: nil)
        let model = OnboardingModel(store: store) {}
        model.go(to: .focus)
        #expect(!model.canContinue)
        model.focus = [.energy, .sleep]
        #expect(model.canContinue)
        model.advance()
        #expect(store.profile.focus == [.energy, .sleep])

        #expect(!model.canContinue)
        model.sex = .female
        #expect(!model.canContinue)
        model.birthday = Date(timeIntervalSince1970: 0)
        model.hasBirthday = true
        model.name = "  Sam "
        #expect(model.canContinue)
        model.advance()
        #expect(store.profile.firstName == "Sam")
        #expect(store.profile.sex == .female)
        #expect(store.profile.birthday == Date(timeIntervalSince1970: 0))
    }

    @Test("A starting birthday is never saved as an answer")
    func startingBirthday() {
        let store = SomaProfileStore(url: nil)
        let model = OnboardingModel(store: store) {}
        model.go(to: .about)
        model.advance()
        #expect(store.profile.birthday == nil)
        #expect(store.profile.name == nil)
    }

    @Test("Ready finishes the run and stamps it")
    func finish() {
        let store = SomaProfileStore(url: nil)
        var finished = false
        let model = OnboardingModel(store: store) { finished = true }
        model.go(to: .ready)
        model.advance()
        #expect(finished)
        #expect(store.profile.onboardedAt != nil)
    }

    @Test("Five segments, email counted as sign in")
    func progress() {
        #expect(OnboardingStep.screens.count == 5)
        #expect(OnboardingStep.signIn.progressIndex == 0)
        #expect(OnboardingStep.email.progressIndex == 0)
        #expect(OnboardingStep.ready.progressIndex == 4)
    }
}

/// The email and password path is hidden until accounts support it: the first
/// screen offers Sign in with Apple and "Not now", and nothing reaches the
/// email screen.
@Suite("Onboarding sign in options")
@MainActor
struct OnboardingSignInOptionsTests {
    @Test("The email path is switched off")
    func emailIsOff() {
        #expect(OnboardingSignInOptions.offersEmail == false)
    }

    @Test("The first screen offers Apple and Not now, no email")
    func ways() {
        #expect(OnboardingSignInOptions.ways() == [.apple, .notNow])
        #expect(!OnboardingSignInOptions.ways().contains(.email))
    }

    @Test("Switching the flag on brings the email way back, between the two")
    func flagBringsItBack() {
        #expect(OnboardingSignInOptions.ways(offersEmail: true) == [.apple, .email, .notNow])
    }

    @Test("The email step cannot be reached while it is off")
    func emailStepUnreachable() {
        let model = OnboardingModel(store: SomaProfileStore(url: nil)) {}
        model.go(to: .email)
        #expect(model.step == .signIn)
        model.advance()
        #expect(model.step == .focus)
        model.back()
        #expect(model.step == .signIn)
    }
}
