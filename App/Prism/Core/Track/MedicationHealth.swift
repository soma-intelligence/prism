//
//  MedicationHealth.swift
//  Prism
//
//  The medications a person keeps in Apple Health's Medications list, read
//  through the Medications API, and the one list they make with the
//  supplements on the Track plan. Read only: Soma never adds to that list,
//  and a medication's schedule and reminders stay Health's own.
//

import Foundation
import HealthKit

/// A medication from Apple Health's list, reduced to what Soma shows.
nonisolated struct HealthMedication: Identifiable, Equatable, Sendable {
    let id: String
    /// The person's nickname for it when they gave one, else Health's name.
    let name: String
    /// Moved out of the active list in Health: one the person stopped.
    let isArchived: Bool
    /// Health keeps a schedule and reminders for it.
    let hasSchedule: Bool
    /// A dose logged as taken in Health today.
    var takenToday = false
}

/// One line of the merged list: a supplement on the plan, a medication in
/// Health, or both under one name.
nonisolated struct MedicationEntry: Identifiable, Equatable, Sendable {
    var id: String { MedicationList.key(name) }
    let name: String
    let supplementID: UUID?
    let healthID: String?
    var takenToday = false
}

nonisolated enum MedicationList {
    /// The plan's active supplements and Health's active medications as one
    /// list, by name. The same name in both (any case, any accent) is one
    /// entry, named as on the plan. Archived medications stay out.
    static func merged(supplements: [TrackSupplement], health: [HealthMedication]) -> [MedicationEntry] {
        var byKey: [String: MedicationEntry] = [:]
        for supplement in supplements where supplement.isActive {
            byKey[key(supplement.name)] = MedicationEntry(name: supplement.name, supplementID: supplement.id, healthID: nil)
        }
        for medication in health where !medication.isArchived {
            let k = key(medication.name)
            if let entry = byKey[k] {
                byKey[k] = MedicationEntry(name: entry.name, supplementID: entry.supplementID, healthID: medication.id,
                                           takenToday: entry.takenToday || medication.takenToday)
            } else {
                byKey[k] = MedicationEntry(name: medication.name, supplementID: nil, healthID: medication.id,
                                           takenToday: medication.takenToday)
            }
        }
        return byKey.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name two lists are matched on.
    static func key(_ name: String) -> String { MedicationInteractions.fold(name) }
}

/// The read of Apple Health's Medications list.
///
/// Medications are authorised one by one: the person picks, in Health's own
/// sheet, which of them Soma may see (``HealthAccess/requestMedications(store:)``).
/// That sheet is asked for from the dose page, on a tap, never at launch.
/// Every read returns empty when Health holds nothing or was not allowed,
/// which is also what the Simulator returns.
enum MedicationHealth {
    /// The medications the person shared, archived ones included, with
    /// whether a dose of each was logged as taken today.
    static func medications(store: HKHealthStore = HKHealthStore(), now: Date = .now,
                            calendar: Calendar = .current) async -> [HealthMedication] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let annotated = (try? await HKUserAnnotatedMedicationQueryDescriptor().result(for: store)) ?? []
        guard !annotated.isEmpty else { return [] }
        let taken = await takenToday(store: store, now: now, calendar: calendar)
        return annotated.map { item in
            HealthMedication(
                id: String(describing: item.medication.identifier),
                name: item.nickname ?? item.medication.displayText,
                isArchived: item.isArchived,
                hasSchedule: item.hasSchedule,
                takenToday: taken.contains(item.medication.identifier)
            )
        }
    }

    /// The medication concepts with a dose logged as taken since midnight.
    private static func takenToday(store: HKHealthStore, now: Date, calendar: Calendar) async -> Set<HKHealthConceptIdentifier> {
        let start = calendar.startOfDay(for: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: .medicationDoseEventType(),
                                 predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: []
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return Set(samples.compactMap { sample in
            guard let event = sample as? HKMedicationDoseEvent, event.logStatus == .taken else { return nil }
            return event.medicationConceptIdentifier
        })
    }
}
