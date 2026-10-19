//
//  ToolsSleepCycleModel.swift
//  Prism
//
//  Smart alarm sleep-cycle model. A pure, PREDICTIVE model over a single
//  night's stage segments: it reconstructs the ultradian cycle structure (the
//  roughly 90 minute NREM/REM rhythm) and predicts the wake instant that would
//  minimise sleep inertia ("grogginess"). Every method is pure math over
//  inputs the caller passes in.
//
//  This model stays pure advice, never a scheduler. It predicts an ideal wake
//  WINDOW from a recorded night. It does not schedule anything, and there is no
//  live, in-progress sleep-stage stream on iOS, so every window is predicted
//  ahead of time from a recorded night, not read live off the wrist.
//  `SmartAlarmPlanner` turns it into a scheduled instant.
//
//  Stage vocabulary matches Apple's ("awake" / "rem" / "core" / "deep").
//  "core" is light sleep. Grogginess (sleep inertia) is worst when woken from
//  "deep" and mildest when woken from "awake" / "rem", with "core" in between;
//  the wake-window search encodes exactly that ordering.
//

import Foundation

extension SomaTools {

    nonisolated enum SleepCycleModel {

        /// One contiguous stage segment of a night. `stage` is Apple's
        /// vocabulary ("awake" / "rem" / "core" / "deep"); `seconds` is its
        /// duration.
        nonisolated struct StageSpan: Sendable, Equatable {
            let stage: String
            let seconds: Double

            init(stage: String, seconds: Double) {
                self.stage = stage
                self.seconds = seconds
            }

            init(stage: Stage, seconds: Double) {
                self.init(stage: stage.rawValue, seconds: seconds)
            }
        }

        /// Typed stage names, raw values in Apple's vocabulary.
        nonisolated enum Stage: String, Sendable, Equatable, CaseIterable {
            case awake, rem, core, deep
        }

        // MARK: Tunables

        /// Anchor length of one ultradian sleep cycle (90 min). Cycle cuts are
        /// snapped to the surfacing nearest this distance from the previous cut.
        static let anchorCycleSeconds: Double = 90 * 60

        /// A cut must lie at least this far from the previous one, so a brief
        /// mid-cycle surfacing (a micro-arousal) never splits a cycle in two.
        static let minCycleSeconds: Double = 60 * 60

        /// A cut must lie no farther than this from the previous one.
        static let maxCycleSeconds: Double = 120 * 60

        /// Half-width of the small window returned around the chosen wake
        /// instant (2.5 min each side, a 5-min window), clamped to the flex.
        static let wakeWindowHalfSeconds: Double = 150

        // MARK: Cycles

        /// Cycle boundaries as seconds-from-onset ranges, contiguous and
        /// covering the whole night (`[0 ... total]` when no cut is found).
        ///
        /// A cut is placed at a light/awake TROUGH, a surfacing to "core" or
        /// "awake" out of "deep" or "rem". Among the troughs, the one nearest
        /// `anchorCycleSeconds` past the previous cut (and inside
        /// `[minCycleSeconds, maxCycleSeconds]`) is chosen. Returns `[]` for an
        /// empty or zero-length night.
        static func cycles(from spans: [StageSpan]) -> [ClosedRange<Double>] {
            let (bounds, total) = segments(spans)
            guard total > 0 else { return [] }
            let troughs = troughTimes(bounds)

            var ranges: [ClosedRange<Double>] = []
            var lastCut = 0.0
            while true {
                let target = lastCut + anchorCycleSeconds
                let lo = lastCut + minCycleSeconds
                let hi = lastCut + maxCycleSeconds
                let candidate = troughs
                    .filter { $0 >= lo && $0 <= hi && $0 < total }
                    .min { abs($0 - target) < abs($1 - target) }
                guard let cut = candidate else { break }
                ranges.append(lastCut...cut)
                lastCut = cut
            }
            if total > lastCut { ranges.append(lastCut...total) }
            return ranges
        }

        /// Mean cycle length over a night, or nil when the night yields no
        /// cycle. The smart alarm uses it instead of a hard-coded 90 min.
        static func meanCycleSeconds(_ spans: [StageSpan]) -> Double? {
            let found = cycles(from: spans)
            guard !found.isEmpty else { return nil }
            let total = found.reduce(0.0) { $0 + ($1.upperBound - $1.lowerBound) }
            return total / Double(found.count)
        }

        // MARK: Wake window

        /// The predicted best wake WINDOW inside `[targetWake-flex, targetWake
        /// + flex]`, or nil when no low-grogginess boundary falls in range.
        ///
        /// Candidates are the surfacings into a non-deep stage. Among those
        /// inside the flex window, the one minimising `distance-to-target + a
        /// small per-stage grogginess penalty` wins, so the result stays close
        /// to the target while gently preferring a lighter stage (awake over
        /// rem over core). `flexMinutes` is clamped to be non-negative.
        static func recommendedWakeWindow(spans: [StageSpan],
                                          onset: Date,
                                          targetWake: Date,
                                          flexMinutes: Double) -> ClosedRange<Date>? {
            let (bounds, total) = segments(spans)
            guard total > 0 else { return nil }

            let flex = max(0, flexMinutes) * 60
            let targetOffset = targetWake.timeIntervalSince(onset)
            let lowBound = targetOffset - flex
            let highBound = targetOffset + flex

            let candidates = wakeCandidates(bounds)
                .filter { $0.time >= lowBound && $0.time <= highBound }
            guard let best = candidates.min(by: {
                cost($0, targetOffset: targetOffset) < cost($1, targetOffset: targetOffset)
            }) else { return nil }

            let lo = max(best.time - wakeWindowHalfSeconds, lowBound)
            let hi = min(best.time + wakeWindowHalfSeconds, highBound)
            return onset.addingTimeInterval(lo)...onset.addingTimeInterval(hi)
        }

        /// The next surfacing into a non-deep stage strictly after `after`, as
        /// an absolute Date, or nil when the night holds none later.
        static func nextLightWindow(spans: [StageSpan],
                                    onset: Date,
                                    after: Date) -> Date? {
            let (bounds, total) = segments(spans)
            guard total > 0 else { return nil }
            let afterOffset = after.timeIntervalSince(onset)
            guard let next = wakeCandidates(bounds)
                .filter({ $0.time > afterOffset })
                .min(by: { $0.time < $1.time })
            else { return nil }
            return onset.addingTimeInterval(next.time)
        }

        // MARK: Internals

        /// Segment start times (seconds from onset) with their stage, plus the
        /// total night length. Zero and negative-length spans are dropped.
        private static func segments(
            _ spans: [StageSpan]
        ) -> (bounds: [(start: Double, stage: String)], total: Double) {
            var bounds: [(start: Double, stage: String)] = []
            var t = 0.0
            for span in spans where span.seconds > 0 {
                bounds.append((start: t, stage: span.stage))
                t += span.seconds
            }
            return (bounds, t)
        }

        /// The start of every "core" / "awake" segment that follows "deep" or
        /// "rem": the candidate cut points for `cycles`.
        private static func troughTimes(_ bounds: [(start: Double, stage: String)]) -> [Double] {
            guard bounds.count >= 2 else { return [] }
            var out: [Double] = []
            for i in 1..<bounds.count {
                let cur = bounds[i], prev = bounds[i - 1]
                if isLight(cur.stage), prev.stage == "deep" || prev.stage == "rem" {
                    out.append(cur.start)
                }
            }
            return out
        }

        /// The start of every non-deep segment (excluding the onset segment),
        /// tagged with its stage for the grogginess penalty.
        private static func wakeCandidates(
            _ bounds: [(start: Double, stage: String)]
        ) -> [(time: Double, stage: String)] {
            bounds.enumerated().compactMap { index, b in
                guard index > 0, isWakeFriendly(b.stage) else { return nil }
                return (time: b.start, stage: b.stage)
            }
        }

        private static func cost(_ c: (time: Double, stage: String), targetOffset: Double) -> Double {
            abs(c.time - targetOffset) + grogginessPenaltySeconds(for: c.stage)
        }

        /// Sleep-inertia penalty in seconds, so it trades directly against
        /// distance-to-target: "awake" is free, "rem" mild, "core" a little
        /// worse. "deep" is never a candidate; its value is a safety fallback.
        private static func grogginessPenaltySeconds(for stage: String) -> Double {
            switch stage {
            case "awake": return 0
            case "rem": return 120
            case "core": return 300
            default: return 600
            }
        }

        private static func isLight(_ stage: String) -> Bool {
            stage == "core" || stage == "awake"
        }

        private static func isWakeFriendly(_ stage: String) -> Bool {
            stage == "core" || stage == "rem" || stage == "awake"
        }
    }
}
