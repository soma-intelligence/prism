//
//  MeetingStressAnalysis.swift
//  Prism
//
//  Whether a meeting raised the heart, whether the meeting or the walking
//  did it, and what that says about the meetings still to come.
//
//  Each meeting is read against the hour before it, not against the day or
//  the resting rate: a seated, awake heart already runs above resting, and
//  the hour before is the same person on the same day in the same state.
//  Heart readings taken while the body moved (steps around the reading, or a
//  workout) are set aside, because people walk during calls and a walking
//  heart says nothing about the call. What is left is the still heart in the
//  meeting against the still heart before it:
//
//    raised while still               stressful
//    raised only while moving         active, the movement explains it
//    not raised                       calm
//    too few readings                 unknown
//
//  The verdicts then group by who the meeting was with, by series and by
//  the words in the title, and the upcoming week is forecast from the
//  closest group with enough history behind it. A group says nothing under
//  three read meetings: two tense calls with one person is a coincidence,
//  not a pattern. As everywhere in Mind, this is a correlation and the page
//  never says a person causes stress.
//
//  Pure values in and out, so every rule here is tested without a store.
//

import Foundation
import HealthExportCore

nonisolated enum MeetingStressAnalysis {
    // MARK: Rules

    /// How far back the baseline reaches before a meeting starts.
    static let baselineWindow: TimeInterval = 60 * 60
    /// The minutes just before a meeting are left out of its baseline: they
    /// are the walk to the room or the scramble to join the call.
    static let baselineGap: TimeInterval = 5 * 60
    /// Still readings a baseline needs before it is trusted. A watch reads
    /// every few minutes at rest, so an hour gives about twelve.
    static let minimumBaselineReadings = 3
    /// Readings inside a meeting before it is read at all.
    static let minimumMeetingReadings = 3
    /// Beats per minute over the baseline that count as raised. A seated
    /// heart drifts by three or four beats from one half hour to the next;
    /// eight is past that drift and well short of the thirty that marks a
    /// stress peak on the Today page (`PulseSignals.raisedBy`).
    static let raisedBy: Double = 8
    /// Without a measured baseline, a seated awake heart sits about this far
    /// above resting. Used only as a fallback, at a lower confidence.
    static let awakeAboveResting: Double = 10
    /// Steps around a reading, and how far around, that mean the body was
    /// moving: the Today page's own rule (`PulseSignals.movingSteps`).
    static let movingSteps: Double = 100
    static let stepWindow: TimeInterval = 5 * 60
    /// A workout keeps the heart up for a while after it ends.
    static let workoutMargin: TimeInterval = 10 * 60
    /// Read meetings a person, series or word needs before it is linked to
    /// anything, and before it forecasts.
    static let minimumEvidence = 3
    /// A link claims a lean toward stress at this share of its meetings, and
    /// only when that share stands clear of the person's overall rate.
    static let linkedShare = 0.5
    static let linkedLift = 0.15
    /// How many meetings' worth of the overall rate a group's own rate is
    /// pulled toward: with three meetings the overall rate still counts for a
    /// lot, with twenty it barely moves the answer.
    static let priorWeight = 2.0
    /// The rate assumed before any meeting has been read.
    static let defaultRate = 0.3
    /// How far ahead the forecast looks.
    static let forecastDays = 7
    /// Bpm values outside this span are a sensor's mistake.
    static let plausibleHeartRate: ClosedRange<Double> = 25...240

    // MARK: - One meeting

    enum Verdict: String, Sendable, CaseIterable {
        case calm, stressful, active, unknown

        var title: String {
            switch self {
            case .calm: "Calm"
            case .stressful: "Stressful"
            case .active: "Moving"
            case .unknown: "No reading"
            }
        }
    }

    struct Assessment: Equatable, Sendable, Identifiable {
        var event: MindCalendarEvent
        var verdict: Verdict
        /// 0 to 1: how much the verdict can be leaned on. Grows with the
        /// readings behind it, a measured baseline and the distance from the
        /// threshold.
        var confidence: Double
        /// The still heart before the meeting, in bpm.
        var baseline: Double?
        /// False when the baseline is resting plus a seated allowance rather
        /// than the hour before.
        var baselineIsMeasured: Bool
        /// The upper quartile of the still readings in the meeting, in bpm.
        /// The upper quartile rather than the mean, so ten tense minutes in
        /// an hour still show.
        var stillHeartRate: Double?
        /// The same over every reading, moving or not.
        var heartRate: Double?
        /// Steps taken during the meeting, a phone and a watch counted once.
        var steps: Double
        /// The share of the meeting's heart readings taken while moving.
        var movingShare: Double?
        /// Minutes of the meeting a workout covered.
        var workoutMinutes: Double
        /// Heart readings inside the meeting.
        var readings: Int

        var id: String { event.id }

        /// Beats over the baseline while still, else over every reading.
        var rise: Double? {
            guard let baseline else { return nil }
            return (stillHeartRate ?? heartRate).map { $0 - baseline }
        }

        var stepsPerMinute: Double? {
            event.minutes > 0 ? steps / event.minutes : nil
        }

        /// Read for stress: stressful or calm. A moving meeting tells nothing
        /// about the meeting, and an unread one nothing at all.
        var isRead: Bool { verdict == .stressful || verdict == .calm }
    }

    /// Reads one meeting.
    ///
    /// - Parameters:
    ///   - heartRate: readings from at least an hour before the meeting to
    ///     its end; anything outside is ignored.
    ///   - steps: step samples over the same span.
    ///   - workouts: workouts around the meeting.
    ///   - resting: the day's resting rate, the fallback baseline.
    ///   - others: the day's other meetings, kept out of the baseline so a
    ///     tense call just before does not make this one look calm.
    static func assess(
        _ event: MindCalendarEvent,
        heartRate: [HealthReading],
        steps: [HealthReading],
        workouts: [HealthReading],
        resting: Double?,
        others: [MindCalendarEvent] = []
    ) -> Assessment {
        let baselineStart = event.start.addingTimeInterval(-baselineWindow)
        let baselineEnd = event.start.addingTimeInterval(-baselineGap)
        let track = StepTrack(steps: steps, from: baselineStart.addingTimeInterval(-stepWindow), to: event.end.addingTimeInterval(stepWindow))
        let hearts = heartRate.filter { $0.value.isFinite && plausibleHeartRate.contains($0.value) }

        func isMoving(_ reading: HealthReading) -> Bool {
            if workouts.contains(where: {
                reading.start >= $0.start.addingTimeInterval(-workoutMargin) && reading.start <= $0.end.addingTimeInterval(workoutMargin)
            }) { return true }
            return track.steps(from: reading.start.addingTimeInterval(-stepWindow), to: reading.start.addingTimeInterval(stepWindow)) >= movingSteps
        }

        let during = hearts.filter { $0.start >= event.start && $0.start < event.end }
        let moving = during.filter(isMoving)
        let still = during.filter { !isMoving($0) }
        let workoutMinutes = workouts.reduce(0.0) { total, workout in
            let overlap = min(event.end, workout.end).timeIntervalSince(max(event.start, workout.start))
            return total + max(0, overlap) / 60
        }
        let stepsDuring = track.steps(from: event.start, to: event.end)

        let before = hearts.filter { reading in
            reading.start >= baselineStart && reading.start < baselineEnd && !isMoving(reading)
                && !others.contains { $0.id != event.id && reading.start >= $0.start && reading.start < $0.end }
        }
        var baseline: Double?
        var measured = false
        if before.count >= minimumBaselineReadings {
            baseline = percentile(before.map(\.value), 0.5)
            measured = true
        } else if let resting, resting.isFinite, plausibleHeartRate.contains(resting) {
            baseline = resting + awakeAboveResting
        }

        var assessment = Assessment(
            event: event, verdict: .unknown, confidence: 0,
            baseline: baseline, baselineIsMeasured: measured,
            stillHeartRate: still.count >= minimumMeetingReadings ? percentile(still.map(\.value), 0.75) : nil,
            heartRate: during.count >= minimumMeetingReadings ? percentile(during.map(\.value), 0.75) : nil,
            steps: stepsDuring,
            movingShare: during.isEmpty ? nil : Double(moving.count) / Double(during.count),
            workoutMinutes: workoutMinutes,
            readings: during.count
        )
        guard let baseline, let overall = assessment.heartRate else { return assessment }

        let stillRise = assessment.stillHeartRate.map { $0 - baseline }
        let overallRise = overall - baseline
        let rise: Double
        if let stillRise {
            rise = stillRise
            if stillRise >= raisedBy {
                assessment.verdict = .stressful
            } else if !moving.isEmpty, overallRise >= raisedBy {
                // Still, the heart held; moving, it rose. The walk did it.
                assessment.verdict = .active
            } else {
                assessment.verdict = .calm
            }
        } else {
            // Moving for nearly all of it: there is no still heart to read.
            rise = overallRise
            assessment.verdict = overallRise >= raisedBy ? .active : .calm
        }

        let used = Double(assessment.verdict == .active ? during.count : max(still.count, 1))
        let coverage = min(1, used / 8)
        let margin = min(1, abs(rise - raisedBy) / raisedBy)
        // Calm read off a moving heart says little: it was never still.
        let stillness = stillRise == nil && assessment.verdict == .calm ? 0.5 : 1
        let confidence = coverage * (measured ? 1 : 0.6) * (0.5 + 0.5 * margin) * stillness
        assessment.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        return assessment
    }

    /// Reads every meeting of one day against that day's samples.
    static func assessDay(
        _ meetings: [MindCalendarEvent],
        heartRate: [HealthReading],
        steps: [HealthReading],
        workouts: [HealthReading],
        resting: Double?
    ) -> [Assessment] {
        meetings.map { assess($0, heartRate: heartRate, steps: steps, workouts: workouts, resting: resting, others: meetings) }
    }

    // MARK: - Links

    struct Link: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable { case series, attendee, keyword, partOfDay }

        var kind: Kind
        var key: String
        /// The name the page shows: the person, the series' latest title,
        /// the word, the part of the day.
        var title: String
        /// Meetings read as stressful or calm.
        var read: Int
        var stressful: Int
        /// Meetings where moving explained the rise, kept apart.
        var active: Int
        /// The mean still rise over the read meetings, in bpm.
        var meanRise: Double?

        var id: String { kind.rawValue + ":" + key }
        var share: Double { read > 0 ? Double(stressful) / Double(read) : 0 }
        var hasEvidence: Bool { read >= MeetingStressAnalysis.minimumEvidence }

        /// The chance its next meeting runs above the usual: its own rate,
        /// pulled toward the overall rate by ``priorWeight`` meetings.
        func likelihood(overall: Double?) -> Double {
            let prior = overall ?? MeetingStressAnalysis.defaultRate
            let weight = MeetingStressAnalysis.priorWeight
            return (Double(stressful) + prior * weight) / (Double(read) + weight)
        }

        /// Leans toward stress: enough meetings, at least two of them tense,
        /// and a share clear of the overall rate.
        func isLinked(overall: Double?) -> Bool {
            hasEvidence && stressful >= 2
                && share >= max(MeetingStressAnalysis.linkedShare, (overall ?? 0) + MeetingStressAnalysis.linkedLift)
        }
    }

    enum PartOfDay: String, Sendable, CaseIterable {
        case morning, midday, afternoon, evening

        init(hour: Int) {
            switch hour {
            case ..<12: self = .morning
            case 12..<14: self = .midday
            case 14..<18: self = .afternoon
            default: self = .evening
            }
        }

        var title: String {
            switch self {
            case .morning: "morning"
            case .midday: "midday"
            case .afternoon: "afternoon"
            case .evening: "evening"
            }
        }
    }

    /// Everything read so far, grouped four ways.
    struct History: Equatable, Sendable {
        var assessments: [Assessment]
        var series: [String: Link]
        var attendees: [String: Link]
        var keywords: [String: Link]
        var parts: [String: Link]

        var read: Int { assessments.filter(\.isRead).count }
        var stressful: Int { assessments.filter { $0.verdict == .stressful }.count }
        /// The share of read meetings that ran above the usual, nil before
        /// any was read.
        var overall: Double? { read > 0 ? Double(stressful) / Double(read) : nil }

        /// People, series and words that lean toward stress, the strongest
        /// first. Parts of the day are left to the forecast: "afternoons" is
        /// not someone to prepare for.
        var raisers: [Link] {
            let overall = overall
            return (Array(series.values) + Array(attendees.values) + Array(keywords.values))
                .filter { $0.isLinked(overall: overall) }
                .sorted { lhs, rhs in
                    lhs.share != rhs.share ? lhs.share > rhs.share
                        : lhs.read != rhs.read ? lhs.read > rhs.read : lhs.id < rhs.id
                }
        }
    }

    static func history(_ assessments: [Assessment], calendar: Calendar) -> History {
        var series: [String: Link] = [:]
        var attendees: [String: Link] = [:]
        var words: [String: Link] = [:]
        var parts: [String: Link] = [:]
        var rises: [String: [Double]] = [:]

        func add(_ assessment: Assessment, to table: inout [String: Link], kind: Link.Kind, key: String, title: String) {
            guard !key.isEmpty else { return }
            var link = table[key] ?? Link(kind: kind, key: key, title: title, read: 0, stressful: 0, active: 0, meanRise: nil)
            // Newest last, so the title shown is the latest one.
            link.title = title
            switch assessment.verdict {
            case .stressful: link.read += 1; link.stressful += 1
            case .calm: link.read += 1
            case .active: link.active += 1
            case .unknown: break
            }
            if assessment.isRead, let rise = assessment.rise, rise.isFinite {
                rises[link.id, default: []].append(rise)
                let values = rises[link.id] ?? []
                link.meanRise = values.reduce(0, +) / Double(values.count)
            }
            table[key] = link
        }

        for assessment in assessments.sorted(by: { $0.event.start < $1.event.start }) {
            let event = assessment.event
            add(assessment, to: &series, kind: .series, key: seriesKey(event), title: event.title)
            for name in Set(event.attendees.map(attendeeKey)) {
                let shown = event.attendees.first { attendeeKey($0) == name } ?? name
                add(assessment, to: &attendees, kind: .attendee, key: name, title: shown)
            }
            for word in keywords(in: event.title) {
                add(assessment, to: &words, kind: .keyword, key: word, title: word)
            }
            let part = PartOfDay(hour: calendar.component(.hour, from: event.start))
            add(assessment, to: &parts, kind: .partOfDay, key: part.rawValue, title: part.title)
        }
        return History(assessments: assessments, series: series, attendees: attendees, keywords: words, parts: parts)
    }

    /// The series an event belongs to: its calendar series when it repeats,
    /// else its folded title, so a meeting booked fresh each week still
    /// groups with itself.
    static func seriesKey(_ event: MindCalendarEvent) -> String {
        if let id = event.seriesID, !id.isEmpty { return "id:" + id }
        let title = MindMeetingStress.key(event)
        return title.isEmpty ? "" : "title:" + title
    }

    static func attendeeKey(_ name: String) -> String {
        MindEventClassifier.normalize(name).trimmingCharacters(in: .whitespaces)
    }

    /// Words generic enough to appear in any meeting's title.
    static let commonWords: Set<String> = [
        "meeting", "call", "with", "and", "the", "for", "weekly", "daily", "monthly",
        "catch", "chat", "sync", "check", "busy", "invite", "updated", "invitation",
        "zoom", "teams", "meet", "google", "from", "about", "this", "that", "team",
    ]

    /// The distinctive words of a title, folded: four letters or more and not
    /// one of ``commonWords``.
    static func keywords(in title: String) -> Set<String> {
        let words = MindEventClassifier.normalize(title).split(whereSeparator: { !$0.isLetter }).map(String.init)
        return Set(words.filter { $0.count >= 4 && !commonWords.contains($0) })
    }

    // MARK: - Forecast

    struct Forecast: Equatable, Sendable, Identifiable {
        enum Level: Sendable {
            case likely, possible, unlikely, unknown

            var title: String {
                switch self {
                case .likely: "Likely tense"
                case .possible: "Could be tense"
                case .unlikely: "Likely calm"
                case .unknown: "New"
                }
            }
        }

        enum Basis: Sendable { case series, attendee, keyword, partOfDay, none }

        var event: MindCalendarEvent
        /// 0 to 1, nil when nothing in the history matches.
        var likelihood: Double?
        var basis: Basis
        /// The reason in plain words: "4 of 5 meetings with Alex ran above
        /// your usual."
        var reason: String

        var id: String { event.id }

        var level: Level {
            guard let likelihood, likelihood.isFinite else { return .unknown }
            if likelihood >= 0.6 { return .likely }
            if likelihood >= 0.35 { return .possible }
            return .unlikely
        }
    }

    /// The forecast for one meeting, from the closest group with enough
    /// history: its series first, since the same meeting is the best guide to
    /// itself; then the people in it, the most tense of them leading because
    /// that is who to prepare for; then the words in its title; then the
    /// part of the day.
    static func forecast(_ event: MindCalendarEvent, history: History, calendar: Calendar) -> Forecast {
        let overall = history.overall

        if let link = history.series[seriesKey(event)], link.hasEvidence {
            return Forecast(event: event, likelihood: link.likelihood(overall: overall), basis: .series,
                            reason: "\(link.stressful) of \(link.read) times, this meeting ran above your usual.")
        }

        let people = Set(event.attendees.map(attendeeKey)).compactMap { history.attendees[$0] }.filter(\.hasEvidence)
        if let link = strongest(people, overall: overall) {
            return Forecast(event: event, likelihood: link.likelihood(overall: overall), basis: .attendee,
                            reason: "\(link.stressful) of \(link.read) meetings with \(link.title) ran above your usual.")
        }

        let words = keywords(in: event.title).compactMap { history.keywords[$0] }.filter(\.hasEvidence)
        if let link = strongest(words, overall: overall) {
            return Forecast(event: event, likelihood: link.likelihood(overall: overall), basis: .keyword,
                            reason: "\(link.stressful) of \(link.read) meetings about \u{201C}\(link.title)\u{201D} ran above your usual.")
        }

        let part = PartOfDay(hour: calendar.component(.hour, from: event.start))
        if let link = history.parts[part.rawValue], link.hasEvidence {
            return Forecast(event: event, likelihood: link.likelihood(overall: overall), basis: .partOfDay,
                            reason: "\(link.stressful) of \(link.read) \(part.title) meetings ran above your usual.")
        }

        return Forecast(event: event, likelihood: nil, basis: .none, reason: "Too few meetings like this one to say yet.")
    }

    /// Forecasts for the meetings starting after `now` and within
    /// ``forecastDays``, soonest first.
    static func forecasts(_ events: [MindCalendarEvent], history: History, now: Date, calendar: Calendar) -> [Forecast] {
        let horizon = calendar.date(byAdding: .day, value: forecastDays, to: now) ?? now.addingTimeInterval(Double(forecastDays) * 86_400)
        return MindMeetingStress.meetings(in: events)
            .filter { $0.start > now && $0.start <= horizon }
            .map { forecast($0, history: history, calendar: calendar) }
    }

    private static func strongest(_ links: [Link], overall: Double?) -> Link? {
        links.max { lhs, rhs in
            let left = lhs.likelihood(overall: overall), right = rhs.likelihood(overall: overall)
            return left != right ? left < right : lhs.read != rhs.read ? lhs.read < rhs.read : lhs.key > rhs.key
        }
    }

    // MARK: - Helpers

    static func percentile(_ values: [Double], _ share: Double) -> Double? {
        MindUsual.percentile(values.filter(\.isFinite), share)
    }

    /// Steps minute by minute over a span. A phone and a watch both write
    /// steps for the same walk, and adding them would double it, so each
    /// minute keeps the higher cadence of the samples covering it.
    struct StepTrack {
        let start: Date
        let perMinute: [Double]

        init(steps: [HealthReading], from start: Date, to end: Date) {
            self.start = start
            let count = max(0, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
            var minutes = Array(repeating: 0.0, count: count)
            for sample in steps where sample.value.isFinite && sample.value > 0 && sample.end > start && sample.start < end {
                let length = max(sample.end.timeIntervalSince(sample.start), 60)
                let cadence = sample.value / (length / 60)
                let first = max(0, Int((sample.start.timeIntervalSince(start) / 60).rounded(.down)))
                let last = min(count, Int((max(sample.end, sample.start.addingTimeInterval(60)).timeIntervalSince(start) / 60).rounded(.up)))
                guard first < last else { continue }
                for minute in first..<last { minutes[minute] = max(minutes[minute], cadence) }
            }
            perMinute = minutes
        }

        /// Steps between two moments, by whole minutes.
        func steps(from lower: Date, to upper: Date) -> Double {
            let first = max(0, Int((lower.timeIntervalSince(start) / 60).rounded(.down)))
            let last = min(perMinute.count, Int((upper.timeIntervalSince(start) / 60).rounded(.up)))
            guard first < last else { return 0 }
            return perMinute[first..<last].reduce(0, +)
        }
    }
}
