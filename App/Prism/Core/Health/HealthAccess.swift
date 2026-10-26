//
//  HealthAccess.swift
//  Prism
//

import Foundation
import HealthKit
import HealthExportCore
import HealthExportHealthKit

/// The one Apple Health permission sheet the app shows.
///
/// The owner asked for Health to ask once, not on every surface
/// (2026-10-03). Before this each page asked for its own types when it opened,
/// and the walk, the mood log, the lab and the fitness reads each asked for
/// theirs, so a person met the sheet again and again. Now the first surface
/// that needs Health asks for everything the app reads and writes in a single
/// request. HealthKit never shows the sheet again for a type that has an
/// answer, so the later calls those surfaces still make return at once.
///
/// The sensitive metrics (cycle tracking, the symptoms logged against a
/// cycle, sexual activity and the rest) are in that one sheet too, as the
/// owner ruled on 2026-10-03. Each still has its own switch there, off
/// unless the person turns it on. The cycle log writes the flow and the
/// symptoms, so their write switches are in the same sheet.
enum HealthAccess {
    /// Everything the app reads: the readable catalog, sensitive types
    /// included, plus the types the catalog source does not name.
    static func readTypes() -> Set<HKObjectType> {
        var types = Set(HealthMetricCatalog.readable.compactMap(HealthKitSampleSource.objectType))
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())
        types.insert(HKObjectType.electrocardiogramType())
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKObjectType.stateOfMindType())
        return types
    }

    /// Everything the app writes, taken from the walk, the journal, the mood
    /// log, the lab and the mouth and teeth page. Empty when this build carries no write usage string:
    /// asking to write without one raises an exception the app cannot survive.
    static func shareTypes() -> Set<HKSampleType> {
        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil else { return [] }
        let quantities: [HKQuantityTypeIdentifier] = [
            .bodyMass, .height, .waistCircumference, .leanBodyMass, .bodyFatPercentage,
            .bloodGlucose, .bloodPressureSystolic, .bloodPressureDiastolic,
            .dietaryWater, .dietaryCaffeine, .dietaryEnergyConsumed,
            .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
            // The cardio fitness test's estimate, written only when the
            // person taps Save to Health on its result.
            .vo2Max,
        ]
        var types = Set<HKSampleType>(quantities.map { HKQuantityType($0) })
        types.insert(HKObjectType.workoutType())
        types.insert(HKCategoryType(.mindfulSession))
        types.insert(HKObjectType.stateOfMindType())
        // A brushing logged by hand on the mouth and teeth page.
        types.insert(HKCategoryType(.toothbrushingEvent))
        // The cycle log: the flow and the symptoms, switches off until the
        // person turns them on.
        types.formUnion(cycleShareTypes())
        return types
    }

    /// The flow and the symptoms of the cycle log.
    private static func cycleShareTypes() -> Set<HKSampleType> {
        let written = [HomeMetric.menstrualFlow] + CycleSymptom.allCases.map(\.identifier)
        return Set(written.compactMap { id -> HKSampleType? in
            HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: id))
        })
    }

    /// Shows the one sheet. Returns once the person has answered it.
    ///
    /// The phone's Motion & Fitness question comes right after it, in the same
    /// moment: steps and movement counted by the iPhone itself, for the days
    /// the watch is off. Core Motion has no request call; the question appears
    /// on the first read of the step counter, which `PhoneMotion` makes here
    /// and nowhere else. A person meets both questions once, together.
    static func requestEverything(
        store: HKHealthStore = HKHealthStore(),
        motion: PhoneMotion? = nil
    ) async throws {
        if HKHealthStore.isHealthDataAvailable() {
            try await store.requestAuthorization(toShare: shareTypes(), read: readTypes())
        }
        await motion?.requestAccess()
    }

    /// The Medications list, the one Health type that is not in the sheet
    /// above: HealthKit authorises medications one by one, in a sheet of its
    /// own where the person picks which of them Soma may read (per object,
    /// like vision prescriptions), so it cannot ride the launch sheet. Asked from
    /// the dose page when the person taps to show their medications, never
    /// at launch. Read only: Soma writes nothing to the list.
    static func requestMedications(store: HKHealthStore = HKHealthStore()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
    }
}
