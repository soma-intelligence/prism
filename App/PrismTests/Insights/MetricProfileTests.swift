//
//  MetricProfileTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The one table of how a metric is read. A HealthKit key spelled wrong in it
/// never matches a record, so its row silently never applies; a row that
/// contradicts itself draws a chart that says one thing and a band that says
/// another. Types the table leaves out are read from the catalog's kind.
@Suite("Metric profiles")
@MainActor
struct MetricProfileTests {
    @Test("Every HealthKit key in the table is one the catalog knows")
    func keysInCatalog() {
        for identifier in MetricProfile.table.keys where !identifier.hasPrefix("soma.score.") {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("Every band is a real range, under the ceiling when there is one")
    func bands() {
        for (identifier, profile) in MetricProfile.table {
            guard let band = profile.referenceBand else { continue }
            #expect(band.lowerBound < band.upperBound, "\(identifier)")
            if let ceiling = profile.ceiling {
                #expect(band.upperBound <= ceiling, "\(identifier)")
            }
        }
    }

    @Test("A daily total draws bars, and a sparse reading draws dots or pressure pills")
    func charts() {
        for (identifier, profile) in MetricProfile.table {
            if profile.accumulates {
                #expect(profile.chart == .bars, "\(identifier)")
            }
            if profile.sparse {
                #expect([MetricProfile.Chart.points, .bloodPressure].contains(profile.chart), "\(identifier)")
            }
            if profile.projects {
                #expect(profile.sparse, "\(identifier) projects but is not sparse")
            }
        }
    }

    @Test("The engine's preference and today rule follow the row they sit in")
    func policies() {
        for (identifier, profile) in MetricProfile.table {
            guard let policy = profile.policy else { continue }
            let preference: InsightPreference = switch profile.risingIsGood {
            case true: .higher
            case false: .lower
            default: .steady
            }
            #expect(policy.preference == preference, "\(identifier)")
            #expect(policy.partialToday == profile.accumulates, "\(identifier)")
        }
    }

    @Test("Blood pressure draws systolic and diastolic together, whichever opens the page")
    func bloodPressure() {
        #expect(MetricProfile.of(MetricProfile.systolic).chart == .bloodPressure)
        #expect(MetricProfile.of(MetricProfile.diastolic).chart == .bloodPressure)
    }

    @Test("A type the table leaves out is read from its kind in the catalog")
    func fallback() {
        let distance = MetricProfile.of("HKQuantityTypeIdentifierDistanceWalkingRunning")
        #expect(distance.chart == .bars)
        #expect(distance.accumulates)
        #expect(distance.policy == nil)

        let mindful = MetricProfile.of("HKCategoryTypeIdentifierMindfulSession")
        #expect(mindful.chart == .bars)
        #expect(!mindful.accumulates)

        let heartRate = MetricProfile.of("HKQuantityTypeIdentifierHeartRate")
        #expect(heartRate.chart == .line)
        #expect(!heartRate.accumulates)

        let unknown = MetricProfile.of("soma.unknown")
        #expect(unknown.chart == .line)
        #expect(unknown.referenceBand == nil)
        #expect(unknown.risingIsGood == nil)
        #expect(unknown.policy == nil)
    }
}
