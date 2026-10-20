//
//  TodayRoutesTests.swift
//  PrismTests
//

import Testing
import SomaUI
import HealthExportCore
@testable import Prism

/// Every entry on Today opens its own aspect's page (owner, 2026-10-20: Mind
/// opened Recovery and Activity opened Strain).
@MainActor
struct TodayRoutesTests {
    /// The table the owner asked for: each aspect, its page.
    private static let table: [(SomaAspect, ScoreRoute)] = [
        (.sleep, .sleep), (.mind, .mind), (.activity, .activity),
        (.heart, .heart), (.gut, .gut), (.body, .body),
    ]

    @Test("Each aspect opens its own page from the rings, the orb, the cards, the tiles and All categories")
    func everyEntryOpensItsOwnPage() {
        for (aspect, page) in Self.table {
            #expect(ScoreRoute.aspect(aspect) == page)
            #expect(TodayRoutes.ring(aspect) == page)
            #expect(TodayRoutes.orb(aspect).aspectPage == page)
            #expect(TodayRoutes.aspectCard(aspect) == page)
            #expect(TodayRoutes.tile(aspect) == page)
            #expect(TodayRoutes.allCategories(aspect) == page)
        }
    }

    @Test("Mind no longer opens Recovery, nor Activity Strain, and no two aspects share a page")
    func noBorrowedPages() {
        #expect(TodayRoutes.ring(.mind) != .recovery)
        #expect(TodayRoutes.ring(.activity) != .strain)
        let pages = SomaAspect.allCases.map(ScoreRoute.aspect)
        #expect(Set(pages).count == SomaAspect.allCases.count)
    }

    @Test("The night card opens last night; the sleep score opens the Sleep page")
    func twoSleepPages() {
        #expect(TodayRoutes.nightCard == .lastNight)
        #expect(TodayRoutes.ring(.sleep) == .sleep)
        #expect(TodayRoutes.nightCard != TodayRoutes.ring(.sleep))
    }

    @Test("Heart, Gut and Body lead with a reading the catalog knows, and list readings it knows")
    func readingPagesKnowTheirMetrics() {
        for kind in AspectReadingKind.allCases {
            #expect(HealthMetricCatalog.metric(for: kind.lead) != nil, "\(kind) lead")
            #expect(kind.readings.first == kind.lead)
            for identifier in kind.readings {
                #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier)")
            }
        }
        for identifier in AspectReadingKind.mindReadings + AspectReadingKind.activityReadings + AspectReadingKind.sleepReadings {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier)")
        }
    }
}
