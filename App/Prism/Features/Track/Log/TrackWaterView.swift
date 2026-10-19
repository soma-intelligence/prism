//
//  TrackWaterView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Water, add a drink: the glass is the control. Drag it up to pour, or pick
/// one of the usual glasses under it; the day's glasses fill along the foot.
///
/// Saved to Apple Health as dietary water, with the caffeine of a coffee or a
/// tea as dietary caffeine, and kept in ``TrackLogStore`` with its time so the
/// caffeine model can read it.
struct TrackWaterView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var drink: TrackDrink
    @State private var ml: Double

    private let log = TrackLogStore.shared

    init(initial: TrackDrink = .water) {
        _drink = State(initialValue: initial)
        _ml = State(initialValue: initial.usual)
    }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let logged = log.waterMl(on: .now)
        let today = logged ?? 0
        let goal = log.waterGoalMl

        TrackEntryPage(title: drink.title, scrolls: false) {
            SomaVesselInput(value: $ml, capacity: drink.capacity, step: drink.step, aspect: aspect, label: drink.title)
                .frame(height: metrics.vesselHeight)

            SomaReadout("\(Int(ml))", unit: "ml",
                        caption: drink == .water ? nil : "\(Int(drink.caffeine(ml: ml))) mg caffeine")

            HStack(spacing: metrics.cardSpacing * 0.5) {
                ForEach(drink.presets, id: \.self) { preset in
                    Button {
                        ml = preset
                    } label: {
                        VStack(spacing: metrics.scoreLabelSpacing * 2) {
                            SomaVessel(fill: preset / drink.capacity * 1.6, aspect: aspect, isGlyph: true)
                                .frame(height: metrics.vesselGlyphHeight * (0.7 + 0.6 * preset / drink.capacity))
                            Text("\(Int(preset)) ml")
                                .somaFont(type.captionValue)
                                .foregroundStyle(ml == preset ? colors.accent.color : colors.inkSecondary.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget * 1.6, alignment: .bottom)
                        .padding(.vertical, metrics.cardSpacing * 0.5)
                        .background {
                            if ml == preset {
                                RoundedRectangle(cornerRadius: metrics.browseGroupCornerRadius, style: .continuous)
                                    .fill(colors.surface.color)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPress)
                    .accessibilityLabel(Text("\(Int(preset)) millilitres"))
                    .accessibilityAddTraits(ml == preset ? .isSelected : [])
                }
            }

            VStack(spacing: metrics.cardSpacing * 0.75) {
                HStack {
                    TrackEyebrow("Today")
                    Spacer()
                    Text(logged == nil ? "Goal \(TrackIntake.litres(goal)) L" : "\(TrackIntake.litres(today)) of \(TrackIntake.litres(goal)) L")
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                HStack(spacing: metrics.cardSpacing * 0.75) {
                    ForEach(Array(TrackIntake.glasses(total: today, goal: goal).enumerated()), id: \.offset) { _, fill in
                        SomaVessel(fill: fill, aspect: .mind, isGlyph: true)
                            .frame(height: metrics.vesselGlyphHeight)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("\(TrackIntake.litres(today)) of \(TrackIntake.litres(goal)) litres today"))
            }
        } footer: {
            SomaActionButton("Add \(Int(ml)) ml") {
                let now = Date.now
                let entry = log.addDrink(drink, ml: ml, at: now)
                Task { await TrackHealthWriter.saveDrink(entry) }
                dismiss()
            }
            .disabled(ml <= 0)
        } principal: {
            SomaSegmentedControl(
                segments: TrackDrink.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                selection: Binding(get: { drink }, set: { drink = $0; ml = $0.usual })
            )
        }
    }

    /// Water wears the mind hue the design gives it; coffee and tea the warm
    /// activity hue.
    private var aspect: SomaAspect { drink == .water ? .mind : .activity }
}

#if DEBUG
#Preview("Water") {
    NavigationStack { TrackWaterView() }
}
#endif
