//
//  HealthAccessTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthKit
import HealthExportCore
import HealthExportHealthKit
@testable import Prism

/// Apple Health asks once (the owner's ruling of 2026-10-03): the first
/// surface that needs Health asks for every type the app reads and writes in
/// one sheet. A surface that reads a type outside that sheet would bring the
/// sheet back the day it opens, so every surface's reads are held to it here.
@Suite("Health asks once")
@MainActor
struct HealthAccessTests {
    /// What each surface reads, by the list it hands to `HealthDashboard.prepare`.
    var surfaces: [(String, [String])] {
        [
            ("Score pages", ScoreDetailInputs.metrics(for: Set(ScoreDetailInputs.Part.allCases))),
            ("Tools", ToolsInputs.metrics),
            ("Environment", EnvironmentInputs.metrics),
            ("Mind", MindJourneyLoad.Metric.all),
            ("Trends", PulseTrendsInputs.metrics),
            ("Trends links", PulseLinksInputs.metrics),
            ("Today's night", [HomeMetric.respiratoryRate, HomeMetric.wristTemperature]),
            ("Fitness", FitnessHistory.metrics + [FitnessHistory.Metric.steps, FitnessHistory.Metric.activeEnergy]),
            ("Body lab", LabReads.bioAgeMetrics + [LabMetric.leanBodyMass, LabMetric.waist, LabMetric.glucose]),
            ("Medical card", HomeClinical.characteristics),
        ]
    }

    @Test("Every type a surface reads is in the one sheet")
    func everyReadIsInTheSheet() {
        let sheet = HealthAccess.readTypes()
        for (surface, identifiers) in surfaces {
            for identifier in identifiers {
                let metric = HealthMetricCatalog.metric(for: identifier)
                let type = metric.flatMap(HealthKitSampleSource.objectType)
                #expect(type.map { sheet.contains($0) } == true, "\(surface) reads \(identifier) outside the sheet")
            }
        }
    }

    @Test("Every readable type in the catalog resolves to a HealthKit type, so none drops out of the sheet unseen")
    func catalogResolves() {
        let unresolved = HealthMetricCatalog.readable.filter { HealthKitSampleSource.objectType($0) == nil }
        #expect(unresolved.isEmpty, "\(unresolved.map(\.identifier))")
    }

    @Test("The sheet names the types the catalog does not: workout routes, ECG, activity rings and state of mind")
    func typesBeyondTheCatalog() {
        let sheet = HealthAccess.readTypes()
        #expect(sheet.contains(HKObjectType.workoutType()))
        #expect(sheet.contains(HKSeriesType.workoutRoute()))
        #expect(sheet.contains(HKObjectType.electrocardiogramType()))
        #expect(sheet.contains(HKObjectType.activitySummaryType()))
        #expect(sheet.contains(HKObjectType.stateOfMindType()))
    }

    @Test("Whatever the app writes it can read back from the same sheet")
    func writesAreRead() {
        let sheet = HealthAccess.readTypes()
        for type in HealthAccess.shareTypes() {
            #expect(sheet.contains(type), "\(type.identifier) is written but never read")
        }
    }
}
