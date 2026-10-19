//
//  HealthReading.swift
//  HealthExportCore
//

import Foundation

/// One value read back from Apple Health, already in its metric's canonical unit.
///
/// The unit travels with the value so a reading can be stored, compared and
/// shown without asking the catalog again: and so a reading can never be
/// rendered against the wrong unit.
public struct HealthReading: Sendable, Hashable, Codable {
    /// The HealthKit identifier this reading belongs to.
    public let metric: String
    public let value: Double
    public let unit: HealthUnit
    public let start: Date
    public let end: Date
    /// What recorded it: a watch, a phone, a third-party app.
    public let source: String?
    /// The bundle identifier of the app that wrote it, when the platform says.
    public let sourceBundle: String?
    /// The hardware that measured it, by the name it reports: "Apple Watch",
    /// "Polar H10". Nil when no device was attached to the sample, which is
    /// the case for anything typed in or computed by an app.
    public let device: String?
    /// The hardware's model and maker, joined: "Watch Apple Inc.". Kept apart
    /// from ``device`` because a person can rename their watch, and a model
    /// string is what a quality rule can rely on.
    public let deviceModel: String?
    /// True when a person typed the value in rather than a sensor taking it.
    public let wasUserEntered: Bool

    public init(
        metric: String,
        value: Double,
        unit: HealthUnit,
        start: Date,
        end: Date,
        source: String? = nil,
        sourceBundle: String? = nil,
        device: String? = nil,
        deviceModel: String? = nil,
        wasUserEntered: Bool = false
    ) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.start = start
        self.end = end
        self.source = source
        self.sourceBundle = sourceBundle
        self.device = device
        self.deviceModel = deviceModel
        self.wasUserEntered = wasUserEntered
    }

    private enum CodingKeys: String, CodingKey {
        case metric, value, unit, start, end, source, sourceBundle, device, deviceModel, wasUserEntered
    }

    /// Decodes a reading, including one stored before the provenance fields
    /// existed: those come back as nil and false.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode(String.self, forKey: .metric)
        value = try container.decode(Double.self, forKey: .value)
        unit = try container.decode(HealthUnit.self, forKey: .unit)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        sourceBundle = try container.decodeIfPresent(String.self, forKey: .sourceBundle)
        device = try container.decodeIfPresent(String.self, forKey: .device)
        deviceModel = try container.decodeIfPresent(String.self, forKey: .deviceModel)
        wasUserEntered = try container.decodeIfPresent(Bool.self, forKey: .wasUserEntered) ?? false
    }
}

/// What the platform will let the app read.
///
/// Apple deliberately never reveals that read access was *denied*: a denial and
/// an empty store look identical, so that an app cannot infer a condition from a
/// refusal. ``undetermined`` therefore means "the sheet has not been shown", not
/// "the person said no".
public enum HealthAuthorizationStatus: String, Sendable, Hashable, Codable {
    case undetermined
    case requested
    case unavailable
}

public enum HealthReadError: Error, Sendable, Hashable {
    /// The device has no Health store: a Mac, or a locked-down configuration.
    case unavailable
    /// The running OS does not know this identifier. Expected: the catalog names
    /// metrics newer than the oldest OS the app supports.
    case unknownMetric(String)
    /// The metric exists but cannot be read the way it was asked for: a total
    /// over a discrete type, say.
    case unsupportedQuery(String)
    case underlying(String)
}

/// Where readings come from.
///
/// A protocol so the pages can be driven by a fixture in tests and in previews:
/// nothing above this line knows HealthKit exists, which is also what lets the
/// whole catalog compile and be tested on a platform that has no Health store.
public protocol HealthSampleSource: Sendable {
    /// False on a device with no Health store. Every call below throws
    /// ``HealthReadError/unavailable`` when this is false.
    var isAvailable: Bool { get }

    /// Shows the permission sheet for exactly these metrics, once.
    ///
    /// Pass ``HealthMetricCatalog/launchRequest`` at first launch, and the one
    /// sensitive metric a surface needs at the moment it opens: never the whole
    /// catalog.
    ///
    /// Calling this again with metrics the person has already answered for
    /// does nothing. An implementation is required to check before it asks,
    /// because a surface opening twice is the normal case: `.task` runs again
    /// on every tab switch, and a second sheet would put a question that has
    /// an answer back in front of someone who gave it.
    func requestAuthorization(for metrics: [HealthMetric]) async throws

    /// The most recent sample, or nil when the store holds none.
    func latest(_ metric: HealthMetric) async throws -> HealthReading?

    /// The sum over an interval. Cumulative quantities only.
    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading?

    /// The mean over an interval. Discrete quantities only.
    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading?

    /// Raw samples, newest first.
    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading]
}

public extension HealthSampleSource {
    /// The sum or the mean, whichever the metric's aggregation calls for.
    func summary(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        switch metric.aggregation {
        case .cumulative: try await total(metric, from: from, to: to)
        case .discrete: try await average(metric, from: from, to: to)
        case .none: try await latest(metric)
        }
    }
}

/// The coded values a category sample can carry, for the handful of categories
/// whose code has to be read rather than counted.
public enum HealthCategoryValue {
    /// `HKCategoryValueSleepAnalysis` cases that mean actually asleep, as
    /// opposed to in bed or awake. Time asleep is the sum of these samples'
    /// durations: the coded value itself is not a measurement.
    public static let asleep: Set<Int> = [3, 4, 5]
}

public extension HealthSampleSource {
    /// How long a category's samples ran, in seconds.
    ///
    /// Sleep and mindful sessions measure time, not a coded value: what matters
    /// is how long each sample lasted. Pass `codes` to count only some of them -
    /// ``HealthCategoryValue/asleep`` for time actually asleep.
    func totalDuration(
        _ metric: HealthMetric,
        from: Date,
        to: Date,
        codes: Set<Int>? = nil,
        limit: Int = 0
    ) async throws -> TimeInterval {
        let found = try await samples(metric, from: from, to: to, limit: limit)
        return found.reduce(0) { running, sample in
            if let codes, !codes.contains(Int(sample.value)) { return running }
            return running + sample.end.timeIntervalSince(sample.start)
        }
    }
}
