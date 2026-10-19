//
//  MetricDetail.swift
//  Prism
//
//  The arithmetic behind a data type page: one daily year to window into, the band behind the chart (a fixed
//  reference or the person's rolling range), where the latest reading
//  stands, the change over 3 to 90 days, projections for body composition,
//  and the chart's buckets, scale and stats. Pure functions over values, so
//  each is tested without a Health store.
//

import Foundation

/// One metric's daily year: a value per day, oldest first, the last today.
struct MetricMaster: Equatable, Sendable {
    /// The start of today.
    var today: Date
    var days: [Double?]
    /// Diastolic beside systolic, for blood pressure.
    var secondary: [Double?]?

    /// Days a page reads.
    static let length = 365

    func date(at index: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: index - (days.count - 1), to: today) ?? today
    }

    func index(of date: Date, calendar: Calendar) -> Int? {
        let day = calendar.startOfDay(for: date)
        guard let back = calendar.dateComponents([.day], from: day, to: today).day else { return nil }
        let index = days.count - 1 - back
        return days.indices.contains(index) ? index : nil
    }

    var lastIndex: Int? { days.lastIndex { $0 != nil } }
}

enum MetricDetailMath {
    // MARK: - Gap filling and the rolling band

    /// Nil gaps filled by a straight line between neighbours; leading and
    /// trailing gaps take the nearest known value. Empty when nothing is known.
    static func interpolated(_ series: [Double?]) -> [Double] {
        guard let firstKnown = series.compactMap({ $0 }).first else { return [] }
        var result = Array(repeating: firstKnown, count: series.count)
        var lastIndex = -1
        var lastValue = firstKnown
        for (index, value) in series.enumerated() {
            guard let value else { continue }
            if lastIndex < 0 {
                for fill in 0...index { result[fill] = value }
            } else if index - lastIndex > 1 {
                let span = Double(index - lastIndex)
                for fill in (lastIndex + 1)..<index {
                    result[fill] = lastValue + (value - lastValue) * Double(fill - lastIndex) / span
                }
            }
            result[index] = value
            lastIndex = index
            lastValue = value
        }
        if lastIndex >= 0, lastIndex < series.count - 1 {
            for fill in (lastIndex + 1)..<series.count { result[fill] = lastValue }
        }
        return result
    }

    /// The person's range: a fourteen day rolling mean, give or take the
    /// larger of its standard deviation and 3 percent of it. The first slots,
    /// read from a window still filling, keep the first full window's width
    /// so the band enters as a steady ribbon.
    static func rollingBand(_ values: [Double], window: Int = 14) -> (lower: [Double], upper: [Double]) {
        var lower: [Double] = []
        var upper: [Double] = []
        for index in values.indices {
            let slice = values[max(0, index - window + 1)...index]
            let mean = slice.reduce(0, +) / Double(slice.count)
            let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            let deviation = slice.count > 2 ? (variance / Double(slice.count - 1)).squareRoot() : abs(mean) * 0.06
            let spread = max(deviation, abs(mean) * 0.03)
            lower.append(mean - spread)
            upper.append(mean + spread)
        }
        let firstFull = min(window - 1, values.count - 1)
        if firstFull > 0 {
            let width = (upper[firstFull] - lower[firstFull]) / 2
            for index in 0..<firstFull {
                let center = (upper[index] + lower[index]) / 2
                lower[index] = center - width
                upper[index] = center + width
            }
        }
        return (lower, upper)
    }

    /// The band behind the chart, one edge pair per day.
    struct Band: Equatable, Sendable {
        var lower: [Double]
        var upper: [Double]
        /// A fixed healthy zone rather than the person's own range.
        var isReference: Bool

        func range(at index: Int) -> ClosedRange<Double>? {
            guard lower.indices.contains(index), upper.indices.contains(index) else { return nil }
            return min(lower[index], upper[index])...max(lower[index], upper[index])
        }
    }

