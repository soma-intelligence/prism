//
//  SomaDeepLinkTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Deep links")
struct SomaDeepLinkTests {
    @Test("Every link survives its URL")
    func roundTrip() {
        let links: [SomaDeepLink] = [.checkIn(.morning), .checkIn(.evening), .sleep,
                                     .vaultMetric("HKQuantityTypeIdentifierRestingHeartRate"), .trends, .today, .inbox,
                                     .meetings, .mindAssessments, .mindConnection, .screeningLedger, .medicalRecord]
        for link in links {
            #expect(SomaDeepLink(url: link.url) == link)
            #expect(SomaDeepLink(userInfo: [SomaDeepLink.userInfoKey: link.url.absoluteString]) == link)
        }
        #expect(SomaDeepLink(string: "https://somalabs.me/sleep") == nil)
        #expect(SomaDeepLink(string: "soma://checkin/noon") == nil)
    }

    @Test("Widget URLs parse")
    func widgetURLsParse() {
        #expect(SomaDeepLink(url: URL(string: "soma://score/recovery")!) == .score("recovery"))
        #expect(SomaDeepLink(url: URL(string: "soma://vitals")!) == .vitals)
        #expect(SomaDeepLink(url: URL(string: "soma://fuel")!) == .fuel)
        #expect(SomaDeepLink(url: URL(string: "soma://journal")!) == .journal)
        #expect(SomaDeepLink(url: URL(string: "soma://track/mood")!) == .trackMood)
        #expect(SomaDeepLink(url: URL(string: "soma://track/meal")!) == .trackMeal)
        #expect(SomaDeepLink(url: URL(string: "soma://capture/start")!) == .captureStart)
        #expect(SomaDeepLink(url: URL(string: "soma://score/nonsense")!) == nil)
        #expect(SomaDeepLink(url: URL(string: "soma://track/nonsense")!) == nil)
        #expect(SomaDeepLink(url: URL(string: "soma://capture")!) == nil)
    }

    @Test("Widget links survive their URL")
    func widgetRoundTrip() {
        let links: [SomaDeepLink] = [.score("sleep"), .score("recovery"), .score("strain"), .score("stress"),
                                     .vitals, .fuel, .journal, .trackMood, .trackMeal, .captureStart]
        for link in links { #expect(SomaDeepLink(url: link.url) == link) }
    }

    @Test("The app claims the soma scheme, so a widget's link opens it")
    func schemeRegistered() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(SomaDeepLink.scheme))
    }

    @Test("A notification without a link still opens its place")
    func fallbacks() {
        #expect(SomaNotificationRouter.fallbackLink(for: ReminderPlan.Identifier.morning) == .checkIn(.morning))
        #expect(SomaNotificationRouter.fallbackLink(for: NotificationPlanner.Identifier.bedtime) == .sleep)
        #expect(SomaNotificationRouter.fallbackLink(for: "soma.alert.restingHigh.1") == .inbox)
        #expect(SomaNotificationRouter.fallbackLink(for: ScreeningReminderRules.prefix + "bloodPressure.soon.20261002") == .screeningLedger)
        #expect(SomaNotificationRouter.fallbackLink(for: AppointmentReminderRules.prefix + "x.hour") == .medicalRecord)
    }

    @Test("Screening and record links read from their URL")
    func recordURLsParse() {
        #expect(SomaDeepLink(url: URL(string: "soma://screenings")!) == .screeningLedger)
        #expect(SomaDeepLink(url: URL(string: "soma://record")!) == .medicalRecord)
    }
}
