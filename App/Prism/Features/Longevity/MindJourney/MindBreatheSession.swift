//
//  MindBreatheSession.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Breathe · in session, then Breathe · done.
///
/// The mind orb breathes in for four seconds and out for six inside a ring
/// that fills with the session. HRV now is the latest HRV Apple Health holds
/// from the last hour, a dash until a watch records one. At the end the
/// session is saved as mindful minutes, and HRV and heart rate from before
/// are set against what came during and after.
struct MindBreatheSession: View {
    /// How long the session runs, in seconds.
    var length: TimeInterval = 10 * 60

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    /// Seconds breathed before the last pause.
    @State private var banked: TimeInterval = 0
    /// When the current stretch started; nil while paused.
    @State private var runningSince: Date? = Date()
    @State private var finished: TimeInterval?
    @State private var before = MindBreatheReading()
    @State private var after = MindBreatheReading()
    @State private var hrvNow: Double?
    @State private var savedToHealth: Bool?
    @State private var isLogging = false

    var body: some View {
        NavigationStack {
            Group {
                if let finished {
                    done(finished)
                } else {
                    session
                }
            }
            .padding(.horizontal, theme.metrics.pagePadding)
            .padding(.bottom, theme.metrics.pagePadding)
            .frame(maxWidth: theme.metrics.pageMaxWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle("Breathe")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .tint(theme.colors.inkPrimary.color)
        }
        .task { await readBefore() }
        .task(id: runningSince) {
            guard let runningSince, finished == nil else { return }
            let remaining = length - banked - Date().timeIntervalSince(runningSince)
            try? await Task.sleep(for: .seconds(max(0, remaining)))
            guard !Task.isCancelled, self.runningSince != nil, finished == nil else { return }
            await finish(at: length)
        }
        .sheet(isPresented: $isLogging) { MindEmotionLogSheet() }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        banked + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    // MARK: - In session

    private var session: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color
        let isPaused = runningSince == nil

        return TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: isPaused)) { context in
            let seconds = min(length, elapsed(at: context.date))
            let breath = MindBreatheSheet.breath(at: seconds)

            VStack(spacing: metrics.leadSpacing) {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 1)
                    Circle()
                        .trim(from: 0, to: seconds / length)
                        .stroke(hue, style: StrokeStyle(lineWidth: metrics.chartLineWidth + 1, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    SomaOrb(aspect: .mind, scale: .hero)
                        .scaleEffect(reduceMotion || isPaused ? 1 : breath.scale)
                        .padding(metrics.cardPadding)
                }
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(isPaused ? "Paused" : (breath.isInhaling ? "Breathe in" : "Breathe out"))
                        .somaFont(type.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.updatesFrequently)
                    Text("Four seconds in, six out.")
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                }

                MindHairline()

                SomaStatRow([
                    SomaStat("HRV now", value: hrvNow.map { MindFormat.whole($0) ?? "-" }, unit: "ms"),
                    SomaStat("Time left", value: MindBreatheSheet.clock(max(0, length - seconds))),
                ])

                Spacer(minLength: 0)

                MindWideButton(title: isPaused ? "Resume" : "Pause", isPrimary: false) {
                    if let since = runningSince {
                        banked += Date().timeIntervalSince(since)
                        runningSince = nil
                    } else {
                        runningSince = Date()
                    }
                }
                MindQuietButton(title: "End now") {
                    Task { await finish(at: elapsed(at: Date())) }
                }
            }
        }
        .task(id: "hrv") {
            while !Task.isCancelled, finished == nil {
                hrvNow = await latestHRV(since: Date().addingTimeInterval(-60 * 60))
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - Done

    private func done(_ seconds: TimeInterval) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let minutes = Int((seconds / 60).rounded())
        let eased = (after.hrv ?? 0) > (before.hrv ?? .infinity)

        return SomaPageScroll {
            VStack(spacing: metrics.leadSpacing) {
                SomaOrb(aspect: .mind, scale: .hero)
                    .frame(maxHeight: metrics.orbDiameter)
                    .padding(.top, metrics.heroTopPadding)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(minutes < 1 ? "Under a minute." : (eased ? "Your nervous system eased." : "Done: \(minutes) minutes."))
                        .somaFont(type.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    MindReasonText(text: summary(minutes: minutes))
                        .multilineTextAlignment(.center)
                }

                if before.hrv != nil || before.heartRate != nil {
                    MindRowsCard(title: "Before and after", rows: rows) { row in
                        MindBeforeAfterRow(row: row)
                    }
                    Text("Hollow is before, filled is after.")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                MindQuietButton(title: "Log how it felt") { isLogging = true }
                MindWideButton(title: "Done") { dismiss() }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var rows: [MindBeforeAfter] {
        [
            MindBeforeAfter(id: "hrv", title: "HRV", unit: "ms", before: before.hrv, after: after.hrv, higherIsBetter: true),
            MindBeforeAfter(id: "hr", title: "Heart rate", unit: "bpm", before: before.heartRate, after: after.heartRate, higherIsBetter: false),
        ]
    }

    private func summary(minutes: Int) -> String {
        guard minutes >= 1 else { return "Nothing to count this time. A few minutes are enough to show on your heart." }
        var sentences: [String] = []
        if let a = before.hrv, let b = after.hrv {
            let way = b >= a ? "rose" : "fell"
            sentences.append("HRV \(way) from \(Int(a.rounded())) to \(Int(b.rounded())) ms in \(minutes) minutes.")
        } else {
            sentences.append("\(minutes) minutes of slow breathing.")
        }
        if let a = before.heartRate, let b = after.heartRate, Int((a - b).rounded()) != 0 {
            let gap = Int((a - b).rounded())
            sentences.append(gap > 0 ? "Your heart rate fell by \(gap)." : "Your heart rate rose by \(-gap).")
        } else if after.hrv == nil {
            sentences.append("A watch worn during the session shows what it did to your heart.")
        }
        switch savedToHealth {
        case true?: sentences.append("Saved to Apple Health as mindful minutes.")
        case false?: sentences.append("Not saved to Apple Health: Soma was not allowed to write there.")
        case nil: break
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Reading

    private func finish(at seconds: TimeInterval) async {
        runningSince = nil
        finished = seconds
        let end = Date()
        if seconds >= 60 {
            savedToHealth = await MindHealthBridge.saveMindful(from: end.addingTimeInterval(-seconds), to: end)
        }
        // A watch writes HRV a little after the fact: read a short while on.
        after = await read(from: end.addingTimeInterval(-seconds), to: end.addingTimeInterval(15 * 60), heartFrom: end.addingTimeInterval(-min(seconds, 5 * 60)))
    }

    private func readBefore() async {
        startedAt = Date()
        before = await read(from: startedAt.addingTimeInterval(-2 * 60 * 60), to: startedAt, heartFrom: startedAt.addingTimeInterval(-10 * 60))
        hrvNow = before.hrv
    }

    private func read(from start: Date, to end: Date, heartFrom: Date) async -> MindBreatheReading {
        guard let source = await health.prepare([MindInputs.Metric.heartRate, MindInputs.Metric.heartRateVariability]),
              let hrvMetric = HealthMetricCatalog.metric(for: MindInputs.Metric.heartRateVariability),
              let hrMetric = HealthMetricCatalog.metric(for: MindInputs.Metric.heartRate) else { return MindBreatheReading() }
        let hrv = (try? await source.samples(hrvMetric, from: start, to: end, limit: 0)) ?? []
        let heart = (try? await source.samples(hrMetric, from: heartFrom, to: min(end, Date()), limit: 0)) ?? []
        return MindBreatheReading(
            hrv: hrv.max { $0.end < $1.end }?.value,
            heartRate: MindUsual.mean(heart.map(\.value))
        )
    }

    private func latestHRV(since start: Date) async -> Double? {
        guard let source = await health.prepare([MindInputs.Metric.heartRateVariability]),
              let metric = HealthMetricCatalog.metric(for: MindInputs.Metric.heartRateVariability) else { return nil }
        return ((try? await source.samples(metric, from: start, to: Date(), limit: 0)) ?? []).max { $0.end < $1.end }?.value
    }
}

/// HRV and heart rate around a session.
struct MindBreatheReading: Equatable {
    var hrv: Double?
    var heartRate: Double?
}

struct MindBeforeAfter: Identifiable {
    var id: String
    var title: String
    var unit: String
    var before: Double?
    var after: Double?
    var higherIsBetter: Bool
}

/// One reading before and after: hollow dot before, filled dot after.
struct MindBeforeAfterRow: View {
    let row: MindBeforeAfter

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let text: String = switch (row.before, row.after) {
        case let (a?, b?): "\(Int(a.rounded())) to \(Int(b.rounded())) \(row.unit)"
        case let (a?, nil): "\(Int(a.rounded())) to - \(row.unit)"
        default: "-"
        }
        HStack {
            Text(row.title)
                .somaFont(type.body)
                .foregroundStyle(colors.inkPrimary.color)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(text)
                    .somaFont(type.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
                if let a = row.before, let b = row.after {
                    MindTwoDots(before: a, after: b)
                        .frame(width: theme.metrics.aspectChartWidth)
                }
            }
        }
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// Two values on one track: before hollow, after filled.
struct MindTwoDots: View {
    let before: Double
    let after: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let low = min(before, after)
        let high = max(before, after)
        let pad = max((high - low) * 0.8, 2)
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY = proxy.size.height / 2
            let dot = metrics.chartEstimateDiameter
            let x: (Double) -> CGFloat = { v in width * CGFloat((v - (low - pad)) / (high - low + 2 * pad)) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(colors.surfaceRecessed.color)
                    .frame(width: width, height: metrics.chartTrackHeight)
                    .offset(y: midY - metrics.chartTrackHeight / 2)
                Circle().strokeBorder(colors.inkPrimary.color, lineWidth: 1.5)
                    .background(Circle().fill(colors.surface.color))
                    .frame(width: dot, height: dot)
                    .offset(x: x(before) - dot / 2, y: midY - dot / 2)
                Circle().fill(colors.inkPrimary.color)
                    .frame(width: dot, height: dot)
                    .offset(x: x(after) - dot / 2, y: midY - dot / 2)
            }
        }
        .frame(height: metrics.chartEstimateDiameter + 4)
        .accessibilityHidden(true)
    }
}
