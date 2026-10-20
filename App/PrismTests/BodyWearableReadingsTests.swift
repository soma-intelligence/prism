//
//  BodyWearableReadingsTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
import HealthExportCore
@testable import Prism

@Suite("Body lens wearable readings")
struct BodyWearableReadingsTests {
    @Test("Every reading the Body lens shows resolves in the catalog, and each section is listed once")
    func everyReadingResolves() {
        let shown = BodyBiomarkerSpec.tiles + BodyBiomarkerSpec.movement + BodyBiomarkerSpec.walking + BodyBiomarkerSpec.rows
        #expect(Set(shown) == Set(BodyBiomarkerSpec.allCases))
        #expect(shown.count == BodyBiomarkerSpec.allCases.count)
        for spec in BodyBiomarkerSpec.allCases {
            #expect(HealthMetricCatalog.metric(for: spec.identifier) != nil, "\(spec)")
            #expect(spec.hue != .other, "\(spec) has no hue")
        }
    }

    @Test("The walking and movement readings carry a policy from the one table")
    func policies() {
        for spec in BodyBiomarkerSpec.movement + BodyBiomarkerSpec.walking + [.walkingHeartRateAverage] {
            #expect(MetricProfile.of(spec.identifier).policy != nil, "\(spec)")
        }
        #expect(BodyBiomarkerSpec.walkingHeartRateAverage.policy.preference == .lower)
        #expect(BodyBiomarkerSpec.appleWalkingSteadiness.policy.preference == .higher)
    }

    @Test("Today reads only the readings the engine ranks")
    func todayReadsInterpreted() {
        #expect(BodyBiomarkerSpec.interpreted.allSatisfy { $0.insight != nil })
        #expect(!BodyBiomarkerSpec.interpreted.contains(.appleWalkingSteadiness))
        #expect(BodyBiomarkerSpec.interpreted.count == InsightMetric.allCases.count - 1)
    }

    @Test("Units read the way the tiles show them")
    func display() {
        #expect(BodyBiomarkerSpec.walkingStepLength.display(0.74) == 74)
        #expect(BodyBiomarkerSpec.appleWalkingSteadiness.display(0.94) == 94)
        #expect(BodyBiomarkerSpec.appleExerciseTime.sumsPerDay)
        #expect(BodyBiomarkerSpec.activeEnergyBurned.sumsPerDay)
        #expect(!BodyBiomarkerSpec.walkingHeartRateAverage.sumsPerDay)
    }

    @Test("A walking reading with a month of values gets a line and a word")
    func walkingMarker() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let readings = (0..<40).map { day -> HealthReading in
            let at = now.addingTimeInterval(-Double(day) * 86_400)
            return HealthReading(metric: BodyBiomarkerSpec.walkingStepLength.identifier, value: 0.74, unit: .meter, start: at, end: at)
        }
        let marker = BodyBiomarkers.make(.walkingStepLength, readings: readings, now: now, calendar: calendar)
        #expect(marker.value == "74")
        #expect(marker.days.compactMap { $0 }.count == BodyBiomarkers.days)
        #expect(marker.status == .stabilizing)
    }
}

@Suite("Nothing waits on a visit")
struct NoVisitTests {
    @Test("No source file under Prism advertises or waits on a Soma visit")
    func noVisitCopy() throws {
        let root = StyleGuardTests.root.appendingPathComponent("Prism")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for phrase in ["Soma visit", "Book a visit", "Visit results", "Soma studio"] {
                #expect(!text.contains(phrase), "\(StyleGuardTests.relative(file)) says \(phrase)")
            }
        }
    }
}
