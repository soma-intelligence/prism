//
//  ECGPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The latest ECG from Apple Watch: its heart rate on the metric stage with
/// the month's recordings, its rhythm, the trace itself, what the result means and cannot mean, and the recordings before
/// it.
///
/// ECG is read only here, and asked for when this page opens: never at launch.
/// The page states Apple's own limits plainly, because a rhythm strip read by a
/// watch is not a diagnosis.
struct ECGPage: View {
    @Environment(\.somaTheme) private var theme

    @State private var recordings: [FitnessHealthKit.Recording] = []
    @State private var trace: [Double] = []
    @State private var isLoaded = false

    private let reader = FitnessHealthKit()
    private var words: MetricWords { MetricWords() }

    var body: some View {
        let latest = recordings.first

        TabPartScaffold(
            aspect: .heart,
            eyebrow: latest.map { "Last recording, \(words.day($0.date))" } ?? "ECG",
            title: headline(latest),
            reason: reason(latest),
            stats: []
        ) {
            AspectStage(
                aspect: .heart,
                lead: SomaMetricLead(
                    caption: latest.map { "\(words.day($0.date)), \(words.time($0.date))" } ?? "Latest recording",
                    value: latest?.averageHeartRate.map(words.whole),
                    unit: "bpm average",
                    meaning: latest?.classification.rawValue ?? "No recording yet"
                ),
                values: Self.days(recordings, now: .now),
                unit: "bpm",
                scale: nil,
                higherIsBetter: nil,
                style: .points,
                format: { MetricWords().whole($0) }
            )
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.chartLabelGap * 2) {
                    Text("Trace, lead I")
                        .somaFont(theme.typography.eyebrow)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    ECGTrace(voltages: trace, samplingFrequency: latest?.samplingFrequency)
                }
            }
            .accessibilityHint(Text(latest.map { "\(Int($0.duration.rounded())) seconds." } ?? "Your next recording on Apple Watch draws its trace here."))
            MetricTextCard(eyebrow: "What it means", lead: meaning(latest).lead, rest: meaning(latest).rest)
            if recordings.count > 0 {
                MetricRowsCard(eyebrow: "Recent recordings", rows: recordings.map { recording in
                    MetricRowItem(
                        recording.classification.rawValue,
                        detail: "\(words.day(recording.date)), \(words.time(recording.date))",
                        value: recording.averageHeartRate.map { "\(words.whole($0)) bpm" },
                        id: recording.id.uuidString
                    )
                })
            }
            SomaActionCard(
                eyebrow: "Record",
                title: "Take another reading",
                detail: "Open ECG on your watch and rest a finger on the crown for 30 seconds. Health keeps a PDF of each one for your doctor."
            ) {
                PulseMiniOrb(aspect: .heart, diameter: theme.metrics.miniOrbDiameter)
            }
        }
        .navigationTitle("ECG")
        .task { await load() }
        .somaRefreshable { await load() }
    }

    /// The average heart rate of each day's last recording, the last thirty
    /// days, today last.
    static func days(_ recordings: [FitnessHealthKit.Recording], now: Date, calendar: Calendar = .current) -> [Double?] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: Double] = [:]
        for recording in recordings.sorted(by: { $0.date < $1.date }) {
            if let rate = recording.averageHeartRate { byDay[calendar.startOfDay(for: recording.date)] = rate }
        }
        return (0..<30).map { index in
            calendar.date(byAdding: .day, value: index - 29, to: today).flatMap { byDay[$0] }
        }
    }

    private func load() async {
        let found = await reader.recordings()
        recordings = found
        if let latest = found.first {
            trace = await reader.voltages(of: latest)
        }
        isLoaded = true
    }

    private func headline(_ latest: FitnessHealthKit.Recording?) -> String {
        guard let latest else {
            return isLoaded ? "No ECG recorded yet." : "Reading your ECG recordings."
        }
        switch latest.classification {
        case .sinusRhythm: return "Sinus rhythm: a steady, regular beat."
        case .atrialFibrillation: return "Signs of atrial fibrillation."
        case .lowHeartRate: return "Too slow to classify."
        case .highHeartRate: return "Too fast to classify."
        case .poorReading: return "The recording was too noisy to read."
        case .inconclusive, .unclassified: return "This recording couldn’t be classified."
        }
    }

    private func reason(_ latest: FitnessHealthKit.Recording?) -> String {
        guard let latest else {
            return isLoaded
                ? "Apple Watch records an ECG from the ECG app. Each one lands here, with its trace and its rhythm."
                : "Asking Health for your ECG recordings. They’re read on this device only."
        }
        let same = recordings.prefix(5).filter { $0.classification == latest.classification }.count
        var text = latest.averageHeartRate.map { "Thirty seconds at \(words.whole($0)) bpm." } ?? "Thirty seconds recorded."
        if recordings.count > 1 {
            text += " \(same) of your last \(min(5, recordings.count)) recordings read the same."
        }
        return text
    }

    private func meaning(_ latest: FitnessHealthKit.Recording?) -> (lead: String, rest: String) {
        let limits = "A watch ECG reads rhythm only. It can’t rule out a heart attack; if you feel unwell, call for help."
        switch latest?.classification {
        case .sinusRhythm?:
            return ("Sinus rhythm is the normal pattern: each beat set off in the right place, at a steady pace.", limits)
        case .atrialFibrillation?:
            return ("The upper chambers beat irregularly. Talk to your doctor about this result.", limits)
        case .lowHeartRate?:
            return ("Under 50 bpm the watch doesn’t classify the rhythm.", limits)
        case .highHeartRate?:
            return ("Over 150 bpm the watch doesn’t classify the rhythm.", limits)
        case .poorReading?, .inconclusive?, .unclassified?:
            return ("Rest your arm on a table and keep still for the 30 seconds, then record again.", limits)
        case nil:
            return ("An ECG shows the electrical signal that sets off each heartbeat.", limits)
        }
    }
}

/// A few seconds of the ECG voltage as one line, in the heart's hue. Draws a
/// flat baseline until there is a trace.
private struct ECGTrace: View {
    let voltages: [Double]
    let samplingFrequency: Double?

    @Environment(\.somaTheme) private var theme

    /// Seconds of the recording shown: enough for a few beats to read.
    private static let shownSeconds = 4.0

    var body: some View {
        let hue = theme.aspects[.heart].identity.color
        let hairline = theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)
        let count = samplingFrequency.map { Int($0 * Self.shownSeconds) } ?? 2048
        let start = max(0, voltages.count / 2 - count / 2)
        let shown = Array(voltages.dropFirst(start).prefix(count))

        Canvas { context, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height / 2))
            base.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(base, with: .color(hairline), lineWidth: 1)

            guard shown.count >= 2, let low = shown.min(), let high = shown.max(), high > low else { return }
            var line = Path()
            for (index, value) in shown.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(shown.count - 1)
                let y = size.height * (1 - CGFloat((value - low) / (high - low)))
                if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(line, with: .color(hue), style: StrokeStyle(lineWidth: theme.metrics.chartLineWidth * 0.75, lineJoin: .round))
        }
        .frame(height: theme.metrics.metricTraceHeight)
        .accessibilityLabel("ECG trace")
    }
}

#Preview("ECG") {
    NavigationStack { ECGPage() }
        .environment(HealthDashboard())
}