    /// The reference band where the metric has one, else the rolling band.
    /// Nil before three readings: a range from two days means nothing.
    static func band(_ days: [Double?], profile: MetricProfile) -> Band? {
        let known = days.compactMap { $0 }.count
        if let reference = profile.referenceBand, known >= 1 {
            return Band(
                lower: Array(repeating: reference.lowerBound, count: days.count),
                upper: Array(repeating: reference.upperBound, count: days.count),
                isReference: true
            )
        }
        guard known >= 3 else { return nil }
        let rolling = rollingBand(interpolated(days))
        return Band(lower: rolling.lower, upper: rolling.upper, isReference: false)
    }

    // MARK: - Where it stands

    enum Direction: Sendable, Equatable { case rising, falling, flat }

    /// The word under the big number.
    enum Status: Sendable, Equatable {
        /// Inside the band. `reference` says whose: the healthy zone, or the
        /// person's own range.
        case normal(reference: Bool)
        case above
        case below
        /// A daily total on a day still adding up: its direction, never a
        /// verdict on half a day.
        case direction(Direction)
        case none
    }

    struct Standing: Equatable, Sendable {
        var status: Status
        /// The band at the latest reading, for the legend.
        var band: ClosedRange<Double>?
        var isReference: Bool
    }

    /// Where the latest reading stands against the band at its day.
    ///
    /// - Parameter todayOpen: the metric is a daily total and today is not
    ///   over, so the status reads the direction of the finished days.
    static func standing(_ days: [Double?], profile: MetricProfile, todayOpen: Bool = false) -> Standing {
        guard let band = band(days, profile: profile),
              let lastIndex = days.lastIndex(where: { $0 != nil }),
              let last = days[lastIndex], let range = band.range(at: lastIndex) else {
            return Standing(status: .none, band: nil, isReference: false)
        }
        if todayOpen, days.last.flatMap({ $0 }) != nil {
            let travel = direction(Array(days.suffix(31)), accumulates: true, openDayTail: 1)
            return Standing(status: travel.map(Status.direction) ?? .none, band: range, isReference: band.isReference)
        }
        let status: Status = last > range.upperBound ? .above
            : last < range.lowerBound ? .below
            : .normal(reference: band.isReference)
        return Standing(status: status, band: range, isReference: band.isReference)
    }

    /// The direction over `values` with the open day dropped: the mean of
    /// the first known days against the mean of the last (a week at most),
    /// past a dead band of 1.5 percent (5 for a daily total, which swings by a
    /// fifth from one day to the next). Nil with less than two readings.
    static func direction(_ values: [Double?], accumulates: Bool, openDayTail: Int = 0) -> Direction? {
        let known = Array(values.dropLast(min(openDayTail, values.count))).compactMap { $0 }
        guard known.count >= 2 else { return nil }
        let span = max(1, min(7, known.count / 2))
        let opening = known.prefix(span).reduce(0, +) / Double(span)
        let closing = known.suffix(span).reduce(0, +) / Double(span)
        guard abs(opening) > 0.0001 else { return nil }
        let change = (closing - opening) / abs(opening)
        let dead = accumulates ? 0.05 : 0.015
        if change > dead { return .rising }
        if change < -dead { return .falling }
        return .flat
    }

    // MARK: - Trends analysis

    enum Valence: Sendable, Equatable { case good, bad, neutral }

    struct TrendRow: Equatable, Sendable, Identifiable {
        var id: Int { days }
        var days: Int
        /// Latest minus the value `days` ago, on the gap filled series.
        var change: Double
        var direction: Direction
        var valence: Valence
        /// Eight points over the period.
        var spark: [Double?]

        /// Improving or Worsening where a direction is good or bad news,
        /// else Increasing, Decreasing or Stable.
        var verdict: String {
            switch valence {
            case .good: "Improving"
            case .bad: "Worsening"
            case .neutral:
                switch direction {
                case .rising: "Increasing"
                case .falling: "Decreasing"
                case .flat: "Stable"
                }
            }
        }
    }

    static let trendPeriods = [3, 7, 14, 30, 90]

    static func valence(_ direction: Direction, risingIsGood: Bool?) -> Valence {
        guard let risingIsGood else { return .neutral }
        switch direction {
        case .rising: return risingIsGood ? .good : .bad
        case .falling: return risingIsGood ? .bad : .good
        case .flat: return .neutral
        }
    }

