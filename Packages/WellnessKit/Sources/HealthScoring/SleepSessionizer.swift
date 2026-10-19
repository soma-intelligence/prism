//
//  SleepSessionizer.swift
//  HealthScoring (ported from the previous app, behaviour unchanged)
//
//  One detection path for every sleep surface. Given raw sleep-stage
//  samples it groups them into consolidated SESSIONS (a long gap splits
//  a session), then CLASSIFIES each as the main night or a nap with a
//  hybrid duration + time-of-day rule:
//
//    night = the longest-asleep session that ENDS in the wake window
//            (e.g. 2:00-11:00), restricted to the MOST RECENT night:
//            the read can span ~36h and hold two nights, so candidates
//            are limited to those within `nightRecencyHours` of the
//            latest wake-window end. This stops a longer night BEFORE
//            last night from stealing "the night" (the symptom: last
//            night shown as a nap, an older night as "Primary sleep").
//            If none ends in the window, the longest session overall,
//            but only when it clears a night floor (so a lone afternoon
//            nap on a no-night day is not mislabelled as "the night").
//    nap   = every other session with at least `minNapMinutes` asleep,
//            EXCEPT a wake-window session far from the chosen night,
//            which is a prior night the wide read caught (dropped, so it
//            neither shows as today's nap nor charges the energy ledger).
//
//  Pure on purpose: `now`, the thresholds and the calendar are passed
//  in, so there is no clock or HealthKit access and the classifier is
//  deterministic and unit-testable (see SleepSessionizerTests).
//

import Foundation

/// A flattened sleep-stage sample, HealthKit-agnostic so the classifier
/// stays pure. `inBed` wrappers are filtered out before this.
struct SleepSampleLite {
    /// "awake" / "rem" / "core" / "deep".
    let stage: String
    let start: Date
    let end: Date
    /// Recording source key (HealthKit bundle id). Per session only the
    /// source covering the most time is kept, so a second tracker writing
    /// the same night is not double-counted. Defaults to one anonymous
    /// source (single-source data is unaffected).
    var source: String = ""
    /// Friendly recorder name (HealthKit source name, e.g. "Apple Watch")
    /// carried alongside the bundle-id `source` key, for the provenance
    /// footer. Defaults to empty (single-source data is unaffected).
    var sourceName: String = ""
}

/// A gap-split sleep cluster after per-source dedup: only the dominant
/// source's samples kept, overlap-clipped into one non-overlapping
/// segment timeline. Shared by `sessions` (the 36 h night/nap
/// classifier) and the year-long daily breakdown, so EVERY surface
/// counts a two-tracker night exactly once.
struct SleepCluster {
    let start: Date
    let end: Date
    let segments: [RealSleepSegment]
    let asleepSeconds: Int
    let sourceName: String
}

enum SleepSessionizer {

    struct Thresholds {
        /// Local hours in which a session that ENDS counts as a
        /// candidate for "the night" (half-open, e.g. 2..<11).
        var wakeWindow: Range<Int> = 2..<11
        /// A gap larger than this between samples splits a session.
        var sessionGapMinutes: Int = 60
        /// A non-night session with less asleep time than this is
        /// dropped as a micro-arousal.
        var minNapMinutes: Int = 15
        /// Fallback night floor: with no session ending in the wake
        /// window, the longest session becomes the night only when its
        /// asleep time reaches this (else every session is a nap, e.g.
        /// a night-shift day with daytime sleep only).
        var minNightMinutes: Int = 90
        /// Only wake-window sessions within this many hours of the most
        /// recent wake-window end are night candidates. One sleep cycle
        /// (evening run-up to late-morning wake) spans well under this;
        /// consecutive nights' ends sit ~21h+ apart, so this cleanly
        /// keeps last night and discards the night before it.
        var nightRecencyHours: Double = 16
    }

    /// A single sleep-stage sample longer than this is not one real sleep
    /// episode: it is corrupt HealthKit data (a bad end date, a mislogged
    /// manual block). Apple Watch writes short stage samples; even a basic
    /// tracker logging a whole night as one block tops out around a dozen
    /// hours. Left in, an over-long sample dominates its source, clips into
    /// one giant segment and yields a physically impossible night (the
    /// symptom: a 31 h "time asleep" that broke the sleep score, the energy
    /// charge and the Sleep Bank). Dropped before clustering, so EVERY
    /// surface is fixed at once (the night sessionizer and the daily
    /// breakdown both read `dedupedClusters`). Well above any real night,
    /// far below the multi-day spans corrupt samples produce.
    static let maxPlausibleSampleHours: Double = 16

