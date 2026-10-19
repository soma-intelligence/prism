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
/// The sensitive metrics (cycle tracking, sexual activity and the rest) are in
/// that one sheet too. Each still has its own switch there, off unless the
/// person turns it on.
enum HealthAccess {
    /// Everything the app reads: the readable catalog plus the types the
    /// catalog source does not name.
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
    /// log and the lab. Empty when this build carries no write usage string:
    /// asking to write without one raises an exception the app cannot survive.
    static func shareTypes() -> Set<HKSampleType> {
        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil else { return [] }
        let quantities: [HKQuantityTypeIdentifier] = [
            .bodyMass, .height, .waistCircumference, .leanBodyMass, .bodyFatPercentage,
            .bloodGlucose, .bloodPressureSystolic, .bloodPressureDiastolic,
            .dietaryWater, .dietaryCaffeine, .dietaryEnergyConsumed,
            .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
        ]
        var types = Set<HKSampleType>(quantities.map { HKQuantityType($0) })
        types.insert(HKObjectType.workoutType())
        types.insert(HKCategoryType(.mindfulSession))
        types.insert(HKObjectType.stateOfMindType())
        return types
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
}
