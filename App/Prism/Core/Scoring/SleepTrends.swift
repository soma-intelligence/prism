//
//  SleepTrends.swift
//  Prism
//

import Foundation
import HealthScoring
import SomaUI

/// The Sleep page's trend list, as the reference design sets it: one row a reading, its
/// latest value, where that value sits against the person's own usual band,
/// and the month behind it. Pure, so the judging is tested apart from the
/// page.
nonisolated enum SleepTrends {
    /// Where the latest value sits.
    enum Status: Equatable, Sendable {
        case normal, above, below
        /// Bed and wake times: earlier or later than usual is a fact, not a
        /// verdict, so it is worded rather than coloured as out of range.
        case earlier, later
        case debt, noDebt
        case none
    }

    /// The sheet or page a row opens.
    enum Target: Equatable, Sendable {
        case history, debt, dip, breathing, night
    }

    enum Chart: Equatable, Sendable { case line, bars }

    struct Row: Identifiable, Equatable, Sendable {
        var id: String { title }
        var title: String
        var symbol: String
        var value: String?
        var status: Status
        var values: [Double?]
        var band: ClosedRange<Double>?
        var chart: Chart = .line
        var target: Target?
    }

    /// Nights drawn on each row.
    static let window = 30

    /// The latest against a band. Nothing to judge when either is missing.
    static func status(_ latest: Double?, _ band: ClosedRange<Double>?) -> Status {
        guard let latest, let band else { return .none }
        if latest < band.lowerBound { return .below }
        if latest > band.upperBound { return .above }
        return .normal
    }

    /// The usual band from every night before the latest.
    static func usual(_ values: [Double?], floor: Double) -> ClosedRange<Double>? {
        ScoringUsual.of(Array(values.dropLast()), spreadFloor: floor).map { $0.low...$0.high }
    }

    /// "6h 55m", "45m": the way Apple prints a night, through ``SomaFormat``.
    static func hm(_ hours: Double) -> String {
        SomaFormat.duration(max(0, hours) * 3600)
    }

    static func rows(scores: SomaScores?, inputs: ScoreDetailInputs?, dip: ScorePages.NightDip?) -> [Row] {
        let detail = scores?.detail ?? SomaScores.Detail()
        func last(_ values: [Double?]) -> [Double?] { Array(values.suffix(window)) }
        var rows: [Row] = []

        let score = last(detail.sleep)
        let scoreBand = usual(score, floor: ScoringUsual.Floor.scorePoints)
        // Today's score as the gauge shows it, the series behind it.
        let latestScore = scores?.sleep.map(Double.init) ?? (score.last ?? nil)
        rows.append(Row(title: "Sleep score", symbol: "moon.zzz.fill", value: latestScore.map { "\(Int($0.rounded()))" },
                        status: status(latestScore, scoreBand), values: score, band: scoreBand, target: .history))

        let asleep = last(detail.sleepHours)
        let asleepBand = usual(asleep, floor: ScoringUsual.Floor.sleepHours)
        rows.append(Row(title: "Time asleep", symbol: "clock.fill", value: (asleep.last ?? nil).map(hm),
                        status: status(asleep.last ?? nil, asleepBand), values: asleep, band: asleepBand,
                        chart: .bars, target: .night))

        for (title, symbol, series) in [("REM sleep", "moon.fill", detail.remHours), ("Deep sleep", "bed.double.fill", detail.deepHours)] {
            let values = last(series)
            let band = usual(values, floor: 0.1)
            rows.append(Row(title: title, symbol: symbol, value: (values.last ?? nil).map(hm),
                            status: status(values.last ?? nil, band), values: values, band: band, chart: .bars, target: .night))
        }

        // The dipping convention, 10 to 20 percent below resting, rather than
        // a personal band: a dip is judged against physiology, not habit.
        let dips = dip?.nights ?? []
        let latestDip = dip?.today?.percent ?? (dips.last ?? nil)
        rows.append(Row(title: "Heart rate dip", symbol: "heart.fill", value: latestDip.map { "\(Int($0.rounded()))%" },
                        status: status(latestDip, 10...20), values: dips, band: 10...20, target: .dip))

        let debt = last(detail.sleepDebtHours)
        let debtNow = scores?.sleepDebtHours
        rows.append(Row(title: "Sleep debt", symbol: "hourglass", value: debtNow.map(hm),
                        status: debtNow.map { $0 >= 0.25 ? .debt : .noDebt } ?? .none,
                        values: debt.map { $0.map { -$0 } }, band: nil, target: .debt))

        for (title, symbol, series) in [("Bedtime", "moon.stars.fill", detail.bedHour), ("Wake time", "sunrise.fill", detail.wakeHour)] {
            let values = last(series)
            let band = usual(values, floor: 0.25)
            let latest = values.last ?? nil
            let judged: Status = switch status(latest, band) {
            case .below: .earlier
            case .above: .later
            case let other: other
            }
            rows.append(Row(title: title, symbol: symbol, value: latest.map(ScoreMath.clock),
                            status: judged, values: values, band: band))
        }

        if let sjl = socialJetlag(bedHour: detail.bedHour, wakeHour: detail.wakeHour, now: inputs?.now ?? Date()) {
            rows.append(Row(title: "Social jetlag", symbol: "arrow.left.arrow.right", value: hm(sjl),
                            status: sjl < 1 ? .normal : .above,
                            values: last(midpoints(bedHour: detail.bedHour, wakeHour: detail.wakeHour)), band: nil))
        }

        let breathing = last(inputs?.respiratory ?? [])
        let breathingBand = usual(breathing, floor: ScoringUsual.Floor.respiratoryRate)
        rows.append(Row(title: "Breathing", symbol: "lungs.fill",
                        value: (breathing.last ?? nil).map { "\(ScoreMath.number($0, decimals: 1)) /min" },
                        status: status(breathing.last ?? nil, breathingBand), values: breathing, band: breathingBand,
                        target: .breathing))
        return rows
    }

    /// The next time after `date` the clock reads `hour` (above 24 wraps).
    static func next(hour: Double, after date: Date, calendar: Calendar = .current) -> Date {
        let wrapped = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        let minutes = Int((wrapped * 60).rounded())
        return calendar.nextDate(after: date, matching: DateComponents(hour: minutes / 60 % 24, minute: minutes % 60),
                                 matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    }

    // MARK: - Social jetlag

    /// The middle of each night as a clock hour past the evening's midnight
    /// (27.0 is 03:00), or nil where bed or wake is missing.
    static func midpoints(bedHour: [Double?], wakeHour: [Double?]) -> [Double?] {
        let count = min(bedHour.count, wakeHour.count)
        let bed = bedHour.suffix(count), wake = wakeHour.suffix(count)
        return zip(bed, wake).map { bed, wake in
            guard let bed, let wake else { return nil }
            // Bed is above 24 after midnight; wake is a morning clock hour,
            // carried into the same frame.
            var up = wake + 24
            while up <= bed { up += 24 }
            return (bed + up) / 2
        }
    }

    /// Social jetlag (Roenneberg's MSF minus MSW): how far the middle of the
    /// night on free days sits from work days, in hours, over the last four
    /// weeks. Weekend mornings are the free days. Nil until there are two
    /// free and three work nights to compare.
    ///
    /// Under an hour is aligned; an hour or more is linked to higher BMI and
    /// worse metabolic markers (Roenneberg 2012, Curr Biol 22:939; Parsons
    /// 2015, Int J Obes 39:842).
    static func socialJetlag(bedHour: [Double?], wakeHour: [Double?], now: Date, calendar: Calendar = .current) -> Double? {
        let mids = midpoints(bedHour: bedHour, wakeHour: wakeHour)
        let today = calendar.startOfDay(for: now)
        var free: [Double] = [], work: [Double] = []
        for (offset, mid) in mids.reversed().prefix(28).enumerated() {
            guard let mid, let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if calendar.isDateInWeekend(day) { free.append(mid) } else { work.append(mid) }
        }
        guard free.count >= 2, work.count >= 3 else { return nil }
        let meanFree = free.reduce(0, +) / Double(free.count)
        let meanWork = work.reduce(0, +) / Double(work.count)
        return abs(meanFree - meanWork)
    }
}
