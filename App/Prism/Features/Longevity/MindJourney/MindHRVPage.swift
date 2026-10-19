//
//  MindHRVPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Metric · HRV: today against the baseline, the last thirty days as their
/// distance from it, what moves it, and where today sits among the days.
///
/// Daily HRV is the mean of the day's SDNN readings from Apple Health; the
/// baseline is the median of the days before, the usual range their middle
/// half.
struct MindHRVPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?
    @State private var extras = MindJourneyExtras()
    @State private var isBreathing = false

    var body: some View {
        let calendar = Calendar.current
        let words = PulseWording(calendar: calendar, locale: .current)
        let base = inputs ?? MindInputs(now: Date())
        let signals = MindSignals.make(
            heartRateVariability: base.heartRateVariability, restingHeartRate: base.restingHeartRate,
            respiratory: extras.respiratory, sleep: base.sleep, peaks: base.today?.peaks ?? [],
            now: base.now, calendar: calendar, words: words
        )
        let today = calendar.startOfDay(for: base.now)
        let days: [Double?] = (0..<30).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today), let baseline = signals.hrvBaseline else { return nil }
            return signals.hrvByDay[day].map { $0 - baseline }
        }
        let late = lateDinners(calendar: calendar, today: today)
        let values = signals.hrvByDay.values.sorted()
        let rank = signals.hrvToday.map { now in values.filter { $0 > now }.count }

        MindPage(
            navigationTitle: "HRV",
            title: headline(signals),
            stats: [
                SomaStat("Now", value: MindFormat.whole(signals.hrvToday), trend: MindMath.trend(signals.hrvToday, against: signals.hrvBaseline, by: (signals.hrvBaseline ?? 0) * 0.07)),
                SomaStat("Last night", value: MindFormat.whole(signals.hrvLastNight)),
                SomaStat("Baseline", value: MindFormat.whole(signals.hrvBaseline)),
            ]
        ) {
            SomaChartCard(
                eyebrow: "HRV · last 30 days",
                value: MindFormat.whole(signals.hrvToday),
                unit: "ms",
                note: signals.hrvBaseline == nil
                    ? "The baseline needs five days of HRV. A watch worn through the night records it."
                    : "Each day against your \(words.whole(signals.hrvBaseline ?? 0)) ms baseline. The band is your usual range."
            ) {
                MindDeviationChart(values: days, usual: signals.hrvUsual.flatMap { usual in signals.hrvBaseline.map { (usual.lowerBound - $0)...(usual.upperBound - $0) } })
            }

            MindRowsCard(title: "What moves it", caption: "Against your usual", rows: [
                signals.resting, signals.breathing, signals.peaks, signals.sleep,
                MindSignalRow(kind: .lateMeals, title: "Late dinners", detail: "\(late) of the last 4 nights", value: "\(late)", isCost: late >= 2, number: nil, usual: nil),
            ]) { MindSignalRowView(row: $0) }

            SomaChartCard(
                eyebrow: "Where today sits",
                value: MindFormat.whole(signals.hrvToday),
                unit: "ms",
                note: rank.map { values.count >= MindUsual.minimumDays ? "Lower than \($0) of your last \(values.count) days." : "A few more days place today among the others." } ?? "Today has no HRV reading yet."
            ) {
                SomaNightBars(aspect: .mind, values: histogram(values))
                    .frame(height: theme.metrics.aspectChartHeight * 1.4)
            }

            SomaActionCard(
                eyebrow: "Right now",
                title: "Breathe for 10 minutes",
                detail: signals.hrvBaseline.map { "Brings your HRV back toward \(words.whole($0)) ms." } ?? "Ten slow minutes. Soma measures what they do for you.",
                actionTitle: "Start",
                action: { isBreathing = true }
            ) {
                SomaOrb(aspect: .mind, scale: .mini)
            }
        }
        .task {
            async let more = MindJourneyLoad.extras(health)
            inputs = await MindLoad.inputs(health)
            extras = await more
        }
        .sheet(isPresented: $isBreathing) { MindBreatheSession() }
    }

    private func headline(_ signals: MindSignals) -> String {
        switch MindUsual.place(signals.hrvToday, in: signals.hrvUsual) {
        case .under?: "Under your usual range."
        case .over?: "Above your usual range."
        case .inside?:
            (signals.hrvToday ?? 0) < (signals.hrvBaseline ?? 0) ? "A little under your baseline." : "At or above your baseline."
        case nil: "Your HRV."
        }
    }

    private func lateDinners(calendar: Calendar, today: Date) -> Int {
        let days = journal.dates(tagged: "late-meal")
        return (1...4).filter { offset in
            days.contains(calendar.date(byAdding: .day, value: -offset, to: today) ?? today)
        }.count
    }

    /// Days counted into eight bins from the lowest to the highest.
    private func histogram(_ sorted: [Double]) -> [Double?] {
        guard let low = sorted.first, let high = sorted.last, high > low else { return [] }
        var bins = Array(repeating: 0.0, count: 8)
        for value in sorted {
            bins[min(7, Int((value - low) / (high - low) * 8))] += 1
        }
        return bins.map { $0 }
    }
}

/// Daily values as their distance from the baseline: a thin stem and a dot
/// each, filled above it and hollow below, over the usual band in faint green.
struct MindDeviationChart: View {
    let values: [Double?]
    let usual: ClosedRange<Double>?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.mind].identity.color
        let known = values.compactMap { $0 } + [usual?.lowerBound, usual?.upperBound].compactMap { $0 }
        let reach = max(known.map(abs).max() ?? 1, 1) * 1.15
        let values = values
        let usual = usual

        SomaPlot(scale: SomaPlotScale(values: [-reach, reach], desired: 3),
                 label: { $0.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false))) }) { context, space, pen in
            if let usual {
                pen.band(context, top: space.y(usual.upperBound), bottom: space.y(usual.lowerBound), in: space.plot)
            }
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let x = space.x(index, of: values.count)
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: space.y(0)))
                stem.addLine(to: CGPoint(x: x, y: space.y(value)))
                context.stroke(stem, with: .color(hue.opacity(0.7)), lineWidth: 1)
                pen.dot(context, at: CGPoint(x: x, y: space.y(value)), color: hue, filled: value >= 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("HRV against baseline, last 30 days")
        .accessibilityValue("Filled dots are above the baseline, hollow ones below")
    }
}
