//
//  PhoneMotionModels.swift
//  Prism
//

import Foundation

/// Where the phone's Motion & Fitness permission stands.
///
/// `unavailable` is a device with no step counter: a Mac, a headset, an old
/// iPad. It is kept apart from `denied` because the page says different
/// things: one is a choice the person made, the other is the hardware.
nonisolated enum MotionAuthorization: String, Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case unavailable

    /// One short line for the Health access page.
    var summary: String {
        switch self {
        case .authorized: "Steps and movement are read from this iPhone."
        case .notDetermined: "Not asked yet. The question comes with Apple Health's."
        case .denied: "Turned off. Settings, Privacy, Motion & Fitness turns it back on."
        case .restricted: "Restricted on this device."
        case .unavailable: "This device does not count steps."
        }
    }
}

/// What the phone counted over one stretch of time, most often a day.
///
/// The optionals are honest: a phone without a barometer has no floors, and a
/// query over the past carries no cadence. Nil renders as a dash.
nonisolated struct PedometerDay: Sendable, Equatable {
    var start: Date
    var end: Date
    var steps: Double
    /// Metres, estimated by the phone from the steps and the person's stride.
    var distance: Double?
    var floorsAscended: Double?
    var floorsDescended: Double?
    /// Steps a second. Only live updates carry it.
    var cadence: Double?
    /// Seconds a metre while moving.
    var pace: Double?
}

/// The one thing the phone thinks the person is doing.
///
/// Core Motion can raise two flags at once (automotive and stationary is a car
/// at a red light), so a sample is read as its most specific flag.
nonisolated enum MotionActivityKind: String, Sendable, Equatable, CaseIterable {
    case stationary
    case walking
    case running
    case cycling
    case automotive

    /// A short name for a timeline row.
    var label: String {
        switch self {
        case .stationary: "Still"
        case .walking: "Walk"
        case .running: "Run"
        case .cycling: "Ride"
        case .automotive: "Drive"
        }
    }

    /// True for the kinds the body itself does.
    var isOnFoot: Bool { self == .walking || self == .running }

    /// Picks the most specific flag, or nil when none is raised.
    static func from(
        stationary: Bool, walking: Bool, running: Bool, cycling: Bool, automotive: Bool
    ) -> MotionActivityKind? {
        if automotive { return .automotive }
        if cycling { return .cycling }
        if running { return .running }
        if walking { return .walking }
        if stationary { return .stationary }
        return nil
    }
}

nonisolated enum MotionConfidence: Int, Sendable, Equatable, Comparable {
    case low
    case medium
    case high

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One change of activity as Core Motion reports it: from `start` on, the
/// person is doing `kind`, until the next sample says otherwise. A nil kind is
/// Core Motion's "unknown".
nonisolated struct MotionActivitySample: Sendable, Equatable {
    var start: Date
    var kind: MotionActivityKind?
    var confidence: MotionConfidence
}

/// A stretch of one activity with a start and an end: what a timeline draws.
nonisolated struct MotionSegment: Sendable, Equatable, Identifiable {
    var kind: MotionActivityKind
    var start: Date
    var end: Date
    /// The highest confidence Core Motion gave any sample inside it.
    var confidence: MotionConfidence

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Turns Core Motion's stream of changes into segments a timeline can draw.
///
/// The rules, in order:
/// 1. Each sample lasts until the next one starts; the last lasts until `end`.
/// 2. A sample that is unknown, or under the confidence floor, says nothing
///    new: whatever was going on continues through it. Before the first sure
///    sample there is nothing to continue, so that time is left out.
/// 3. Neighbours of the same kind join.
/// 4. A segment shorter than `minimumDuration` is a blip (a stop at a
///    crossing, a jolt read as a run) and is dropped; if the same kind sits on
///    both sides of it, the two join across the gap. A blip between two
///    different kinds leaves a gap rather than inventing what filled it.
nonisolated enum MotionSegmenter {
    static func segments(
        from samples: [MotionActivitySample],
        until end: Date,
        minimumDuration: TimeInterval = 120,
        minimumConfidence: MotionConfidence = .medium
    ) -> [MotionSegment] {
        let ordered = samples.filter { $0.start < end }.sorted { $0.start < $1.start }

        // Rules 1 to 3: carry the last sure kind forward and join equal runs.
        var joined: [MotionSegment] = []
        for (index, sample) in ordered.enumerated() {
            let stop = index + 1 < ordered.count ? ordered[index + 1].start : end
            guard stop > sample.start else { continue }
            let isSure = sample.kind != nil && sample.confidence >= minimumConfidence
            if let kind = sample.kind, isSure {
                if var last = joined.last, last.kind == kind, last.end == sample.start {
                    last.end = stop
                    last.confidence = max(last.confidence, sample.confidence)
                    joined[joined.count - 1] = last
                } else {
                    joined.append(MotionSegment(kind: kind, start: sample.start, end: stop, confidence: sample.confidence))
                }
            } else if var last = joined.last, last.end == sample.start {
                last.end = stop
                joined[joined.count - 1] = last
            }
        }

        // Rule 4: drop the blips, then join what they split.
        var kept: [MotionSegment] = []
        for segment in joined where segment.duration >= minimumDuration {
            if var last = kept.last, last.kind == segment.kind {
                last.end = segment.end
                last.confidence = max(last.confidence, segment.confidence)
                kept[kept.count - 1] = last
            } else {
                kept.append(segment)
            }
        }
        return kept
    }
}

/// How a phone count and a Health count of the same thing become one number.
///
/// Health lags: the phone's samples reach it in batches, minutes apart, so
/// during the day the live phone count is usually ahead. Health also adds a
/// watch's steps that the phone never felt, so later it can be ahead. Neither
/// double counts the other's steps inside its own total, which makes the
/// higher of the two the better answer, and the one present when the other is
/// missing. Both missing is nil, a dash.
nonisolated enum MotionMerge {
    static func preferred(health: Double?, phone: Double?) -> Double? {
        switch (health, phone) {
        case let (health?, phone?): max(health, phone)
        case let (health?, nil): health
        case let (nil, phone?): phone
        case (nil, nil): nil
        }
    }
}
