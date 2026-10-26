//
//  InsightEngine.swift
//  Prism
//
//  Reads one metric's days and says what they mean: the person's usual,
//  where now sits against it, which way the month went, a cue of a few words
//  and how much it moved, for ranking. Pure arithmetic over a series, so it
//  is tested without a Health store.
//

import Foundation

/// What one metric's days mean today.
struct Insight: Equatable, Sendable, Codable {
    enum Position: Sendable, Equatable, Codable { case within, above, below }
    enum Direction: Sendable, Equatable, Codable { case rising, falling, steady }
    /// How the cue reads: good news, something to watch, or neither.
    enum Tone: Sendable, Equatable, Codable { case good, watch, neutral }
    /// What the cue names, so a surface can drop one it already says.
    enum CueKind: Sendable, Equatable, Codable {
        /// "Highest in 30 days".
        case extreme
        /// "3 days rising".
        case run
        /// "12% under usual".
        case offUsual
        /// "Back in range".
        case backInRange
        /// "Rising over 30 days".
        case trend
        /// "Usual range after 12 days".
        case learning
    }

    /// The median of the days before the last week.
    var usual: Double?
    /// The usual, give or take its spread: the band a reading sits within.
    var band: ClosedRange<Double>?
    /// The last three days' mean, or the latest reading of the week.
    var current: Double?
    /// Days between today and the newest reading behind ``current``.
    var currentAge: Int?
    var position: Position?
    /// How far ``current`` sits from the usual, in percent of it, signed.
    var percent: Double?
    var direction: Direction?
    /// The fitted change over the last thirty days, in the metric's unit.
    var change: Double?
    var preference: InsightPreference
    /// A short label, never a sentence. Nil when there is nothing to say:
    /// within the usual and steady.
    var cue: String?
    var cueKind: CueKind?
    var tone: Tone
    /// How much this moved, 0 to 1. What ranks Today's "What moved".
    var severity: Double

    /// Whether more is better for this metric, nil when neither is.
    var higherIsBetter: Bool? {
        switch preference {
        case .higher: true
        case .lower: false
        case .steady: nil
        }
    }

    /// The cue, or where it sits when there is no cue: what a row too small
    /// for a status word shows.
    var label: String? {
        if let cue { return cue }
        return position == .within ? "In your range" : nil
    }

    static func empty(_ preference: InsightPreference) -> Insight {
        Insight(preference: preference, tone: .neutral, severity: 0)
    }
}

enum InsightEngine {
    /// The days at the end that are "now", left out of the usual.
    static let recentDays = 7
    /// How far back the usual reaches before the last week.
    static let usualDays = 60
    /// Readings the usual needs before it means anything.
    static let usualMinimum = 5

    /// What a reading says while its usual is still being learned: the days
    /// it takes, the last week plus the readings the usual is drawn from.
    static var learningCue: String { "Usual range after \(recentDays + usualMinimum) days" }
    /// The window the direction is read over.
    static let trendDays = 30
    /// Spread from the median absolute deviation as a standard deviation.
    static let madScale = 1.4826

    /// Interprets `days` for `metric`.
    static func interpret(_ metric: InsightMetric, days: [Double?]) -> Insight {
        interpret(days, policy: metric.policy, percentCue: metric != .wristTemperature)
    }

