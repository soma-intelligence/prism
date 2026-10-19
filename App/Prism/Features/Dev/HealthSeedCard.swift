//
//  HealthSeedCard.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
#if canImport(HealthKit)
import SwiftUI
import SomaUI

/// The button that fills the Simulator's Health store.
///
/// Simulator debug builds only, and deliberately blunt about what it does: it
/// writes invented samples into the real store, which is fine on a Simulator
/// and is not what anyone wants on the phone in their pocket, so a device build
/// does not compile it at all.
struct HealthSeedCard: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var seeder = HealthSeeder()
    @State private var task: Task<Void, Never>?

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fake a month of Health")
                    .somaFont(theme.typography.title)
                    .foregroundStyle(theme.colors.inkPrimary.color)

                Text(explanation)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)

                if seeder.isRunning {
                    ProgressView(value: seeder.fraction)
                        .tint(theme.colors.accent.color)
                }

                if let line = resultLine {
                    Text(line)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: seed) {
                    Text(seeder.isRunning ? "Writing" : "Write \(HealthSeeder.days) days of samples")
                        .somaFont(theme.typography.title)
                        .foregroundStyle(theme.colors.onAccent.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(theme.colors.accent.color))
                        .contentShape(.capsule)
                }
                .buttonStyle(.somaGlassPress)
                .disabled(seeder.isRunning || !seeder.isAvailable)

                Button("Remove what was written", action: remove)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .disabled(seeder.isRunning || !seeder.isAvailable)
            }
        }
        .onDisappear { task?.cancel() }
    }

    private var explanation: LocalizedStringKey {
        seeder.isAvailable
        ? "Writes invented samples for every metric Apple Health lets an app write, across the last \(HealthSeeder.days) days, then reloads the pages from the store. Simulator debug builds only."
        : "This device has no Health store, so there is nothing to write into."
    }

    private var resultLine: LocalizedStringKey? {
        switch seeder.phase {
        case .idle:
            return nil
        case .authorizing:
            return "Waiting on the permission sheet. Turn the categories on, then allow."
        case .writing:
            return "Writing."
        case let .failed(message):
            return "Failed: \(message)"
        case let .done(summary):
            return done(summary)
        }
    }

    private func done(_ summary: HealthSeeder.Summary) -> LocalizedStringKey {
        var line = "\(summary.samples) samples across \(summary.metrics) metrics, and \(summary.workouts) workouts."
        if !summary.refused.isEmpty {
            line += " \(summary.refused.count) refused: \(summary.refused.prefix(4).joined(separator: ", "))."
        }
        return LocalizedStringKey(line)
    }

    private func seed() {
        task?.cancel()
        task = Task {
            await seeder.seed()
            await health.load()
        }
    }

    private func remove() {
        task?.cancel()
        task = Task {
            await seeder.removeSeeded()
            await health.load()
        }
    }
}

#Preview("Seed") {
    HealthSeedCard()
        .environment(HealthDashboard())
}
#endif
#endif
