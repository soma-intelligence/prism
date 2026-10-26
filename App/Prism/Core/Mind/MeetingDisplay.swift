//
//  MeetingDisplay.swift
//  Prism
//
//  How the meetings page words what `MeetingStressAnalysis` found: a person
//  named the way a friend would say it rather than by the address an
//  invitation was sent to, a title cut down to who the meeting is with when a
//  booking tool wrote it, the days a list is grouped under, the page's
//  verdict and the sentences under each card.
//
//  Presentation only: nothing here reads or changes a verdict. Pure values in
//  and out, so every rule is tested without a view.
//

import Foundation

nonisolated enum MeetingDisplay {
    // MARK: - People

    /// The name to show for an attendee. A real name stays as it is; an
    /// address becomes its local part, split on the separators people put in
    /// addresses and capitalized: "nicolas.martin@augura.health" reads
    /// "Nicolas Martin", "jeanpaul@augura.health" reads "Jeanpaul". Digits
    /// that only number an address ("alex2") are dropped.
    static func personName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = trimmed
        if address.lowercased().hasPrefix("mailto:") { address = String(address.dropFirst("mailto:".count)) }
        guard let at = address.firstIndex(of: "@") else { return trimmed }
        let local = address[..<at]
        let parts = local
            .split(whereSeparator: { ".-_+".contains($0) })
            .map { $0.filter { !$0.isNumber } }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return trimmed }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    /// "Alex", "Alex and Sam", "Alex and 5 others", each by ``personName(_:)``.
    static func people(_ names: [String]) -> String {
        let shown = names.map(personName)
        switch shown.count {
        case 0: return ""
        case 1: return shown[0]
        case 2: return "\(shown[0]) and \(shown[1])"
        default: return "\(shown[0]) and \(shown.count - 1) others"
        }
    }

    /// A sentence with every address in it replaced by its name: the
    /// forecast's reason names the person it learned from as the calendar
    /// gave them.
    static func namingPeople(in text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard word.contains("@") else { return String(word) }
            // Keep the punctuation a sentence put after the address.
            let tail = word.reversed().prefix { ".,;:)".contains($0) }
            let address = word.dropLast(tail.count)
            return personName(String(address)) + String(tail.reversed())
        }
        return words.joined(separator: " ")
    }

    // MARK: - Titles

    /// What a booking tool puts before the name: "30 Minutes Meeting with",
    /// "30 min with", "1 hour call with", "Meeting with".
    private static var bookingPrefix: Regex<(Substring, Substring)> {
        #/^(?:\d+\s*(?:min|mins|minute|minutes|hr|hrs|hour|hours|h)\b\s*)?(?:meeting|call|chat|session)?\s*(?:with|w/)\s+(.+)$/#
            .ignoresCase()
    }

    /// A booking title with nobody in it: "30 Minute Meeting".
    private static var bareDuration: Regex<Substring> {
        #/^\d+\s*(?:min|mins|minute|minutes|hr|hrs|hour|hours|h)\b\s*(?:meeting|call|chat|session)?$/#
            .ignoresCase()
    }

    /// What an invitation adds in front of the title.
    private static var invitationPrefix: Regex<Substring> {
        #/^(?:updated invitation|invitation|fw|fwd|re)\s*:\s*/#
            .ignoresCase()
    }

    /// The title to show. A booking tool's title becomes the other person:
    /// "30 Minutes Meeting with Philippe Boulanger" reads "Philippe
    /// Boulanger"; "30 min with Alex (Jean Dupont)", where the owner of
    /// the booking page comes first and the guest in brackets, reads "Jean
    /// Dupont". A bare "30 Minute Meeting" reads as whoever it is with. Every
    /// other title stays as written, its whitespace folded.
    static func title(_ raw: String, attendees: [String] = []) -> String {
        var text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        text = text.replacing(invitationPrefix, with: "")
        if let match = text.wholeMatch(of: bookingPrefix) {
            let named = String(match.output.1).trimmingCharacters(in: .whitespaces)
            if let open = named.firstIndex(of: "("), let close = named.lastIndex(of: ")"), open < close {
                let guest = named[named.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
                if !guest.isEmpty { return personName(guest) }
            }
            if !named.isEmpty { return personName(named) }
        }
        if text.wholeMatch(of: bareDuration) != nil {
            return attendees.first.map(personName) ?? "Meeting"
        }
        return text.isEmpty ? "Meeting" : text
    }

    // MARK: - Days

    /// Items grouped under the day they start, the days in `newestFirst`
    /// order and each day's items earliest first, the way a timeline reads.
    static func days<Item>(_ items: [Item], start: (Item) -> Date, newestFirst: Bool, calendar: Calendar) -> [(day: Date, items: [Item])] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: start($0)) }
        return grouped.keys
            .sorted { newestFirst ? $0 > $1 : $0 < $1 }
            .map { day in (day, (grouped[day] ?? []).sorted { start($0) < start($1) }) }
    }

    /// The heading over a day: "Today", "Yesterday", "Tomorrow", the
    /// weekday within the week either side ("Thu"), else the date ("Thu 16
    /// Oct").
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let distance = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0
        switch distance {
        case 0: return "Today"
        case -1: return "Yesterday"
        case 1: return "Tomorrow"
        default:
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
            if abs(distance) > 6 { style = style.day().month(.abbreviated) }
            return day.formatted(style)
        }
    }

    // MARK: - The page's verdict

    /// The read meetings the page's verdict stands on.
    struct Summary: Equatable, Sendable {
        enum Span: Sendable { case week, month }

        var span: Span
        /// Meetings read as calm or stressful.
        var read: Int
        var stressful: Int
        /// The mean still rise over the read meetings, in bpm.
        var meanRise: Double?

        var share: Double? { read > 0 ? Double(stressful) / Double(read) : nil }
    }

    /// The last seven days when any meeting in them was read, else
    /// everything read, so a quiet week still has something to say.
    static func summary(_ assessments: [MeetingStressAnalysis.Assessment], now: Date, calendar: Calendar) -> Summary {
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let past = assessments.filter { $0.event.end <= now && $0.isRead }
        let week = past.filter { $0.event.start >= weekStart }
        let chosen = week.isEmpty ? past : week
        let rises = chosen.compactMap(\.rise).filter(\.isFinite)
        return Summary(
            span: week.isEmpty ? .month : .week,
            read: chosen.count,
            stressful: chosen.filter { $0.verdict == .stressful }.count,
            meanRise: rises.isEmpty ? nil : rises.reduce(0, +) / Double(rises.count)
        )
    }

    /// "Meetings ran calm this week.", the verdict the page leads with.
    static func headline(_ summary: Summary) -> String {
        guard let share = summary.share else { return "No meetings read yet." }
        let when = summary.span == .week ? "this week" : "lately"
        switch share {
        case 0: return "Meetings ran calm \(when)."
        case ..<0.3: return "Meetings ran mostly calm \(when)."
        case ..<0.6: return "Some meetings ran tense \(when)."
        default: return "Meetings ran tense \(when)."
        }
    }

    /// The one grey line under the headline.
    static func reason(_ summary: Summary) -> String {
        guard summary.read > 0 else {
            return "Each meeting is read against your heart in the hour before, once your watch has read one."
        }
        let tense = summary.stressful == 0 ? "None" : "\(summary.stressful) of \(summary.read)"
        return "\(tense) ran above the hour before."
    }

    // MARK: - One meeting

    /// What a meeting's evidence says, in one sentence for its expanded row.
    static func explanation(_ assessment: MeetingStressAnalysis.Assessment) -> String {
        let rise = assessment.rise.map { Int($0.rounded()) }
        var sentence: String
        switch assessment.verdict {
        case .stressful:
            sentence = "Sitting still, your heart ran \(rise.map { "\($0) bpm" } ?? "well") above the hour before."
        case .calm:
            sentence = "Your heart stayed within \(Int(MeetingStressAnalysis.raisedBy)) bpm of the hour before."
        case .active:
            sentence = "Your heart rose while you moved, so the walking explains it."
        case .unknown:
            sentence = assessment.readings == 0 ? "No heart readings during this meeting." : "Too few heart readings to tell."
        }
        if assessment.workoutMinutes >= 1 {
            sentence += " A workout covered \(Int(assessment.workoutMinutes.rounded())) min of it."
        }
        return sentence
    }

    // MARK: - People and series that lean

    /// The quiet line under the page when nobody leans toward stress, and
    /// how far along the closest person or series is, nil once someone has
    /// enough meetings behind them to be judged.
    ///
    /// The count that matters is per person or series, never the total: 29
    /// meetings with 29 different people link nobody.
    static func footnote(_ history: MeetingStressAnalysis.History) -> (text: String, progress: Double?) {
        let needed = MeetingStressAnalysis.minimumEvidence
        let closest = (Array(history.series.values) + Array(history.attendees.values)).map(\.read).max() ?? 0
        if closest >= needed {
            return ("No one stands out: meetings with each person and series run about the same.", nil)
        }
        let progress = Double(closest) / Double(needed)
        let reading = closest == 0
            ? "none has one read yet"
            : "the closest has \(closest)"
        return ("No one stands out yet. Mind links a person or a series after \(needed) meetings together; \(reading).", progress)
    }

    // MARK: - Mornings and afternoons

    /// Which half of the day runs higher, nil while one half has nothing.
    enum Lean: Equatable, Sendable { case mornings, afternoons, even }

    static func lean(_ halves: MindMeetingStress.Halves) -> Lean? {
        guard let morning = halves.morning, let afternoon = halves.afternoon, morning > 0 else { return nil }
        let ratio = afternoon / morning
        if ratio >= 1.2 { return .afternoons }
        if ratio <= 0.83 { return .mornings }
        return .even
    }

    /// The sentence over the two bars.
    static func halvesVerdict(_ halves: MindMeetingStress.Halves) -> String {
        guard let lean = lean(halves), let morning = halves.morning, let afternoon = halves.afternoon else {
            return halves.morning == nil ? "No morning meetings read yet" : "No afternoon meetings read yet"
        }
        switch lean {
        case .afternoons: return "Afternoons run \(Int(((afternoon / morning - 1) * 100).rounded()))% higher"
        case .mornings: return "Mornings run \(Int(((morning / afternoon - 1) * 100).rounded()))% higher"
        case .even: return "Mornings and afternoons run alike"
        }
    }
}