    /// A row per period with enough history behind it: the period has to
    /// start on or after the first reading, so a month of data shows the 3
    /// to 30 day rows and leaves out 90.
    static func trendRows(_ days: [Double?], risingIsGood: Bool?, openDayTail: Int = 0) -> [TrendRow] {
        let dense = interpolated(days)
        let end = dense.count - max(0, openDayTail)
        guard let first = days.firstIndex(where: { $0 != nil }), end > 0, end <= days.count else { return [] }
        let last = dense[end - 1]
        return trendPeriods.compactMap { period in
            let pastIndex = end - 1 - period
            guard pastIndex >= first else { return nil }
            let change = last - dense[pastIndex]
            let direction: Direction = change > 0.05 ? .rising : change < -0.05 ? .falling : .flat
            var spark: [Double?] = []
            let stride = max(1, period / 7)
            var index = pastIndex
            while index < end {
                spark.append(dense[index])
                index += stride
            }
            return TrendRow(
                days: period, change: change, direction: direction,
                valence: valence(direction, risingIsGood: risingIsGood), spark: spark
            )
        }
    }

    // MARK: - Projections

    /// A least squares line through dated points, and what a prediction
    /// interval needs.
    struct Fit: Equatable, Sendable {
        var slope: Double
        var intercept: Double
        var count: Int
        var xMean: Double
        var sxx: Double
        var residualError: Double
        var rSquared: Double
    }

