//
//  TrackFastingView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Fasting: the fast is an arc on a 24 hour clock. Drag its start and its
/// end, or pick a length under the clock; the usual night sits inside the
/// track so the arc shows how much of the fast is slept through.
///
/// While a fast runs, the arc fills with the time already behind and the
/// action ends it. Kept in ``TrackLogStore``; Apple Health has no type for a
/// fast.
struct TrackFastingView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var startHour: Double
    @State private var length: Double
    @State private var window: (from: Double, to: Double)?

    private let log = TrackLogStore.shared
    private let calendar = Calendar.current

    init() {
        let now = Date()
        let calendar = Calendar.current
        let log = TrackLogStore.shared
        if let running = log.currentFast {
            _startHour = State(initialValue: TrackFasting.clockHour(running.start, calendar: calendar))
            _length = State(initialValue: running.objectiveHours ?? 16)
        } else {
            let nowHour = TrackFasting.clockHour(now, calendar: calendar)
            let usual = log.fasts.last.map { TrackFasting.clockHour($0.start, calendar: calendar) } ?? 20
            let hour = nowHour <= usual ? usual : nowHour
            _startHour = State(initialValue: TrackFasting.snapped(hour))
            _length = State(initialValue: log.fasts.last?.objectiveHours ?? 14)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .task { window = await TrackHealthReads.sleepWindow(from: health) }
    }

    private func content(now: Date) -> some View {
        let metrics = theme.metrics
        let running = log.currentFast
        let start = running?.start ?? plannedStart(now: now)
        let end = start.addingTimeInterval(length * 3600)

        return TrackEntryPage(title: "Fasting") {
            SomaDayClock(
                start: $startHour,
                length: $length,
                lengthRange: TrackFasting.lengthRange,
                snap: TrackFasting.snap,
                band: window,
                now: TrackFasting.clockHour(now, calendar: calendar),
                progress: running?.fraction(at: now),
                isEditable: running == nil
            ) {
                if let running {
                    let minutes = Int(running.elapsed(at: now) / 60)
                    SomaReadout("\(minutes / 60):" + String(format: "%02d", minutes % 60),
                                caption: running.goalEnd.map { "of \(lengthText) h, ends \(endText($0, now: now))" } ?? "Open fast")
                } else {
                    SomaReadout(lengthText, unit: "h", caption: "Ends \(endText(end, now: now))")
                }
            }
            .padding(.top, metrics.cardSpacing)

            if running == nil {
                HStack(spacing: metrics.spaceS) {
                    ForEach(TrackFasting.presets, id: \.self) { hours in
                        SomaChoiceChip("\(Int(hours)) h", isOn: length == hours) {
                            length = hours
                        }
                    }
                }
            }

            if let window {
                let slept = TrackFasting.overlap(start: start, hours: length, window: window, calendar: calendar)
                TrackNote(lead: slept > 0
                          ? "\(TrackFasting.length(slept)) of it inside your usual night."
                          : "None of it falls inside your usual night.")
            } else {
                TrackNote(lead: "Your usual night shows here after three nights of sleep in Apple Health.")
            }
        } footer: {
            if running != nil {
                VStack(spacing: metrics.cardSpacing) {
                    SomaActionButton("End the fast") {
                        log.endFast(at: .now)
                        dismiss()
                    }
                    Button("Started by mistake") {
                        log.cancelFast()
                        dismiss()
                    }
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                }
            } else {
                SomaActionButton(startsNow(now: now) ? "Start now" : "Start at \(TrackClock.hour(startHour))") {
                    let begin = startsNow(now: now) ? Date.now : plannedStart(now: now)
                    log.startFast(at: begin, objectiveHours: length, now: .now)
                    dismiss()
                }
            }
        }
    }

    private var lengthText: String {
        length == length.rounded() ? "\(Int(length))" : String(format: "%.1f", length)
    }

    private func plannedStart(now: Date) -> Date {
        TrackFasting.nextStart(at: startHour, from: now, calendar: calendar)
    }

    /// A start within a quarter hour either side of now is now.
    private func startsNow(now: Date) -> Bool {
        abs(plannedStart(now: now).timeIntervalSince(now)) <= 15 * 60
    }

    private func endText(_ date: Date, now: Date) -> String {
        let day = TrackClock.day(date, now: now, calendar: calendar)
        return day == "Today" ? "at \(TrackClock.time(date))" : "\(day) \(TrackClock.time(date))"
    }
}

#if DEBUG
#Preview("Fasting") {
    NavigationStack { TrackFastingView() }
        .environment(HealthDashboard())
}
#endif