    /// Steps 1-2 of the pipeline, shared with the daily breakdown:
    /// gap-split `samples` into clusters, keep the dominant source per
    /// cluster and clip overlaps so each instant counts once. Pure and
    /// deterministic. `sessions` classifies the result into night/naps;
    /// `RealHealthReader.dailySleepBreakdown` attributes each cluster
    /// to its wake day.
    static func dedupedClusters(from samples: [SleepSampleLite],
                                gapMinutes: Int = Thresholds().sessionGapMinutes)
        -> [SleepCluster] {
        guard !samples.isEmpty else { return [] }

        // Reject physically impossible samples up front. A single sample
        // spanning far longer than one sleep episode is corrupt data; if it
        // reached clustering it would balloon a session into a 31 h night.
        // Dropping it here (before dominance selection and overlap clipping)
        // lets the real samples recorded alongside it form the night as
        // usual, and fixes the daily breakdown in the same stroke.
        let maxSampleSeconds = Self.maxPlausibleSampleHours * 3600
        let sane = samples.filter {
            $0.end.timeIntervalSince($0.start) <= maxSampleSeconds
        }
        guard !sane.isEmpty else { return [] }
        let sorted = sane.sorted { $0.start < $1.start }

        // 1. Sessionize: contiguous samples, split on a long gap.
        let gap = TimeInterval(gapMinutes * 60)
        var clusters: [[SleepSampleLite]] = []
        var current: [SleepSampleLite] = []
        var clusterEnd: Date?
        for sample in sorted {
            if let end = clusterEnd, sample.start.timeIntervalSince(end) > gap {
                clusters.append(current)
                current = []
                clusterEnd = nil
            }
            current.append(sample)
            clusterEnd = max(clusterEnd ?? sample.end, sample.end)
        }
        if !current.isEmpty { clusters.append(current) }

        // 2. Build a cluster (segments, span, asleep time) per group.
        return clusters.compactMap { cluster -> SleepCluster? in
            // Match Apple Health's per-source hypnogram: keep only the
            // source covering the most time in this session, so a second
            // tracker writing the same night is not stacked on top (which
            // doubled durations and scrambled the stage sequence).
            let primary = dominantSource(in: cluster)
            let chosen = cluster
                .filter { $0.source == primary }
                .sorted { $0.start < $1.start }
            guard let first = chosen.first else { return nil }

            // Clip any overlap so each instant counts once and the
            // segments form one non-overlapping timeline end to end.
            var segments: [RealSleepSegment] = []
            var lastEnd = first.start
            for sample in chosen {
                let segStart = max(sample.start, lastEnd)
                guard sample.end > segStart else { continue }   // fully covered
                let seconds = Int(sample.end.timeIntervalSince(segStart))
                guard seconds > 0 else { continue }
                segments.append(RealSleepSegment(stage: sample.stage, seconds: seconds))
                lastEnd = sample.end
            }
            let asleep = segments.reduce(0) { $0 + ($1.stage == "awake" ? 0 : $1.seconds) }
            guard asleep > 0 else { return nil }   // pure-awake cluster
            return SleepCluster(start: first.start, end: lastEnd,
                                segments: segments, asleepSeconds: asleep,
                                sourceName: chosen.first?.sourceName ?? "")
        }
    }

    /// A cluster starting within this much of the read's own window start
    /// was cut by the WINDOW, not by the sleeper. Wide enough to catch the
    /// stage sample that straddles the edge (the read returns overlapping
    /// samples, so the cluster can even start just before it), far below the
    /// gap that would have split a real session anyway.
    static let windowEdgeTolerance: TimeInterval = 15 * 60

    /// `clusters` minus the one sitting on the read's own `windowStart` edge.
    ///
    /// The same rule `sessions(from:now:windowStart:)` applies inline below: a
    /// cluster starting within `windowEdgeTolerance` of the earliest instant the
    /// read could see was cut by the WINDOW, not by the sleeper, so its start
    /// (and therefore its bed time and its asleep total) is an artefact of when
    /// the read ran. This exists because a caller that clusters through
    /// `dedupedClusters` DIRECTLY, to enumerate many nights at once
    /// (`HealthSnapshotQueries.sleepClusters`), cannot reach the rule otherwise.
    ///
    /// `sessions` keeps its own copy of these four lines rather than calling
    /// this: it is read by the night detection, the daily breakdown and the
    /// smart alarm, and an additive function cannot regress any of them while an
    /// edit to `sessions` could. Change one, change the other.
    ///
    /// A nil `windowStart` drops nothing: the caller could see everything, so no
    /// cluster is an artefact of its window. Pure + nonisolated.
    static func droppingWindowEdge(_ clusters: [SleepCluster],
                                   windowStart: Date?) -> [SleepCluster] {
        guard let windowStart, let first = clusters.first,
              first.start < windowStart.addingTimeInterval(windowEdgeTolerance)
        else { return clusters }
        return Array(clusters.dropFirst())
    }

