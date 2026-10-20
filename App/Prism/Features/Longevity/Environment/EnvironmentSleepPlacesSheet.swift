//
//  EnvironmentSleepPlacesSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
#if os(iOS)
import UIKit
#endif

/// What the Sleep places tile opens: the place in question on its map, and
/// the one thing it needs. A new place asks whether you sleep there: call it
/// Home, give it a name, or forget it. A named place can be renamed or
/// forgotten. Under them the places, the way to let the phone find them on
/// its own (Location set to Always, explained first), and nights by hand.
struct SleepPlacesSheet: View {
    let scores: SomaScores?
    let inputs: ScoreDetailInputs?

    @State private var finder = SleepPlaceFinder.shared
    @State private var monitor = SleepVisitMonitor.shared
    /// The place picked from the list; else the one waiting for a name.
    @State private var picked: String?
    @State private var naming = false
    @State private var draft = ""
    @State private var forgetting: SleepPlaceCluster?
    @State private var showsLedger = false
    @State private var answered = 0
    @FocusState private var fieldFocused: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Row: Identifiable { let id: String }

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let places = finder.places
        let focus = places.first { $0.id == picked } ?? finder.pending
        let heat = finder.heat(around: focus)
        let shape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)

        ScoreSheet(eyebrow: "Environment · Sleep", title: "Where you sleep") {
            Group {
                if heat.points.isEmpty {
                    Image(systemName: "bed.double")
                        .somaFont(theme.typography.metricCompact)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colors.surfaceRecessed.color)
                } else {
                    SomaHeatMap(points: heat.points, framing: heat.framing)
                }
            }
            .frame(height: metrics.heatMapHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))

            if let focus {
                editor(focus, offersHome: !places.contains { $0.name == String(localized: "Home") })
            }

            if !places.isEmpty {
                SomaBrowseGroup(places, hasGlyphs: false) { place in
                    SomaBrowseRow(title: place.name ?? String(localized: "New place"), detail: nil,
                                  action: { pick(place) }) {
                        Text(verbatim: EnvironmentSleepPlacesCard.nights(place.nights.count))
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }

            if monitor.access != .always, monitor.access != .unavailable {
                access
            }

            SomaBrowseGroup([Row(id: "byHand")], hasGlyphs: false) { _ in
                SomaBrowseRow(title: String(localized: "Set nights by hand"), action: { showsLedger = true }) {
                    EmptyView()
                }
            }

            ScoreFootnote(text: "Places stay on this phone.")
        }
        .sensoryFeedback(.success, trigger: answered)
        .confirmationDialog("Forget this place?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { place in
            Button("Forget", role: .destructive) {
                withAnimation(reduceMotion ? nil : theme.motion.selection) {
                    finder.forget(place)
                    done()
                }
            }
        } message: { _ in
            Text("Its nights go too.")
        }
        .sheet(isPresented: $showsLedger) { SleepPlaceLedgerSheet(scores: scores, inputs: inputs) }
    }

    // MARK: Parts

    /// The place's question and its answers.
    /// Home is offered while no place carries that name.
    private func editor(_ place: SleepPlaceCluster, offersHome: Bool) -> some View {
        let type = theme.typography
        let colors = theme.colors

        return SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: place.name ?? String(localized: "Is this where you sleep?"))
                        .somaFont(type.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Text(verbatim: EnvironmentSleepPlacesCard.nights(place.nights.count))
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }

                if naming {
                    HStack(spacing: 8) {
                        TextField("Name", text: $draft)
                            .somaFont(type.body)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                            .onSubmit { save(place, draft) }
                            .padding(.horizontal, 14)
                            .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                            .background(Capsule().fill(colors.surfaceRecessed.color))
                        capsule("Save", filled: true) { save(place, draft) }
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    HStack(spacing: 8) {
                        if offersHome {
                            capsule("Home", filled: true) { save(place, String(localized: "Home")) }
                        }
                        capsule(place.isConfirmed ? "Rename" : (offersHome ? "Other name" : "Name it"), filled: !offersHome) {
                            draft = place.name ?? ""
                            withAnimation(reduceMotion ? nil : theme.motion.selection) { naming = true }
                            fieldFocused = true
                        }
                        Spacer(minLength: 0)
                        Button { forgetting = place } label: {
                            Text("Forget it")
                                .somaFont(type.callout)
                                .foregroundStyle(colors.inkSecondary.color)
                                .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPress)
                    }
                }
            }
        }
    }

    /// Location set to Always, said plainly before it is asked.
    private var access: some View {
        let type = theme.typography
        let colors = theme.colors

        return SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                Text("Find them on its own")
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                Text("With Location set to Always, your phone notes where it stays overnight, and Soma matches that to your sleep. It all stays on this phone. Without it, set your nights by hand.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if monitor.askedAlways || monitor.access == .denied {
                    capsule("Open Settings", filled: false) { openSettings() }
                } else {
                    capsule("Allow Always", filled: true) { monitor.requestAlways() }
                }
            }
        }
    }

    private func capsule(_ title: LocalizedStringResource, filled: Bool, action: @escaping () -> Void) -> some View {
        let colors = theme.colors
        return Button(action: action) {
            Text(title)
                .somaFont(theme.typography.callout)
                .foregroundStyle(filled ? colors.onAccent.color : colors.inkPrimary.color)
                .padding(.horizontal, 16)
                .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                .background(Capsule().fill(filled ? colors.accent.color : colors.surfaceRecessed.color))
        }
        .buttonStyle(.somaGlassPress)
    }

    // MARK: Actions

    private func pick(_ place: SleepPlaceCluster) {
        withAnimation(reduceMotion ? nil : theme.motion.selection) {
            picked = place.id
            naming = false
        }
    }

    private func save(_ place: SleepPlaceCluster, _ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(reduceMotion ? nil : theme.motion.selection) {
            finder.name(place, name)
            done()
        }
    }

    private func done() {
        picked = nil
        naming = false
        draft = ""
        fieldFocused = false
        answered += 1
    }

    private func openSettings() {
#if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
#endif
    }
}
