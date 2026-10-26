//
//  TrackHeightView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Height, then waist: a figure stands against a ruler and grows to the
/// height under the knob; the waist is read off a tape that turns like the
/// scale. Each saves to Apple Health (height, waist circumference) and to
/// ``TrackLogStore``; Skip moves on without saving.
struct TrackHeightView: View {
    private enum Step { case height, waist }

    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var step = Step.height
    @State private var unit = TrackLengthUnit.preferred()
    /// Centimetres.
    @State private var height: Double?
    @State private var waist: Double?
    @State private var knownHeight: Double?
    @State private var knownWaist: Double?

    private let log = TrackLogStore.shared

    var body: some View {
        let metrics = theme.metrics

        TrackEntryPage(title: step == .height ? "Height" : "Waist", scrolls: false) {
            switch step {
            case .height:
                let shown = height ?? knownHeight
                let parts = shown.map(unit.parts)
                SomaReadout(parts?.value, unit: parts?.unit ?? (unit == .centimetres ? "cm" : ""))
                SomaHeightRuler(
                    value: Binding(get: { shown ?? 170 }, set: { height = $0 }),
                    range: 0...220,
                    step: unit.step,
                    tickEvery: unit == .centimetres ? 10 : TrackLengthUnit.centimetresPerInch * 6,
                    labels: unit == .centimetres ? [50, 100, 150, 200] : [1, 2, 3, 4, 5, 6, 7].map { Double($0) * 12 * TrackLengthUnit.centimetresPerInch },
                    label: "Height"
                ) { [unit] value in
                    unit == .centimetres ? "\(Int(value.rounded()))" : "\(Int((value / TrackLengthUnit.centimetresPerInch / 12).rounded())) ft"
                }
            case .waist:
                let shown = waist ?? knownWaist
                let parts = shown.map(unit.parts)
                SomaReadout(parts?.value, unit: parts?.unit ?? (unit == .centimetres ? "cm" : ""),
                            caption: "Round the navel, breathing out")
                    .padding(.top, metrics.leadSpacing)
                SomaScaleDial(
                    value: Binding(get: { shown ?? 80 }, set: { waist = $0 }),
                    range: 40...180,
                    step: unit.step,
                    majorEvery: unit == .centimetres ? 20 : 12,
                    label: "Waist"
                ) { [unit] value in
                    unit == .centimetres ? "\(Int(value.rounded()))" : "\(Int((value / TrackLengthUnit.centimetresPerInch).rounded()))"
                }
                .padding(.horizontal, -metrics.pagePadding)
                .padding(.top, metrics.leadSpacing)
                TrackNote(lead: knownWaist == nil
                          ? "Waist against height says more about the middle than weight does."
                          : "Last: \(unit.parts(knownWaist ?? 0).value) \(unit.parts(knownWaist ?? 0).unit)")
            }
        } footer: {
            HStack(spacing: metrics.cardSpacing) {
                SomaActionButton("Skip", role: .secondary) { advance() }
                    .frame(maxWidth: metrics.orbDiameter * 0.7)
                switch step {
                case .height:
                    SomaActionButton("Next: waist") {
                        if let value = height ?? knownHeight, height != nil {
                            save(.height, value)
                        }
                        advance()
                    }
                case .waist:
                    SomaActionButton("Save") {
                        if let value = waist { save(.waist, value) }
                        dismiss()
                    }
                    .disabled(waist == nil)
                }
            }
        } principal: {
            SomaSegmentedControl(
                segments: TrackLengthUnit.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                selection: $unit
            )
        }
        .task { await load() }
    }

    private func advance() {
        switch step {
        case .height: step = .waist
        case .waist: dismiss()
        }
    }

    private func save(_ measure: TrackMeasure, _ centimetres: Double) {
        log.addMeasure(measure, value: centimetres, at: .now)
        let quantity: TrackHealthWriter.Quantity = measure == .height ? .height(centimetres: centimetres) : .waist(centimetres: centimetres)
        Task {
            let reached = await TrackHealthWriter.save([quantity], at: .now)
            Confirmations.shared.logged(measure == .height ? "Height" : "Waist", reachedHealth: reached)
        }
    }

    private func load() async {
        if let reading = await TrackHealthReads.latest(TrackHealthReads.Metric.height, from: health) {
            knownHeight = reading.value * 100
        } else {
            knownHeight = log.latest(.height)?.value
        }
        if let reading = await TrackHealthReads.latest(TrackHealthReads.Metric.waist, from: health) {
            knownWaist = reading.value * 100
        } else {
            knownWaist = log.latest(.waist)?.value
        }
    }
}

#if DEBUG
#Preview("Height") {
    NavigationStack { TrackHeightView() }
        .environment(HealthDashboard())
}
#endif
