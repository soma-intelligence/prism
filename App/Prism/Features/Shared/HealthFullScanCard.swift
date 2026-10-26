//
//  HealthFullScanCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Asks Apple Health for the whole catalog and reports what came back.
///
/// This is the one place allowed to request the sensitive metrics, because the
/// person pressed a button that says what it will do. The launch sheet still
/// never names them.
struct HealthFullScanCard: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var task: Task<Void, Never>?

    /// What the button actually reads, so the label and the counter agree.
    ///
    /// The request is wider than the sweep: it names every readable type,
    /// including the workout type and the characteristics, which are authorized
    /// but are not read as a single value.
    private var metricCount: Int { HealthDashboard.scannableMetrics.count }

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Everything in Apple Health")
                    .somaFont(theme.typography.title)
                    .foregroundStyle(theme.colors.inkPrimary.color)

                Text(explanation)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)

                if let scan = health.scan {
                    progress(scan)
                }

                Button(action: toggle) {
                    Text(isRunning ? "Stop" : "Read all \(metricCount) metrics")
                        .somaFont(theme.typography.title)
                        .foregroundStyle(theme.colors.onAccent.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.spaceM)
                        .background(
                            Capsule().fill(theme.colors.accent.color)
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(.somaGlassPress)
                .disabled(!health.isAvailable)
            }
        }
        .onDisappear { task?.cancel() }
    }

    private var isRunning: Bool { health.scan?.isRunning == true }

    private var explanation: LocalizedStringKey {
        health.isAvailable
        ? "Asks for read access to every type Apple Health can hand over, including the cycle tracking the launch sheet deliberately leaves out, then reads each one to see what the store actually holds."
        : "This device has no Health store, so there is nothing to read. The same button works on iPhone and iPad."
    }

    private func toggle() {
        if isRunning {
            task?.cancel()
            health.setScan(nil)
            task = nil
        } else {
            task = Task { await health.scanEverything() }
        }
    }

    @ViewBuilder
    private func progress(_ scan: HealthFullScan) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
            ProgressView(value: scan.fraction)
                .tint(theme.colors.accent.color)

            HStack(spacing: 4) {
                Text("\(scan.scanned)")
                    .somaFont(theme.typography.metric)
                Text("of \(scan.total) read")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            .foregroundStyle(theme.colors.inkPrimary.color)

            Text(resultLine(scan))
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
    }

    private func resultLine(_ scan: HealthFullScan) -> LocalizedStringKey {
        if scan.isRunning {
            return "Reading."
        }
        if scan.withData == 0 {
            return "The store held nothing for any of them. On a Simulator that is expected: there is no health data to read."
        }
        return "\(scan.withData) of \(scan.total) came back with a value."
    }
}
