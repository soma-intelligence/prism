//
//  MindBreatheSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A breathing session: the mind orb breathing in for four seconds and out
/// for six, a countdown, and a way to stop. At the end it says how long it
/// ran.
///
/// The session lives only as long as the sheet: the Health source Soma reads
/// through cannot write, so nothing is saved to Apple Health yet, and the
/// done screen says so.
struct MindBreatheSheet: View {
    /// How long the session runs, in seconds.
    var length: TimeInterval = 10 * 60

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    /// Seconds breathed, once the session is over.
    @State private var finished: TimeInterval?

    /// One breath: in, then out.
    static let inhale: TimeInterval = 4
    static let exhale: TimeInterval = 6
    /// The orb's size at the bottom of a breath, against its full size.
    static let emptyScale: CGFloat = 0.78

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        NavigationStack {
            VStack(spacing: metrics.leadSpacing) {
                if let finished {
                    done(finished)
                } else {
                    session
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbar {
                if finished == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .tint(colors.inkPrimary.color)
        }
        .task(id: finished == nil) {
            guard finished == nil else { return }
            let remaining = length - Date().timeIntervalSince(startedAt)
            try? await Task.sleep(for: .seconds(max(0, remaining)))
            guard !Task.isCancelled, finished == nil else { return }
            finished = length
        }
    }

    // MARK: - The session

    private var session: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        return TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: finished != nil)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let breath = Self.breath(at: elapsed)

            VStack(spacing: metrics.leadSpacing) {
                Text("Breathe")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.top, metrics.heroTopPadding)

                Spacer(minLength: 0)

                SomaOrb(aspect: .mind, scale: .hero)
                    .scaleEffect(reduceMotion ? 1 : breath.scale)
                    .accessibilityHidden(true)

                Text(breath.isInhaling ? "Breathe in" : "Breathe out")
                    .somaFont(type.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.updatesFrequently)

                if reduceMotion {
                    Text("In for four, out for six.")
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                }

                Text(Self.clock(max(0, length - elapsed)))
                    .somaFont(type.metric)
                    .foregroundStyle(colors.inkSecondary.color)
                    .accessibilityLabel("Time left")
                    .accessibilityValue(Self.clock(max(0, length - elapsed)))

                Spacer(minLength: 0)

                Button {
                    finished = min(length, Date().timeIntervalSince(startedAt))
                } label: {
                    Text("End")
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget + 4)
                        .background(Capsule().fill(colors.surface.color))
                        .overlay(Capsule().strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
                        .contentShape(.capsule)
                }
                .buttonStyle(SomaGlassPressStyle())
            }
        }
    }

    // MARK: - Done

    private func done(_ seconds: TimeInterval) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let minutes = Int((seconds / 60).rounded())

        return VStack(spacing: metrics.heroSpacing) {
            Spacer(minLength: 0)
            SomaObjectIcon(aspect: .mind, size: .row)
            Text("Done")
                .somaFont(type.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
                Text(minutes >= 1 ? "\(minutes)" : "-")
                    .somaFont(type.display)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(minutes == 1 ? "minute" : "minutes")
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .accessibilityElement(children: .combine)
            Text(minutes >= 1
                 ? "Not saved to Apple Health: Soma does not write to it yet."
                 : "Under a minute, so nothing to count this time.")
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .somaFont(type.body)
                    .foregroundStyle(colors.onAccent.color)
                    .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget + 4)
                    .background(Capsule().fill(colors.accent.color))
                    .contentShape(.capsule)
            }
            .buttonStyle(SomaGlassPressStyle())
        }
    }

    // MARK: - Arithmetic

    /// Where a breath is at `elapsed` seconds: in or out, and the orb's scale,
    /// eased at both ends so the turn from in to out is soft.
    static func breath(at elapsed: TimeInterval) -> (isInhaling: Bool, scale: CGFloat) {
        let cycle = inhale + exhale
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let isInhaling = t < inhale
        let progress = isInhaling ? t / inhale : 1 - (t - inhale) / exhale
        let eased = 0.5 - 0.5 * cos(Double.pi * progress)
        return (isInhaling, emptyScale + (1 - emptyScale) * CGFloat(eased))
    }

    /// Seconds as minutes and seconds: 9:41.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}

#Preview("Breathe") {
    MindBreatheSheet(length: 30)
}
