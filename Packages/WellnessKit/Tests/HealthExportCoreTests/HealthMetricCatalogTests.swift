//
//  HealthMetricCatalogTests.swift
//  HealthExportCoreTests
//

import Foundation
import Testing
@testable import HealthExportCore

@Suite("Metric catalog")
struct HealthMetricCatalogTests {
    @Test("Every identifier appears once")
    func identifiersAreUnique() {
        let ids = HealthMetricCatalog.all.map(\.identifier)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every identifier carries the prefix its kind implies")
    func identifiersAreWellFormed() {
        for metric in HealthMetricCatalog.all {
            let expected = switch metric.kind {
            case .quantity: "HKQuantityTypeIdentifier"
            case .category: "HKCategoryTypeIdentifier"
            case .correlation: "HKCorrelationTypeIdentifier"
            case .characteristic: "HKCharacteristicTypeIdentifier"
            case .workout: "HKWorkoutTypeIdentifier"
            }
            #expect(metric.identifier.hasPrefix(expected), "\(metric.identifier)")
            // The workout type's identifier is exactly its prefix; every other
            // kind names something after it.
            if metric.kind != .workout {
                #expect(metric.identifier.count > expected.count, "\(metric.identifier) has no name")
            }
        }
    }

    @Test("Every quantity has a unit and an aggregation, and nothing else has either")
    func unitsMatchKinds() {
        for metric in HealthMetricCatalog.quantities {
            #expect(metric.unit != .none, "\(metric.identifier) has no unit")
            #expect(metric.aggregation != .none, "\(metric.identifier) has no aggregation")
        }
        let nonQuantities = HealthMetricCatalog.all.filter { $0.kind != .quantity }
        #expect(nonQuantities.allSatisfy { $0.unit == .none })
        #expect(nonQuantities.allSatisfy { $0.aggregation == .none })
    }

    @Test("The launch permission sheet never names a sensitive metric")
    func launchRequestExcludesSensitive() {
        #expect(HealthMetricCatalog.launchRequest.allSatisfy { $0.sensitivity == .standard })
        #expect(!HealthMetricCatalog.onDemand.isEmpty)
        // The two halves partition what can be requested, which is `readable`
        // rather than `all`: the correlations sit outside both by design.
        #expect(
            HealthMetricCatalog.launchRequest.count + HealthMetricCatalog.onDemand.count
                == HealthMetricCatalog.readable.count
        )
    }

    @Test("Cycle tracking is only ever asked for on demand")
    func reproductiveHealthIsOnDemand() {
        let onDemand = Set(HealthMetricCatalog.onDemand.map(\.identifier))
        for name in ["HKCategoryTypeIdentifierMenstrualFlow",
                     "HKCategoryTypeIdentifierOvulationTestResult",
                     "HKCategoryTypeIdentifierCervicalMucusQuality",
                     "HKCategoryTypeIdentifierSexualActivity",
                     "HKCategoryTypeIdentifierPregnancy",
                     "HKQuantityTypeIdentifierBasalBodyTemperature"] {
            #expect(onDemand.contains(name), "\(name) would be requested at launch")
        }
    }

    @Test("The symptoms a cycle log writes are asked for on demand, never at launch")
    func cycleSymptomsAreOnDemand() {
        let onDemand = Set(HealthMetricCatalog.onDemand.map(\.identifier))
        for name in ["AbdominalCramps", "HotFlashes", "NightSweats", "SleepChanges",
                     "MoodChanges", "Headache", "Bloating"] {
            #expect(onDemand.contains("HKCategoryTypeIdentifier" + name), "\(name) would be requested at launch")
        }
    }

    @Test("Reproductive health types of iOS 18 and 27 are in the catalog, on demand")
    func newerReproductiveTypesAreCatalogued() {
        for name in ["BleedingAfterMenopause", "BleedingAfterPregnancy", "BleedingDuringPregnancy", "MenopausalState"] {
            let metric = HealthMetricCatalog.metric(for: "HKCategoryTypeIdentifier" + name)
            #expect(metric?.kind == .category, "\(name) is missing")
            #expect(metric?.sensitivity == .sensitive, "\(name) would be requested at launch")
        }
    }

    @Test("A correlation is never offered to a read request")
    func correlationsAreNotReadAuthorizable() {
        // Asking HealthKit to read a correlation raises NSInvalidArgumentException
        // and terminates the app, so no set meant for a request may contain one.
        #expect(HealthMetricCatalog.correlations.allSatisfy { !$0.isReadAuthorizable })
        #expect(HealthMetricCatalog.readable.allSatisfy { $0.kind != .correlation })
        #expect(HealthMetricCatalog.launchRequest.allSatisfy { $0.kind != .correlation })
        #expect(HealthMetricCatalog.onDemand.allSatisfy { $0.kind != .correlation })
        #expect(
            HealthMetricCatalog.readable.count
                == HealthMetricCatalog.all.count - HealthMetricCatalog.correlations.count
        )
    }

    @Test("Lookup finds a metric by its identifier and misses cleanly")
    func lookupWorks() {
        let steps = HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierStepCount")
        #expect(steps?.unit == .count)
        #expect(steps?.aggregation == .cumulative)
        #expect(steps?.tier == .priority)
        #expect(HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierNope") == nil)
    }

    @Test("A few units are the ones Apple actually stores the metric in")
    func spotCheckUnits() {
        func unit(_ id: String) -> HealthUnit? {
            HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifier" + id)?.unit
        }
        #expect(unit("HeartRate") == .countPerMinute)
        #expect(unit("HeartRateVariabilitySDNN") == .millisecond)
        #expect(unit("VO2Max") == .millilitrePerKilogramMinute)
        #expect(unit("BodyMass") == .kilogram)
        #expect(unit("OxygenSaturation") == .percent)
        #expect(unit("DietaryWater") == .litre)
        #expect(unit("DietaryCaffeine") == .milligram)
        #expect(unit("DietaryVitaminB12") == .microgram)
        #expect(unit("BloodGlucose") == .milligramPerDecilitre)
    }

    @Test("Apple's acronym spellings survive the identifier rule")
    func acronymIdentifiersAreExact() {
        // Capitalising the first letter of `vo2Max` gives `Vo2Max`, which
        // HealthKit does not know: the type would resolve to nil at runtime and
        // the metric would silently never appear.
        let ids = Set(HealthMetricCatalog.all.map(\.identifier))
        #expect(ids.contains("HKQuantityTypeIdentifierVO2Max"))
        #expect(ids.contains("HKQuantityTypeIdentifierUVExposure"))
        #expect(!ids.contains("HKQuantityTypeIdentifierVo2Max"))
        #expect(!ids.contains("HKQuantityTypeIdentifierUvExposure"))
    }

    @Test("Activity and heart rate are read before nutrition")
    func tiersAreOrdered() {
        #expect(HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierStepCount")?.tier == .priority)
        #expect(HealthMetricCatalog.metric(for: "HKQuantityTypeIdentifierDietaryZinc")?.tier == .slow)
        #expect(HealthTier.priority < HealthTier.normal)
        #expect(HealthTier.normal < HealthTier.slow)
    }

    @Test("The catalog covers the whole of Apple Health, not a sample of it")
    func catalogIsComplete() {
        #expect(HealthMetricCatalog.quantities.count > 110)
        #expect(HealthMetricCatalog.categories.count > 60)
        #expect(HealthMetricCatalog.characteristics.count == 6)
        #expect(HealthMetricCatalog.correlations.count == 2)
        #expect(HealthMetricCatalog.all.count > 185)
    }
}
