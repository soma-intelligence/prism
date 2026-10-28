//
//  HomeWalkLiveView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// An easy walk, live, over the whole screen: the time walked, distance,
/// heart rate and steps, the heart against an easy band, and Pause or End.
/// Before it starts it says what it records; where it cannot run it says why.
struct HomeWalkLiveView: View {
    let targetMinutes: Int

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = HomeWalkSession()
    @State private var age: Int?
    @Environment(HealthDashboard.self) private var health

    var body: some View {
        let metrics = theme.metrics

        NavigationStack {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        HomeEyebrow(eyebrow)
                        Text(clock(session.elapsed(at: context.date)))
                            .somaFont(theme.typography.display)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        Text("elapsed")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                    .frame(maxWidth: .infinity)
                }

                SomaStatRow([
                    SomaStat("Kilometres", value: session.distanceMetres.map { HomeFormat.decimal($0 / 1000) }),
                    SomaStat("Heart rate", value: session.heartRate.map { HomeFormat.whole($0) }),
                    SomaStat("Steps", value: session.steps.map { HomeFormat.whole($0) }),
                ])

                SomaChartCard(eyebrow: "Heart rate, this walk", value: nil, note: bandNote) {
                    if session.heartSeries.count > 1 {
                        HomeTrendChart(values: session.heartSeries.map { Optional($0) }, band: band, aspect: .heart, axis: ["Start", "Now"])
                            .padding(.top, theme.metrics.spaceS)
                    }
                }

                HomeReason(message)

                Spacer(minLength: 0)

                controls
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(maxWidth: .infinity)
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle("Walk")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        Task {
                            if session.phase == .running || session.phase == .paused { await session.end() }
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task { age = health.today?.age }
    }

    @ViewBuilder
    private var controls: some View {
        switch session.phase {
        case .ready, .starting:
            HomePrimaryButton(session.phase == .starting ? "Starting" : "Start walk", isEnabled: session.phase == .ready) {
                Task { await session.start() }
            }
        case .running, .paused:
            HStack(spacing: theme.metrics.cardSpacing) {
                HomeSecondaryButton(session.phase == .paused ? "Resume" : "Pause") {
                    session.phase == .paused ? session.resume() : session.pause()
                }
                HomePrimaryButton("End walk") { Task { await session.end() } }
            }
        case .saved, .unavailable:
            HomePrimaryButton("Done") { dismiss() }
        }
    }

    private var eyebrow: String {
        switch session.phase {
        case .ready, .starting, .unavailable: "Easy walk · \(targetMinutes) min"
        case .running, .paused, .saved:
            session.startDate.map { "Easy walk · since \(HomeFormat.clock($0))" } ?? "Easy walk"
        }
    }

    /// The easy band: 50 to 60 percent of the age-predicted maximum.
    private var band: ClosedRange<Double>? {
        guard let age, age > 0 else { return nil }
        let maximum = Double(220 - age)
        return (maximum * 0.5).rounded()...(maximum * 0.6).rounded()
    }

    private var bandNote: String {
        guard let band else { return "The easy band needs your date of birth in Apple Health." }
        return "Easy band, \(HomeFormat.whole(band.lowerBound)) to \(HomeFormat.whole(band.upperBound))."
    }

    private var message: String {
        switch session.phase {
        case .ready:
            "Easy is the point. Keep your heart inside the band and your breath slow; it lowers stress without adding to today’s strain. Soma records the walk to Apple Health."
        case .starting: "Asking Apple Health to record the walk."
        case .running: "Easy is the point. Keep your heart inside the band and your breath slow."
        case .paused: "Paused. The clock waits for you."
        case .saved: "Saved to Apple Health as a walk. It shows on Today with the rest of your day."
        case .unavailable(let why): why
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
