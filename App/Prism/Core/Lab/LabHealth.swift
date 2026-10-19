//
//  LabHealth.swift
//  Prism
//
//  The Body lab's side of Apple Health: the identifiers it reads, the reads
//  themselves, the one characteristic the sample source does not carry
//  (biological sex), and the writes a logged weight, blood pressure, lean
//  mass, glucose or waist makes.
//
//  Writes go through HealthKit's own save, only for types Health lets an app
//  write, and only when this build declares why it writes. A build without
//  that declaration would be terminated by HealthKit on the request, so it
//  keeps the entry in Soma and says Health was not written.
//

import Foundation
import HealthExportCore
import HealthScoring
#if canImport(HealthKit)
import HealthKit
#endif

nonisolated enum LabMetric {
    static let bodyMass = "HKQuantityTypeIdentifierBodyMass"
    static let bodyFat = "HKQuantityTypeIdentifierBodyFatPercentage"
    static let leanBodyMass = "HKQuantityTypeIdentifierLeanBodyMass"
    static let height = "HKQuantityTypeIdentifierHeight"
    static let waist = "HKQuantityTypeIdentifierWaistCircumference"
    static let systolic = "HKQuantityTypeIdentifierBloodPressureSystolic"
    static let diastolic = "HKQuantityTypeIdentifierBloodPressureDiastolic"
    static let glucose = "HKQuantityTypeIdentifierBloodGlucose"
    static let vo2Max = "HKQuantityTypeIdentifierVO2Max"
    static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    static let biologicalSex = "HKCharacteristicTypeIdentifierBiologicalSex"
}

/// One reading, reduced to what a lab page plots.
nonisolated struct LabPoint: Sendable, Equatable, Hashable {
    var date: Date
    var value: Double
}

/// A blood pressure reading: the systolic and diastolic taken together.
nonisolated struct PressureReading: Sendable, Equatable, Hashable {
    var date: Date
    var systolic: Double
    var diastolic: Double
}

nonisolated enum LabHealth {
    /// Samples of one metric over the last `days` days, oldest first.
    static func points(_ identifier: String, days: Int, now: Date, calendar: Calendar,
                       in source: any HealthSampleSource) async -> [LabPoint] {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        guard let metric = HealthMetricCatalog.metric(for: identifier),
              let readings = try? await source.samples(metric, from: start, to: now, limit: 0) else { return [] }
        return readings.map { LabPoint(date: $0.end, value: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Systolic and diastolic samples paired by the moment they were taken:
    /// Health saves a cuff reading as both at the same instant.
    static func pressures(days: Int, now: Date, calendar: Calendar, in source: any HealthSampleSource) async -> [PressureReading] {
        async let systolic = points(LabMetric.systolic, days: days, now: now, calendar: calendar, in: source)
        async let diastolic = points(LabMetric.diastolic, days: days, now: now, calendar: calendar, in: source)
        return pair(systolic: await systolic, diastolic: await diastolic)
    }

    static func pair(systolic: [LabPoint], diastolic: [LabPoint]) -> [PressureReading] {
        systolic.compactMap { high in
            guard let low = diastolic.min(by: { abs($0.date.timeIntervalSince(high.date)) < abs($1.date.timeIntervalSince(high.date)) }),
                  abs(low.date.timeIntervalSince(high.date)) < 120 else { return nil }
            return PressureReading(date: high.date, systolic: high.value, diastolic: low.value)
        }
    }

    static func age(in source: any HealthSampleSource) async -> Int? {
        guard let metric = HealthMetricCatalog.metric(for: LabMetric.dateOfBirth),
              let reading = try? await source.latest(metric) else { return nil }
        return Int(reading.value)
    }

    /// Sex as Health records it, or nil when it was never entered or shared.
    @MainActor
    static func biologicalSex() -> LabSex? {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              let sex = try? HKHealthStore().biologicalSex().biologicalSex else { return nil }
        switch sex {
        case .female: return .female
        case .male: return .male
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// Ninety days of the watch's daily series and the night each day
    /// closed with, from the same read the scores use.
    static func daily(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> LabDaily {
        let inputs = await SomaScoresReader.read(from: source, now: now, calendar: calendar)
        let result = SomaScoringEngine.compute(inputs)
        return LabDaily(
            restingHeartRate: inputs.restingHeartRate,
            heartRateVariability: inputs.heartRateVariability,
            steps: inputs.steps,
            exerciseMinutes: inputs.exerciseMinutes,
            sleepHours: result.sleepHours,
            ageYears: inputs.ageYears
        )
    }
}

/// Daily series, oldest first, the last entry today. A nil day was not measured.
nonisolated struct LabDaily: Sendable, Equatable {
    var restingHeartRate: [Double?] = []
    var heartRateVariability: [Double?] = []
    var steps: [Double?] = []
    var exerciseMinutes: [Double?] = []
    var sleepHours: [Double?] = []
    var ageYears: Double?
}

// MARK: - Writing

/// What a logged value can be written to Health as.
nonisolated enum LabHealthEntry: Sendable {
    case weight(kilograms: Double)
    case leanMass(kilograms: Double)
    case bodyFat(percent: Double)
    case pressure(systolic: Double, diastolic: Double)
    case glucose(milligramsPerDecilitre: Double)
    case waist(centimetres: Double)
}

@MainActor
enum LabHealthWriter {
    enum Outcome: Equatable {
        case saved
        /// Health is not on this device, or this build does not write.
        case notWritten
        case failed(String)
    }

    /// True when this build tells Health why it writes. Without it, asking
    /// to write raises an exception HealthKit does not let the app survive.
    static var canWrite: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
            && Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil
        #else
        false
        #endif
    }

    static func save(_ entry: LabHealthEntry, at date: Date) async -> Outcome {
        #if canImport(HealthKit)
        guard canWrite else { return .notWritten }
        let store = HKHealthStore()
        let samples = Self.samples(entry, at: date)
        let types = Set(samples.flatMap { object -> [HKSampleType] in
            if let correlation = object as? HKCorrelation { return correlation.objects.map(\.sampleType) }
            return (object as? HKSample).map { [$0.sampleType] } ?? []
        })
        do {
            try await store.requestAuthorization(toShare: types, read: [])
            try await store.save(samples)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .notWritten
        #endif
    }

    #if canImport(HealthKit)
    private static func samples(_ entry: LabHealthEntry, at date: Date) -> [HKObject] {
        func quantity(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date)
        }
        switch entry {
        case .weight(let kg):
            return [quantity(.bodyMass, .gramUnit(with: .kilo), kg)]
        case .leanMass(let kg):
            return [quantity(.leanBodyMass, .gramUnit(with: .kilo), kg)]
        case .bodyFat(let percent):
            return [quantity(.bodyFatPercentage, .percent(), percent / 100)]
        case .glucose(let mgdl):
            let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
            return [quantity(.bloodGlucose, unit, mgdl)]
        case .waist(let cm):
            return [quantity(.waistCircumference, .meterUnit(with: .centi), cm)]
        case .pressure(let high, let low):
            let objects: Set<HKSample> = [
                quantity(.bloodPressureSystolic, .millimeterOfMercury(), high),
                quantity(.bloodPressureDiastolic, .millimeterOfMercury(), low),
            ]
            return [HKCorrelation(type: HKCorrelationType(.bloodPressure), start: date, end: date, objects: objects)]
        }
    }
    #endif
}
