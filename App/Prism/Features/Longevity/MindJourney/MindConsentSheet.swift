//
//  MindConsentSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Mind · consent: shown once, before the first thing a person tells Mind.
///
/// It names what Mind reads, lets State of Mind and the calendar be left
/// off, and keeps the answer on the phone (`MindStore`). Voice is listed and
/// marked as not there yet rather than offered as a switch that does nothing.
struct MindConsentSheet: View {
    /// Called with true once Mind is on, false for "Not now".
    let onDone: (Bool) -> Void

    @Environment(\.somaTheme) private var theme
    @State private var consent = MindStore.shared.consent
    @State private var confirmsDelete = false

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        MindSheetFrame(title: "", closeTitle: "Close") {
            SomaOrb(aspect: .mind, scale: .hero)
                .frame(maxWidth: .infinity, maxHeight: theme.metrics.orbDiameter * 0.7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 6) {
                MindEyebrow(text: "Mind · Your choice")
                Text("Before Mind starts listening.")
                    .somaFont(type.display)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                MindReasonText(text: "Mind turns your heart signals into stress, energy and mood, and learns from the words you give it. Choose what it may read. You can change this at any time from the Mind page.")
            }

            SomaCard {
                VStack(spacing: 0) {
                    row("Heart rate and HRV") {
                        Text("Needed")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    MindHairline()
                    row("State of Mind") { SomaSwitch("State of Mind", isOn: $consent.stateOfMind) }
                    MindHairline()
                    row("Calendar busy times") { SomaSwitch("Calendar busy times", isOn: $consent.calendar) }
                    MindHairline()
                    row("Voice, for Tell your day") {
                        Text("Not yet")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }

            MindReasonText(text: "Calendar gives Mind a meeting’s time and title, never its notes or who was invited. It only reads, on this device, and keeps no title. Mind’s own record stays on this device too.")

            if MindStore.shared.consent.isGiven {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Text("Delete what Mind keeps on this phone")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(colors.danger.color)
                        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete what Mind keeps?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        MindStore.shared.deleteAll()
                        onDone(false)
                    }
                } message: {
                    Text("Your feelings, check-ins and days in words go from this phone. What Apple Health holds stays there.")
                }
            }
        } footer: {
            VStack(spacing: 4) {
                MindQuietButton(title: "Not now") { onDone(false) }
                MindWideButton(title: "Turn on Mind") {
                    var given = consent
                    given.givenAt = Date()
                    given.voice = false
                    MindStore.shared.setConsent(given)
                    onDone(true)
                }
            }
        }
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: theme.metrics.minimumTapTarget + 4)
    }
}
