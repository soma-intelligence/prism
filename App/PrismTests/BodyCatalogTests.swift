//
//  BodyCatalogTests.swift
//  PrismTests
//

import Testing
import HealthExportCore
@testable import Prism

/// The browse list names 190 data types, and it derives every one of those
/// names from its identifier rather than tabulating them. That derivation is
/// the thing worth pinning: Apple keeps acronyms in caps, and a splitter that
/// does not know it turns VO2Max into three words.
@Suite("Body catalog")
struct BodyCatalogTests {

    @Test("An identifier reads as words, with its acronyms left whole")
    func namesSplitOnWordBoundaries() {
        let cases: [(String, String)] = [
            ("HKQuantityTypeIdentifierStepCount", "Step Count"),
            ("HKQuantityTypeIdentifierRestingHeartRate", "Resting Heart Rate"),
            ("HKQuantityTypeIdentifierVO2Max", "VO2 Max"),
            ("HKQuantityTypeIdentifierUVExposure", "UV Exposure"),
            ("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", "Heart Rate Variability SDNN"),
            ("HKQuantityTypeIdentifierForcedExpiratoryVolume1", "Forced Expiratory Volume 1"),
            ("HKCategoryTypeIdentifierSleepAnalysis", "Sleep Analysis"),
        ]

        for (identifier, expected) in cases {
            let metric = HealthMetric(identifier: identifier, kind: .quantity)
            #expect(metric.displayName == expected)
        }
    }

    @Test("Every identifier the browse list names is one the catalog carries")
    func everyCategoryResolves() {
        for category in BodyCatalog.categories {
            #expect(!category.types.isEmpty, "\(category.title) resolved to nothing")
        }
    }

    @Test("A type claimed by two categories is still offered once")
    func searchDoesNotRepeatATypeInTwoCategories() {
        // Heart rate is both a heart reading and a vital.
        let matches = BodyCatalog.search("Heart Rate")
        let identifiers = matches.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.contains("HKQuantityTypeIdentifierHeartRate"))
    }

    @Test("Search is case insensitive and answers nothing for an empty query")
    func searchIgnoresCaseAndEmptyQueries() {
        #expect(BodyCatalog.search("").isEmpty)
        #expect(BodyCatalog.search("   ").isEmpty)
        #expect(!BodyCatalog.search("vo2").isEmpty)
        #expect(BodyCatalog.searchCategories("SLEEP").map(\.title) == ["Sleep"])
    }

    @Test("Cycle tracking stays scoped away from the launch request")
    func cycleTrackingIsAskedForByItsOwnPage() throws {
        let cycle = try #require(BodyCatalog.categories.first { $0.title == "Cycle Tracking" })
        #expect(cycle.isSensitive)

        let launch = Set(HealthMetricCatalog.launchRequest.map(\.identifier))
        let sensitive = cycle.types.filter { $0.metric.sensitivity == .sensitive }
        #expect(!sensitive.isEmpty)
        for type in sensitive {
            #expect(!launch.contains(type.id), "\(type.id) reached the launch request")
        }
    }
}
