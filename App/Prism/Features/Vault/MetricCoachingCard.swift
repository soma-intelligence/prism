//
//  MetricCoachingCard.swift
//  Prism
//
//  The Coaching card on a metric's page: which way is better, the zones with
//  the person's marker, the verdict, and what helps. The ranges, the age
//  band and the sources sit behind Details. The words come from
//  ``MetricCoaching``; this view lays them out.
//

import SwiftUI
import SomaUI

struct MetricCoachingCard: View {
    let advice: MetricCoachingAdvice

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                    Text("Coaching")
                        .somaFont(type.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    Text(advice.direction.title)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                }

                if !advice.zones.isEmpty {
                    SomaZoneBar(
                        zones: advice.zones.map { SomaZoneBar.Zone(name: $0.name, lower: $0.lower, upper: $0.upper, tone: tone($0.tone)) },
                        value: advice.marker
                    )
                }

                Text(advice.verdict)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)

                if let clinician = advice.clinician {
                    HStack(alignment: .firstTextBaseline, spacing: metrics.spaceS) {
                        Image(systemName: "stethoscope")
                            .accessibilityHidden(true)
                        Text(clinician)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .somaFont(type.callout)
                    .foregroundStyle(colors.statusOut.color)
                }

                if !advice.helps.isEmpty {
                    VStack(alignment: .leading, spacing: metrics.spaceXS) {
                        Text("What helps")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(advice.helps, id: \.self) { lever in
                            HStack(alignment: .firstTextBaseline, spacing: metrics.spaceS) {
                                Circle()
                                    .fill(colors.inkSecondary.color)
                                    .frame(width: metrics.timelineDotDiameter, height: metrics.timelineDotDiameter)
                                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + metrics.timelineDotDiameter / 2 }
                                Text(lever)
                                    .somaFont(type.callout)
                                    .foregroundStyle(colors.inkPrimary.color)
                            }
                        }
                    }
                }

                details
            }
        }
    }

    /// The ranges and the sources, one tap away.
    @ViewBuilder
    private var details: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let lines = [advice.targetLine, advice.usualLine].compactMap { $0 }.filter { !$0.isEmpty }

        Button {
            if reduceMotion { showsDetails.toggle() } else {
                withAnimation(theme.motion.fold) { showsDetails.toggle() }
            }
        } label: {
            HStack(spacing: metrics.spaceS) {
                Text("Details")
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkSecondary.color)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .rotationEffect(.degrees(showsDetails ? 180 : 0))
            }
            .frame(minHeight: metrics.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
        .accessibilityValue(Text(showsDetails ? "Shown" : "Hidden"))

        if showsDetails {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Source: \(advice.source). Not medical advice.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity)
        }
    }

    private func tone(_ tone: MetricCoachingAdvice.Tone) -> SomaZoneBar.Tone {
        switch tone {
        case .good: .good
        case .fair: .fair
        case .out: .out
        }
    }
}

extension MetricCoaching.Person {
    /// The person as the app knows them: the profile first, what the
    /// screening ledger asked or Health holds for the gaps, then the sex
    /// given for the cardiometabolic risk.
    static func current(now: Date = .now) -> MetricCoaching.Person {
        let profile = ScreeningReminders.profile(now: now)
        let sex = profile.sex ?? CardiometabolicProfileStore.shared.profile.sex.map { $0 == .male ? BiologicalSex.male : .female }
        return MetricCoaching.Person(age: profile.age(on: now), sex: sex)
    }
}
