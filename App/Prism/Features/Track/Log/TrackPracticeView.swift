//
//  TrackPracticeView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Journal value: a practice timed in minutes (cold plunge, sauna,
/// meditation) set on a segmented ring.
///
/// Logging it also taps the practice's Journal tag for the day, so "What
/// your tags do" starts measuring it; the dots count the sessions of the last
/// thirty days against the days the effects card needs. Meditation also
/// writes mindful minutes to Apple Health.
struct TrackPracticeView: View {
    let practice: TrackPractice

    @Environment(\.somaTheme) private var theme
    @Environment(JournalStore.self) private var journal
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Double

    private let log = TrackLogStore.shared
    /// Sessions the effects card wants before it states anything: its own
    /// minimum on each side, twice over, so the answer is not the first
    /// three days.
    private static let wanted = EffectMath.minimumDays * 2

    init(practice: TrackPractice) {
        self.practice = practice
        _minutes = State(initialValue: practice.usualMinutes)
    }

    var body: some View {
        let metrics = theme.metrics
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let count = log.practices(practice, since: since).count

        TrackEntryPage(title: practice.title, scrolls: false) {
            SomaArcDial(
                value: $minutes,
                range: 0...practice.maxMinutes,
                step: practice.maxMinutes > 10 ? 1 : 0.5,
                style: .ring(segments: practice.maxMinutes > 10 ? 15 : 10),
                aspect: practice == .sauna ? .activity : .mind,
                label: "Minutes"
            ) {
                SomaReadout(minutes > 0 ? SomaArcDial<EmptyView>.number(minutes) : nil, unit: "min")
            }
            .padding(.top, metrics.leadSpacing)

            TrackNote(lead: countLine(count))
        } footer: {
            SomaActionButton("Log \(SomaArcDial<EmptyView>.number(minutes)) \(minutes == 1 ? "minute" : "minutes")") {
                let now = Date.now
                log.logPractice(practice, minutes: minutes, at: now)
                if let tag = journal.addTag(practice.tagTitle), !journal.day(now).tags.contains(tag.id) {
                    journal.toggle(tag.id, on: now)
                }
                if practice == .meditation {
                    Task {
                        let reached = await TrackHealthWriter.saveMindful(minutes: minutes, endingAt: now)
                        Confirmations.shared.logged(practice.title, reachedHealth: reached)
                    }
                } else {
                    Confirmations.shared.done("\(practice.title) logged")
                }
                dismiss()
            }
            .disabled(minutes <= 0)
        }
    }

    private func countLine(_ count: Int) -> String {
        let noun = practice.title.lowercased()
        let sessions = count == 1 ? "One \(noun)" : "\(count.formatted(.number.grouping(.never))) sessions of \(noun)"
        if count == 0 { return "Nothing logged in 30 days. After \(Self.wanted), Soma can tell what it does to your nights." }
        if count >= Self.wanted { return "\(sessions) in 30 days. Its effect shows in the Journal." }
        return "\(sessions) in 30 days. After \(Self.wanted), Soma can tell what it does to your nights."
    }
}

#if DEBUG
#Preview("Cold plunge") {
    NavigationStack { TrackPracticeView(practice: .coldPlunge) }
        .environment(JournalStore(url: nil))
}
#endif