    /// `windowStart`: the earliest instant the caller's read could see. Pass
    /// it and the first cluster is DROPPED when it sits on that edge, because
    /// its start (and therefore its bed time and its asleep total) is an
    /// artefact of when the read ran rather than a fact about the night.
    ///
    /// The symptom this kills: the read window is anchored on `now`, so on a
    /// day whose own night went unrecorded, the tail of an older night left
    /// hanging inside the window became "the night". Its bed time then moved
    /// with every relaunch (relaunch at 16:00 and the fragment starts at
    /// 04:00; relaunch at 19:00 and it starts at 07:00, or vanishes), which
    /// reads as sleep jumping around by itself. Dropping the fragment says
    /// "no night recorded", which is both stable and true.
    ///
    /// Dropped BEFORE classification on purpose: left in, a truncated
    /// fragment ending in the wake window can win "the night" outright and
    /// there is no honest night left to promote afterwards.
    static func sessions(from samples: [SleepSampleLite],
                         now: Date,
                         windowStart: Date? = nil,
                         thresholds: Thresholds = .init(),
                         calendar: Calendar = .current) -> [RealSleepSession] {
        var built = dedupedClusters(from: samples,
                                    gapMinutes: thresholds.sessionGapMinutes)
        if let windowStart, let first = built.first,
           first.start < windowStart.addingTimeInterval(windowEdgeTolerance) {
            built.removeFirst()
        }
        guard !built.isEmpty else { return [] }

        // 3. Classify the night, then everything else is a nap.
        func endsInWakeWindow(_ session: SleepCluster) -> Bool {
            thresholds.wakeWindow.contains(calendar.component(.hour, from: session.end))
        }
        let recencyWindow = thresholds.nightRecencyHours * 3600
        let windowEnders = built.enumerated().filter { endsInWakeWindow($0.element) }
        let nightIndex: Int? = {
            // Among sessions ending in the wake window, keep only the
            // most recent night's worth (within `recencyWindow` of the
            // latest such end) so a longer PRIOR night the wide read
            // caught cannot outrank last night, then take the longest.
            if let latest = windowEnders.map({ $0.element.end }).max() {
                let recent = windowEnders.filter {
                    latest.timeIntervalSince($0.element.end) <= recencyWindow
                }
                if let best = recent.max(by: {
                    $0.element.asleepSeconds < $1.element.asleepSeconds
                }) {
                    return best.offset
                }
            }
            if let longest = built.enumerated().max(by: {
                $0.element.asleepSeconds < $1.element.asleepSeconds
            }), longest.element.asleepSeconds >= thresholds.minNightMinutes * 60 {
                return longest.offset
            }
            return nil
        }()

        let minNapSeconds = thresholds.minNapMinutes * 60
        var result: [RealSleepSession] = []
        for (index, session) in built.enumerated() {
            let isNight = index == nightIndex
            if !isNight {
                if session.asleepSeconds < minNapSeconds { continue }
                // A wake-window session far from the chosen night is a
                // PRIOR night (only the wide read's span reached it), not
                // today's nap. Drop it: a daytime nap never ends in the
                // wake window, so genuine naps are untouched.
                if let nightIdx = nightIndex, endsInWakeWindow(session),
                   built[nightIdx].end.timeIntervalSince(session.end) > recencyWindow {
                    continue
                }
            }
            let kind: RealSleepKind = isNight ? .night : .nap
            result.append(RealSleepSession(
                id: "auto-\(kind.rawValue)-\(Int(session.start.timeIntervalSince1970))",
                kind: kind,
                source: .healthKit,
                start: session.start,
                end: session.end,
                segments: session.segments,
                sourceName: session.sourceName.isEmpty ? nil : session.sourceName))
        }
        return result.sorted { $0.start < $1.start }
    }

    /// The source covering the most time in a session. Apple Health
    /// shows one source's timeline, not the union of every tracker, so
    /// this picks the dominant one (the primary device that recorded the
    /// whole night). Ties break lexically so the result is deterministic.
    private static func dominantSource(in cluster: [SleepSampleLite]) -> String {
        var coverage: [String: TimeInterval] = [:]
        for sample in cluster {
            coverage[sample.source, default: 0] += sample.end.timeIntervalSince(sample.start)
        }
        return coverage
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .first?.key ?? ""
    }
}
