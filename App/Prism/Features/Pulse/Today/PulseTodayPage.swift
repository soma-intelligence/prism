//
//  PulseTodayPage.swift
//  Prism
//

import Foundation
import HealthScoring
import SomaUI

/// The words and numbers of the Today page, worked out apart from the view so
/// each one can be tested: the greeting, the sentence under it, the readings
/// pinned to the body, the six tiles and the day's plan.
///
/// Every sentence states what was measured and what it means for today. None
/// of them guesses a cause or speaks for the body.
struct PulseTodayPage {
    let today: PulseToday?
    let status: HealthDashboard.Status
    let scores: SomaScores?
    let insights: PulseInsights
    let peak: ScoringPeakDay?
    let firstName: String?
    let now: Date
    var calendar: Calendar = .current

    // MARK: - Greeting and sentence

    var greeting: String {
        let hour = calendar.component(.hour, from: now)
        let part = switch hour {
        case 4..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        guard let firstName, !firstName.isEmpty else { return "\(part)." }
        return "\(part), \(firstName)."
    }

    /// Before the first read, the sentence says it is reading rather than
    /// inventing a day.
    var isPending: Bool {
        guard today == nil else { return false }
        switch status {
        case .idle, .loading: return true
        default: return false
        }
    }

    var summary: String {
        switch status {
        case .unavailable:
            return "This device has no Apple Health. The same page reads your real values on iPhone and iPad."
        case .failed(let message):
            return HealthProblemWords.message(detail: message)
        case .idle, .loading, .ready:
            break
        }
        guard let today else { return "Reading last night from Apple Health." }
        guard today.hasData else {
            return "Apple Health has nothing for today yet. Readings appear here as your watch records them."
        }

        var sentences: [String] = []
        if let night = today.night {
            sentences.append("You slept \(TodayFormat.duration(text: night.asleep)).")
        } else {
            sentences.append("No sleep was recorded last night.")
        }

        let hrv = insights[.heartRateVariability]?.insight.position
        let resting = insights[.restingHeartRate]?.insight.position
        switch (hrv, resting) {
        case (.within?, .within?):
            sentences.append("HRV and resting heart rate are in your usual range.")
        default:
            var off: [String] = []
            if let hrv, hrv != .within { off.append("HRV is \(hrv == .above ? "above" : "under") your usual") }
            if let resting, resting != .within {
                off.append("resting heart rate is \(resting == .above ? "above" : "under") your usual")
            }
            if !off.isEmpty { sentences.append(TodayFormat.sentence(off.joined(separator: " and "))) }
        }

        if let recovery = scores?.recovery {
            let advice = switch ScoreMath.Band(recovery) {
            case .high: "Today can take a hard session."
            case .middle: "Keep training moderate today."
            case .low: "Keep today easy."
            }
            sentences.append(advice)
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - The body

    var chest: [SomaBodyCallout] {
        [callout(.respiratoryRate, title: "Breathing"), callout(.bloodOxygen, title: "Blood oxygen")]
    }

    var heart: [SomaBodyCallout] {
        [callout(.restingHeartRate, title: "Resting heart rate"), callout(.heartRateVariability, title: "HRV")]
    }

    /// The wrist's temperature against its own usual: a skin reading means
    /// little on its own, and a lot as a shift.
    var wrist: [SomaBodyCallout] {
        let item = insights[.wristTemperature]
        let unit = item.map(\.unit).flatMap { $0.isEmpty ? nil : $0 } ?? "°C"
        guard let item, let latest = item.latest else {
            return [SomaBodyCallout(title: "Wrist temperature", value: nil, unit: unit,
                                    note: today?.hasData == true ? missingNote : nil)]
        }
        guard let usual = item.insight.usual else {
            return [SomaBodyCallout(title: "Wrist temperature", value: item.number, unit: unit, note: InsightEngine.learningCue)]
        }
        let shift = latest - usual
        let sign = shift >= 0 ? "+" : "\u{2212}"
        return [SomaBodyCallout(
            title: "Wrist temperature",
            value: sign + abs(shift).formatted(.number.precision(.fractionLength(2))),
            unit: unit,
            note: "Against your usual",
            tone: tone(item)
        )]
    }

    /// Where the figure's readings were measured.
    var figureCaption: String {
        guard let night = today?.night else { return "Latest readings from Apple Health." }
        return "Measured overnight by Apple Watch, \(night.bed) to \(night.woke)."
    }

    private var missingNote: String {
        today?.night == nil ? "No reading last night" : "Not measured"
    }

    private func item(_ metric: InsightMetric) -> PulseInsightItem? { insights[metric] }

    private func callout(_ metric: InsightMetric, title: String) -> SomaBodyCallout {
        guard let item = insights[metric], today?.hasData != false else {
            return SomaBodyCallout(title: title, value: nil, unit: item(metric)?.unit ?? "", note: nil)
        }
        guard item.number != nil else {
            return SomaBodyCallout(title: title, value: nil, unit: item.unit, note: missingNote)
        }
        return SomaBodyCallout(title: title, value: item.number, unit: item.unit, note: rangeNote(item), tone: tone(item))
    }

    /// "Usual 51 to 56", or "Above usual 44 to 56" with a dot when off it.
    private func rangeNote(_ item: PulseInsightItem) -> String {
        guard let band = item.band ?? item.insight.band else { return InsightEngine.learningCue }
        let range = "\(TodayFormat.like(item.number, band.lowerBound)) to \(TodayFormat.like(item.number, band.upperBound))"
        switch item.insight.position {
        case .above?: return "Above usual \(range)"
        case .below?: return "Under usual \(range)"
        default: return "Usual \(range)"
        }
    }

    private func tone(_ item: PulseInsightItem) -> SomaCueTone? {
        guard let position = item.insight.position, position != .within else { return nil }
        return item.insight.tone.cueTone
    }

    // MARK: - The tiles

    struct Tile: Equatable {
        var title: String
        var value: String?
        var unit: String?
        var note: String?
        var tone: SomaCueTone?
    }

    /// Hours asleep on each of the last seven nights, oldest first.
    var nights: [Double?] { today?.nights ?? Array(repeating: nil, count: 7) }
    var sleepNeedHours: Double? { scores?.sleepNeedHours }

    var sleepTile: Tile {
        let last = nights.last ?? nil
        var note: String?
        if let last, let need = sleepNeedHours {
            let gap = (need - last) * 3600
            let needText = TodayFormat.duration(seconds: need * 3600)
            if abs(gap) < 5 * 60 {
                note = "Meets your \(needText) need"
            } else {
                note = "\(TodayFormat.span(seconds: abs(gap))) \(gap > 0 ? "under" : "over") your \(needText) need"
            }
        } else if today?.night == nil, !isPending {
            note = "No sleep recorded last night"
        }
        return Tile(
            title: "Sleep",
            value: today?.night.map { TodayFormat.duration(text: $0.asleep) },
            note: note
        )
    }

    var recoveryTile: Tile {
        guard let recovery = scores?.recovery else {
            return Tile(title: "Recovery", value: nil, unit: "of 100", note: isPending ? nil : "Needs a night with HRV")
        }
        var parts: [String] = []
        if let hrv = scores?.recoveryTerms.first(where: { $0.kind == .hrv }), let value = hrv.value, let base = hrv.baseline {
            parts.append(value > base * 1.03 ? "HRV above usual" : value < base * 0.97 ? "HRV under usual" : "HRV steady")
        }
        if let rhr = scores?.recoveryTerms.first(where: { $0.kind == .rhr }), let value = rhr.value, let base = rhr.baseline {
            parts.append(value > base + 2 ? "resting heart rate up" : value < base - 2 ? "resting heart rate down" : "resting heart rate steady")
        }
        return Tile(title: "Recovery", value: "\(recovery)", unit: "of 100",
                    note: parts.isEmpty ? nil : TodayFormat.sentence(parts.joined(separator: ", ")))
    }

    var focusTile: Tile {
        guard let peak, let window = peak.deepWork else {
            return Tile(title: "Focus window", value: nil, note: isPending ? nil : "Needs three nights of sleep")
        }
        let end = TodayFormat.clock(hour: window.end, on: now, calendar: calendar)
        if peak.nowHour >= window.end {
            let windDown = TodayFormat.clock(hour: peak.windDownHour, on: now, calendar: calendar)
            return Tile(title: "Focus window", value: TodayFormat.clock(hour: window.start, on: now, calendar: calendar),
                        unit: "to \(end)", note: "Passed. Wind down at \(windDown).")
        }
        return Tile(title: "Focus window", value: TodayFormat.clock(hour: window.start, on: now, calendar: calendar),
                    unit: "to \(end)", note: "When your alertness peaks today")
    }

    /// The energy curve the focus tile draws, 0 to 1.
    var focusCurve: [Double?] { peak?.curve.map { Optional($0.level) } ?? [] }

    /// Today's rises in pulse while still: Soma reads stress from these.
    var stressPeaks: [(start: Date, end: Date)] {
        (today?.events ?? []).filter { $0.id.hasPrefix("peak-") }.compactMap { event in
            guard let start = event.start else { return nil }
            return (start, event.end ?? start)
        }
    }

    var stressTile: Tile {
        guard today?.hasData == true else { return Tile(title: "Stress", value: nil, unit: "min", note: nil) }
        let peaks = stressPeaks
        guard !peaks.isEmpty else {
            return Tile(title: "Stress", value: "0", unit: "min", note: "No rise in pulse at rest since you woke")
        }
        let minutes = peaks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
        return Tile(title: "Stress", value: "\(Int(minutes.rounded()))", unit: "min",
                    note: "Pulse above resting while still, \(peaks.count == 1 ? "once" : "\(peaks.count) times") today")
    }

    /// Minutes of raised pulse in each hour from six in the morning to now.
    var stressHours: [Double?] {
        let day = calendar.startOfDay(for: now)
        let hours = max(1, calendar.component(.hour, from: now) - 5)
        return (0..<hours).map { offset in
            guard let from = calendar.date(byAdding: .hour, value: 6 + offset, to: day),
                  let to = calendar.date(byAdding: .hour, value: 1, to: from) else { return nil }
            let seconds = stressPeaks.reduce(0.0) { total, peak in
                total + max(0, min(peak.end, to).timeIntervalSince(max(peak.start, from)))
            }
            return seconds / 60
        }
    }

    var stepsTile: Tile {
        let days = insights[.steps]?.days ?? []
        let yesterday = days.count >= 2 ? days[days.count - 2] : nil
        return Tile(
            title: "Steps",
            value: today?.stepsToday.map { Int($0.rounded()).formatted() },
            unit: "so far",
            note: yesterday.map { "Yesterday \(Int($0.rounded()).formatted())" }
        )
    }

    var stepDays: [Double?] {
        var days = Array((insights[.steps]?.days ?? []).suffix(7))
        if let steps = today?.stepsToday, !days.isEmpty { days[days.count - 1] = steps }
        return days
    }

    var fitnessTile: Tile {
        guard let item = insights[.vo2Max], item.number != nil else {
            return Tile(title: "Cardio fitness", value: nil, unit: "VO2 max", note: isPending ? nil : "Needs an outdoor walk or run with your watch")
        }
        let known = item.days.compactMap { $0 }
        var note: String?
        if let first = known.first, let last = known.last, known.count >= 2 {
            let change = last - first
            note = abs(change) < 0.3 ? "Steady over 30 days"
                : "\(change > 0 ? "Up" : "Down") \(abs(change).formatted(.number.precision(.fractionLength(1)))) in 30 days"
        }
        return Tile(title: "Cardio fitness", value: item.number, unit: "VO2 max", note: note, tone: tone(item))
    }

    // MARK: - The day

    var plan: [SomaPlanItem] {
        var items: [SomaPlanItem] = []
        let day = calendar.startOfDay(for: now)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }

        if let night = today?.night, let woke = today?.events.first(where: { $0.id == "wake" })?.end {
            items.append(SomaPlanItem(id: "wake", title: "Woke up", detail: "\(TodayFormat.duration(text: night.asleep)) asleep",
                                      state: .done, start: woke))
        }
        for event in today?.events ?? [] where event.id.hasPrefix("workout-") {
            guard let start = event.start else { continue }
            items.append(SomaPlanItem(id: event.id, title: event.title, detail: event.detail, state: .done, start: start, end: event.end))
        }
        if let peak {
            if let window = peak.deepWork {
                items.append(SomaPlanItem(id: "focus", title: "Focus window",
                                          detail: "Alertness peaks until \(TodayFormat.clock(hour: window.end, on: now, calendar: calendar))",
                                          state: .later, start: at(window.start), end: at(window.end)))
            }
            if let training = peak.training {
                items.append(SomaPlanItem(id: "training", title: "Best time to train",
                                          detail: "Until \(TodayFormat.clock(hour: training.end, on: now, calendar: calendar))",
                                          state: .later, start: at(training.start), end: at(training.end)))
            }
            items.append(SomaPlanItem(id: "coffee", title: "Last coffee", detail: "Keeps caffeine low by bedtime",
                                      state: .later, start: at(peak.caffeineCutoffHour)))
            items.append(SomaPlanItem(id: "windDown", title: "Wind down", detail: "Lights low, screens away",
                                      state: .later, start: at(peak.windDownHour)))
            let need = sleepNeedHours.map { "Gives you the \(TodayFormat.duration(seconds: $0 * 3600)) you need" }
            items.append(SomaPlanItem(id: "bed", title: "In bed", detail: need, state: .later,
                                      start: at(peak.bedHour < 12 ? peak.bedHour + 24 : peak.bedHour)))
        }
        return Self.staged(items, now: now)
    }

    /// Past moments are done, the first one still to come is next.
    static func staged(_ items: [SomaPlanItem], now: Date) -> [SomaPlanItem] {
        var sawNext = false
        return items.sorted { $0.start < $1.start }.map { item in
            let over = (item.end ?? item.start) <= now
            let state: SomaPlanItem.State
            if over {
                state = .done
            } else if !sawNext {
                sawNext = true
                state = .next
            } else {
                state = .later
            }
            return SomaPlanItem(id: item.id, title: item.title, detail: item.detail, state: state, start: item.start, end: item.end)
        }
    }

    // MARK: - Noticed

    struct Noticed: Equatable, Identifiable {
        var id: InsightMetric { metric }
        var metric: InsightMetric
        var title: String
        var detail: String
    }

    /// What moved most, each said with its number and its usual.
    var noticed: [Noticed] {
        insights.moved.compactMap { item in
            guard let cue = item.cue, let value = item.value else { return nil }
            let usual = (item.band ?? item.insight.band).map {
                " Usual \(TodayFormat.like(item.number, $0.lowerBound)) to \(TodayFormat.like(item.number, $0.upperBound))."
            } ?? ""
            return Noticed(metric: item.metric, title: "\(item.metric.title): \(cue.lowercasedFirst)", detail: "\(value).\(usual)")
        }
    }
}

extension PulseInsightItem {
    /// The newest reading of the last two days, as a number.
    var latest: Double? { days.suffix(2).compactMap { $0 }.last }
}

/// How Today writes durations and clock times.
enum TodayFormat {
    /// "7 h 12", held on one line.
    static func duration(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)\u{00A0}h\u{00A0}" + String(format: "%02d", minutes % 60)
    }

    /// A duration already written as "7:12" by ``PulseWording/clock(_:)``.
    static func duration(text: String) -> String {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return text }
        return duration(seconds: TimeInterval(hours * 3600 + minutes * 60))
    }

    /// "28 min", or "1 h 05" past the hour.
    static func span(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : duration(seconds: seconds)
    }

    /// An hour of the day (which may run past 24) as a clock time on `date`'s day.
    static func clock(hour: Double, on date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        return day.addingTimeInterval(hour * 3600).formatted(date: .omitted, time: .shortened)
    }

    /// `value` with as many decimals as `sample` prints.
    static func like(_ sample: String?, _ value: Double) -> String {
        let decimals = sample.flatMap { text in text.split(separator: ".").dropFirst().first.map { $0.prefix { $0.isNumber }.count } } ?? 0
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// A clause as a sentence: first letter up, a full stop at the end.
    static func sentence(_ clause: String) -> String {
        guard let first = clause.first else { return clause }
        return first.uppercased() + clause.dropFirst() + "."
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        // An acronym keeps its capitals: "HRV", not "hRV".
        if count > 1, self[index(after: startIndex)].isUppercase { return self }
        return first.lowercased() + dropFirst()
    }
}