    static func fit(_ points: [(x: Double, y: Double)]) -> Fit? {
        let n = points.count
        guard n >= 5 else { return nil }
        let xMean = points.map(\.x).reduce(0, +) / Double(n)
        let yMean = points.map(\.y).reduce(0, +) / Double(n)
        var sxx = 0.0, sxy = 0.0
        for point in points {
            sxx += (point.x - xMean) * (point.x - xMean)
            sxy += (point.x - xMean) * (point.y - yMean)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = yMean - slope * xMean
        var residual = 0.0, total = 0.0
        for point in points {
            let fitted = intercept + slope * point.x
            residual += (point.y - fitted) * (point.y - fitted)
            total += (point.y - yMean) * (point.y - yMean)
        }
        return Fit(
            slope: slope, intercept: intercept, count: n, xMean: xMean, sxx: sxx,
            residualError: (residual / Double(n - 2)).squareRoot(),
            rSquared: total > 0 ? 1 - residual / total : 0
        )
    }

    /// The value at `x` and the half width of its 95 percent prediction
    /// interval, which widens as `x` moves past the data.
    static func predict(at x: Double, using fit: Fit) -> (value: Double, margin: Double) {
        let leverage = 1 + 1 / Double(fit.count) + (x - fit.xMean) * (x - fit.xMean) / fit.sxx
        return (fit.intercept + fit.slope * x, tQuantile95(fit.count - 2) * fit.residualError * leverage.squareRoot())
    }

    static func tQuantile95(_ degrees: Int) -> Double {
        let table: [Double] = [
            12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
            2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
            2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042,
        ]
        guard degrees >= 1 else { return table[0] }
        if degrees <= 30 { return table[degrees - 1] }
        let z = 1.959964
        return z + (z * z * z + z) / (4 * Double(degrees))
    }

    struct Projection: Equatable, Sendable, Identifiable {
        var id: Int { days }
        var days: Int
        var value: Double
        var margin: Double
        var direction: Direction
    }

    static let projectionHorizons = [7, 30, 90]

    /// Where the line through the last 180 days lands 7, 30 and 90 days on.
    /// Empty unless it is trustworthy: five readings at least, two weeks
    /// apart or more, and a fit that explains a quarter of the movement.
    static func projections(_ days: [Double?], lookback: Int = 180) -> [Projection] {
        let count = days.count
        func points(from start: Int) -> [(x: Double, y: Double)] {
            (max(0, start)..<count).compactMap { index in days[index].map { (Double(index), $0) } }
        }
        var found = points(from: count - lookback)
        if found.count < 5 { found = points(from: 0) }
        guard found.count >= 5, let first = found.first, let last = found.last, last.x - first.x >= 14,
              let line = fit(found), line.rSquared >= 0.25 else { return [] }
        let todayX = Double(count - 1)
        let now = days.compactMap { $0 }.last ?? line.intercept + line.slope * todayX
        return projectionHorizons.map { horizon in
            let (raw, margin) = predict(at: todayX + Double(horizon), using: line)
            let value = max(0, raw)
            let direction: Direction = value > now + 0.05 ? .rising : value < now - 0.05 ? .falling : .flat
            return Projection(days: horizon, value: value, margin: margin, direction: direction)
        }
    }

    // MARK: - The chart

    struct Bucket: Equatable, Sendable, Identifiable {
        var id: Date { interval.start }
        var interval: DateInterval
        /// The mean of the bucket's days, nil when none had a reading.
        var value: Double?
        /// Diastolic, for blood pressure.
        var secondary: Double?
        /// The band over the bucket.
        var band: ClosedRange<Double>?
    }

    /// The master's days folded into the window's buckets: each bucket the
    /// mean of the days it holds.
    static func buckets(
        _ master: MetricMaster,
        band: Band?,
        intervals: [DateInterval],
        calendar: Calendar
    ) -> [Bucket] {
        intervals.map { interval in
            var values: [Double] = []
            var seconds: [Double] = []
            var lows: [Double] = []
            var highs: [Double] = []
            var day = calendar.startOfDay(for: interval.start)
            while day < interval.end {
                if let index = master.index(of: day, calendar: calendar) {
                    if let value = master.days[index] { values.append(value) }
                    if let value = master.secondary?[index] { seconds.append(value) }
                    if let range = band?.range(at: index) {
                        lows.append(range.lowerBound)
                        highs.append(range.upperBound)
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
            let range: ClosedRange<Double>? = if let low = mean(lows), let high = mean(highs) { low...max(low, high) } else { nil }
            return Bucket(interval: interval, value: mean(values), secondary: mean(seconds), band: range)
        }
    }

    /// A moving average through sparse dots: each known bucket the mean of
    /// the known values within `radius` buckets of it.
    static func smoothed(_ values: [Double?], radius: Int = 2) -> [Double?] {
        values.indices.map { index in
            guard values[index] != nil else { return nil }
            let near = values[max(0, index - radius)...min(values.count - 1, index + radius)].compactMap { $0 }
            return near.reduce(0, +) / Double(near.count)
        }
    }

    struct Stats: Equatable, Sendable {
        var minimum: Double
        var average: Double
        var maximum: Double
    }

    static func stats(_ values: [Double?]) -> Stats? {
        let known = values.compactMap { $0 }
        guard let low = known.min(), let high = known.max() else { return nil }
        return Stats(minimum: low, average: known.reduce(0, +) / Double(known.count), maximum: high)
    }

    /// The y scale: always holds the band, never lets a small wobble fill
    /// the plot (at least 1.35 times the band's height), never climbs past
    /// the metric's ceiling, never dips under zero for values that cannot.
    static func domain(values: [Double], bands: [ClosedRange<Double>], ceiling: Double?, zeroBased: Bool) -> ClosedRange<Double> {
        var low = values.min() ?? bands.map(\.lowerBound).min() ?? 0
        var high = values.max() ?? bands.map(\.upperBound).max() ?? 1
        if let bandLow = bands.map(\.lowerBound).min(), let bandHigh = bands.map(\.upperBound).max() {
            low = min(low, bandLow)
            high = max(high, bandHigh)
            let wanted = (bandHigh - bandLow) * 1.35
            if high - low < wanted {
                let middle = (high + low) / 2
                low = min(values.min() ?? low, middle - wanted / 2)
                high = max(values.max() ?? high, middle + wanted / 2)
            }
        }
        if zeroBased { low = min(0, low) }
        let pad = max((high - low) * 0.08, high == low ? max(abs(high) * 0.1, 1) : 0)
        low = zeroBased ? low : low - pad
        high += pad
        if let ceiling { high = min(high, ceiling) }
        if values.allSatisfy({ $0 >= 0 }) { low = max(0, low) }
        return low...max(high, low + 0.0001)
    }
}
