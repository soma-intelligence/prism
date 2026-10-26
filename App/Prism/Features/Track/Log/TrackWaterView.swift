//
//  TrackWaterView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Water, add a drink: the page is the drink. A drag anywhere raises or lowers
/// the level that fills the screen; the usual amounts sit as pills, and the
/// day's total as one line. The drawn glass it replaced looked like clip art
/// (owner, 2026-10-24).
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

        GeometryReader { proxy in
        TrackEntryPage(title: drink.title, scrolls: false, backdrop: AnyView(
            SomaLiquidFill(fill: drink.capacity > 0 ? ml / drink.capacity : 0, aspect: aspect)
        )) {
            // The number, large and light, over the rising level; the whole
            // page pours.
            VStack(spacing: metrics.spaceS) {
                SomaReadout("\(Int(ml))", unit: "ml",
                            caption: drink == .water ? "Drag up or down" : "\(Int(drink.caffeine(ml: ml))) mg caffeine")
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height * 0.42)

            HStack(spacing: metrics.spaceS) {
                ForEach(drink.presets, id: \.self) { preset in
                    Button {
                        ml = preset
                    } label: {
                        Text("\(Int(preset)) ml")
                            .somaFont(type.captionValue)
                            .foregroundStyle(ml == preset ? colors.onAccent.color : colors.inkPrimary.color)
                            .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
                            .background {
                                // Glass over the water, as visionOS sets its
                                // controls over the room; the chosen one ink.
                                if ml == preset {
                                    Capsule().fill(colors.inkPrimary.color)
                                } else {
                                    Color.clear.somaGlass(in: .capsule)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.somaGlassPress)
                    .accessibilityLabel(Text("\(Int(preset)) millilitres"))
                    .accessibilityAddTraits(ml == preset ? .isSelected : [])
                }
            }

            VStack(alignment: .leading, spacing: metrics.spaceS) {
                HStack {
                    TrackEyebrow("Today")
                    Spacer()
                    Text(logged == nil ? "Goal \(TrackIntake.litres(goal)) L" : "\(TrackIntake.litres(today)) of \(TrackIntake.litres(goal)) L")
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        Capsule().fill(colors.inkPrimary.color)
                            .frame(width: bar.size.width * CGFloat(goal > 0 ? min(today / goal, 1) : 0))
                    }
                }
                .frame(height: 4)
                .accessibilityElement()
                .accessibilityLabel(Text("\(TrackIntake.litres(today)) of \(TrackIntake.litres(goal)) litres today"))
            }
            .padding(metrics.cardPadding)
            .somaGlass(in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        } footer: {
            SomaActionButton("Add \(Int(ml)) ml") {
                let now = Date.now
                let entry = log.addDrink(drink, ml: ml, at: now)
                Task {
                    let reached = await TrackHealthWriter.saveDrink(entry)
                    Confirmations.shared.logged(drink.title, reachedHealth: reached)
                }
                dismiss()
            }
            .disabled(ml <= 0)
        } principal: {
            SomaSegmentedControl(
                segments: TrackDrink.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                selection: Binding(get: { drink }, set: { drink = $0; ml = $0.usual })
            )
        }
        .somaLiquidPour(value: $ml, capacity: drink.capacity, step: drink.step, height: proxy.size.height * 0.8)
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
