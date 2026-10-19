//
//  HealthMetric.swift
//  HealthExportCore
//

import Foundation

/// What kind of HealthKit object a metric is, which decides how it is queried.
public enum HealthMetricKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// A number over time. Summable or averaged depending on ``HealthMetric/aggregation``.
    case quantity
    /// A coded value or an event: sleep stages, symptoms, a stand hour.
    case category
    /// Several samples read as one thing, such as a blood pressure pair.
    case correlation
    /// A recorded session.
    case workout
    /// A fact about the person that does not change day to day.
    case characteristic
}

/// How a quantity's samples combine over an interval.
public enum HealthAggregation: String, Sendable, Codable, Hashable, CaseIterable {
    /// Samples add up: steps, calories, distance, water.
    case cumulative
    /// Samples are separate readings: heart rate, weight, VO2 max.
    case discrete
    /// Not a number.
    case none
}

/// How eagerly a metric may be asked for.
public enum HealthSensitivity: String, Sendable, Codable, Hashable, CaseIterable {
    /// Included in the permission sheet shown at first launch.
    case standard
    /// Never requested at launch. A surface that genuinely needs it asks for it
    /// then, on its own, so the first permission sheet does not sweep in
    /// reproductive health the person never asked to share.
    case sensitive
}

/// Read priority. Volume and value differ enormously across the catalog, and a
/// first sync that fetches nutrition before step count feels broken.
public enum HealthTier: String, Sendable, Codable, Hashable, CaseIterable, Comparable {
    case priority
    case normal
    case slow

    private var order: Int {
        switch self {
        case .priority: 0
        case .normal: 1
        case .slow: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// One readable thing in Apple Health.
public struct HealthMetric: Sendable, Hashable, Identifiable, Codable {
    /// The HealthKit identifier, verbatim. This is the stable key: it is what
    /// the platform knows the type by, and what a stored reading refers to.
    public let identifier: String
    public let kind: HealthMetricKind
    public let unit: HealthUnit
    public let aggregation: HealthAggregation
    public let tier: HealthTier
    public let sensitivity: HealthSensitivity

    public var id: String { identifier }

    /// Whether this metric may appear in a read authorization request.
    ///
    /// Correlations may not. HealthKit refuses a read request that names one and
    /// raises `NSInvalidArgumentException`, which terminates the app: a
    /// correlation is a grouping of other samples, so the thing to ask for is the
    /// types inside it. Blood pressure is its systolic and diastolic quantities;
    /// food is the dietary ones, and this catalog already lists all of them.
    public var isReadAuthorizable: Bool { kind != .correlation }

    public init(
        identifier: String,
        kind: HealthMetricKind,
        unit: HealthUnit = .none,
        aggregation: HealthAggregation = .none,
        tier: HealthTier = .normal,
        sensitivity: HealthSensitivity = .standard
    ) {
        self.identifier = identifier
        self.kind = kind
        self.unit = unit
        self.aggregation = aggregation
        self.tier = tier
        self.sensitivity = sensitivity
    }
}