    /// Interprets one value per day, oldest first, the last one today, nil on
    /// a day with no reading. Values are in the unit the metric is shown in.
    ///
    /// - Parameter percentCue: whether the cue may say how far off in
    ///   percent; false where a percent of the value means nothing (a
    ///   temperature).
    static func interpret(_ days: [Double?], policy: InsightPolicy, percentCue: Bool = true) -> Insight {
        // A NaN or an infinity is a missing day: one would poison the median
        // and the band built on it.
        let finite = days.map { $0.flatMap { $0.isFinite ? $0 : nil } }
        let series = policy.partialToday ? Array(finite.dropLast()) : finite
        let count = series.count
        var insight = Insight.empty(policy.preference)
        guard count > 0 else { return insight }

        // The usual: the days before the last week.
        let usualEnd = max(0, count - recentDays)
        let usualStart = max(0, usualEnd - usualDays)
        let earlier = series[usualStart..<usualEnd].compactMap { $0 }
        var half: Double?
        if earlier.count >= usualMinimum, let median = median(earlier) {
            let deviation = Self.median(earlier.map { abs($0 - median) }) ?? 0
            let spread = max(deviation * madScale, policy.minimumSpread, policy.minimumShare * abs(median))
            insight.usual = median
            insight.band = (median - spread)...(median + spread)
            half = spread
        }

        // Now: the last three days, or the latest reading of the week.
        let lately = indexed(series).filter { $0.index >= count - 3 }
        if !lately.isEmpty {
            insight.current = lately.map(\.value).reduce(0, +) / Double(lately.count)
            insight.currentAge = count - 1 - (lately.last?.index ?? count - 1) + (policy.partialToday ? 1 : 0)
        } else if let last = indexed(series).last(where: { $0.index >= count - recentDays }) {
            insight.current = last.value
            insight.currentAge = count - 1 - last.index + (policy.partialToday ? 1 : 0)
        }

        // Where now sits.
        var distance: Double = 0
        if let usual = insight.usual, let band = insight.band, let half, let current = insight.current {
            insight.position = current > band.upperBound ? .above : current < band.lowerBound ? .below : .within
            distance = abs(current - usual) / half
            if usual != 0 { insight.percent = (current - usual) / abs(usual) * 100 }
        }

        // Which way the month went.
        let month = indexed(series).filter { $0.index >= count - trendDays }
        if month.count >= 3, let first = month.first, let last = month.last, last.index - first.index >= 2,
           let slope = theilSen(month) {
            let change = slope * Double(last.index - first.index)
            insight.change = change
            insight.direction = change >= policy.trendStep ? .rising : change <= -policy.trendStep ? .falling : .steady
        }

        let story = Story(series: series, insight: insight, policy: policy)
        let said = cue(insight, story: story, percentCue: percentCue)
        insight.cue = said?.text
        insight.cueKind = said?.kind
        insight.tone = tone(insight, story: story)
        insight.severity = severity(insight, story: story, distance: distance, policy: policy)
        return insight
    }

    // MARK: - The story behind the cue

    /// The moments a cue can name: a record, a run, a return.
    struct Story: Equatable {
        /// The newest reading is the highest (or lowest) of the month.
        var extreme: Insight.Position?
        /// Days in a row the value rose (positive) or fell (negative), ending
        /// on the newest reading.
        var run: Int = 0
        /// Within the usual now, outside it the days before.
        var backInRange = false

        init(series: [Double?], insight: Insight, policy: InsightPolicy) {
            let count = series.count
            let known = InsightEngine.indexed(series)
            guard let newest = known.last, count - 1 - newest.index <= 2 else { return }

            let month = known.filter { $0.index >= count - InsightEngine.trendDays && $0.index != newest.index }
            if month.count >= 9, insight.position == .above || insight.position == .below {
                if insight.position == .above, newest.value > (month.map(\.value).max() ?? .infinity) { extreme = .above }
                if insight.position == .below, newest.value < (month.map(\.value).min() ?? -.infinity) { extreme = .below }
            }

            // A run counts consecutive days only: a gap ends it.
            var steps = 0
            var sign = 0
            var index = newest.index
            while index > 0, let today = series[index], let before = series[index - 1] {
                let step = today > before ? 1 : today < before ? -1 : 0
                if step == 0 || (sign != 0 && step != sign) { break }
                sign = step
                steps += 1
                index -= 1
            }
            if steps >= 3, let start = series[newest.index - steps],
               abs(newest.value - start) >= policy.minimumSpread * 0.5 {
                run = steps * sign
            }

            if insight.position == .within, let band = insight.band {
                let before = known.filter { $0.index >= count - InsightEngine.recentDays && $0.index < count - 3 }
                if !before.isEmpty {
                    let mean = before.map(\.value).reduce(0, +) / Double(before.count)
                    backInRange = !band.contains(mean)
                }
            }
        }
    }

    // MARK: - Cue, tone, severity

