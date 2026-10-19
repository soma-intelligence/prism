//
//  SleepSessionTypes.swift
//  HealthScoring
//
//  The consolidated sleep episode the sessionizer produces, trimmed to the
//  fields the scores read. Ported from the previous app's snapshot model; the
//  overnight vitals it also carried are not read by any score here.
//

import Foundation

/// One run of a single stage inside a session.
struct RealSleepSegment: Codable, Sendable, Equatable {
    /// "awake" / "rem" / "core" / "deep".
    let stage: String
    let seconds: Int
}

/// Whether a consolidated sleep episode is the main night or a nap.
enum RealSleepKind: String, Codable, Sendable {
    case night
    case nap
}

/// Where a session came from. Only HealthKit detection exists in Soma today.
enum RealSleepSource: String, Codable, Sendable {
    case healthKit
    case manual
}

/// One consolidated sleep episode, night or nap.
struct RealSleepSession: Codable, Identifiable, Sendable {
    var id: String
    var kind: RealSleepKind
    var source: RealSleepSource
    var start: Date
    var end: Date
    /// Ordered stage segments.
    var segments: [RealSleepSegment]
    /// Friendly name of the dominant recorder for this session.
    var sourceName: String? = nil

    /// Seconds spent in any asleep stage (everything but "awake").
    var asleepSeconds: Int {
        segments.reduce(0) { $0 + ($1.stage == "awake" ? 0 : $1.seconds) }
    }
}