    static func cue(_ insight: Insight, story: Story, percentCue: Bool) -> (text: String, kind: Insight.CueKind)? {
        guard insight.current != nil || insight.direction != nil else { return nil }

        guard let position = insight.position else {
            // No usual yet: the month's direction, or that it is being learned.
            switch insight.direction {
            case .rising: return ("Rising over 30 days", .trend)
            case .falling: return ("Falling over 30 days", .trend)
            default: return insight.current == nil ? nil : (learningCue, .learning)
            }
        }

        switch position {
        case .above, .below:
            if story.extreme == .above { return ("Highest in 30 days", .extreme) }
            if story.extreme == .below { return ("Lowest in 30 days", .extreme) }
            if story.run >= 3, position == .above { return ("\(story.run) days rising", .run) }
            if story.run <= -3, position == .below { return ("\(-story.run) days falling", .run) }
            let word = position == .above ? "over" : "under"
            if percentCue, let percent = insight.percent, abs(percent) >= 1 {
                return ("\(Int(abs(percent).rounded()))% \(word) usual", .offUsual)
            }
            return (position == .above ? "Over your usual" : "Under your usual", .offUsual)
        case .within:
            if story.backInRange { return ("Back in range", .backInRange) }
            switch insight.direction {
            case .rising: return ("Rising over 30 days", .trend)
            case .falling: return ("Falling over 30 days", .trend)
            default: return nil
            }
        }
    }

    static func tone(_ insight: Insight, story: Story) -> Insight.Tone {
        if story.backInRange { return .good }
        let up: Bool
        switch insight.position {
        case .above: up = true
        case .below: up = false
        case .within, nil:
            switch insight.direction {
            case .rising: up = true
            case .falling: up = false
            default: return .neutral
            }
        }
        switch insight.preference {
        case .higher: return up ? .good : .watch
        case .lower: return up ? .watch : .good
        case .steady: return insight.position == .within ? .neutral : .watch
        }
    }

    /// 0 to 1: how far from the usual, how strong the month's direction,
    /// whether the newest reading is a record or a run, then weighed by the
    /// metric and by how fresh the reading is. Good news counts a little
    /// less than news to watch.
    static func severity(_ insight: Insight, story: Story, distance: Double, policy: InsightPolicy) -> Double {
        var score: Double = 0
        if let position = insight.position {
            score = position == .within ? 0.3 * min(distance, 1) : min(1, 0.3 + 0.2 * (distance - 1))
        }
        if let change = insight.change, policy.trendStep > 0 {
            let steps = abs(change) / policy.trendStep
            if steps >= 1 { score = max(score, min(0.6, 0.25 + 0.1 * (steps - 1))) }
        }
        if story.extreme != nil || abs(story.run) >= 3 { score += 0.1 }
        if story.backInRange { score = max(score, 0.35) }

        let freshness: Double = switch insight.currentAge {
        case .some(0...1): 1
        case .some(2...3): 0.8
        case .some: 0.5
        case nil: 0.4
        }
        let toneWeight = tone(insight, story: story) == .good ? 0.8 : 1
        return min(1, max(0, score * freshness * toneWeight * policy.weight))
    }

    // MARK: - Arithmetic

    struct Point: Equatable { var index: Int; var value: Double }

    static func indexed(_ series: [Double?]) -> [Point] {
        series.enumerated().compactMap { index, value in value.map { Point(index: index, value: $0) } }
    }

    /// The middle value, or nil for none.
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The median of every pairwise slope: a line through the days that one
    /// odd reading cannot tilt.
    static func theilSen(_ points: [Point]) -> Double? {
        var slopes: [Double] = []
        for (offset, a) in points.enumerated() {
            for b in points[(offset + 1)...] where b.index != a.index {
                slopes.append((b.value - a.value) / Double(b.index - a.index))
            }
        }
        return median(slopes)
    }

    // MARK: - Ranking

    /// The metrics that moved most, highest severity first, ties kept in the
    /// order given. At most `limit`, and only those at or over `threshold`,
    /// topped up to `minimum` from the rest that have any reading.
    static func ranked<Key>(
        _ insights: [(key: Key, insight: Insight)],
        minimum: Int = 3,
        limit: Int = 5,
        threshold: Double = 0.3
    ) -> [(key: Key, insight: Insight)] {
        let ordered = sortedBySeverity(insights)
        let moved = ordered.filter { $0.insight.severity >= threshold }
        if moved.count >= minimum { return Array(moved.prefix(limit)) }
        let rest = ordered.filter { $0.insight.severity < threshold && $0.insight.current != nil }
        return Array((moved + rest).prefix(minimum))
    }

    /// Severity first, stable among equals: the order given breaks ties.
    static func sortedBySeverity<Element>(_ items: [Element], severity: (Element) -> Double) -> [Element] {
        items.enumerated()
            .sorted { lhs, rhs in
                let a = severity(lhs.element), b = severity(rhs.element)
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func sortedBySeverity<Key>(_ insights: [(key: Key, insight: Insight)]) -> [(key: Key, insight: Insight)] {
        sortedBySeverity(insights) { $0.insight.severity }
    }
}
