//
//  TrackWeightView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Weight: the number turns a scale under a needle. It starts from the last
/// weight Apple Health holds (or the last one logged here), and saving writes
/// a body mass sample to Health and keeps a copy in ``TrackLogStore``.
struct TrackWeightView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(\.dismiss) private var dismiss

    /// Kilograms.
    @State private var kilograms: Double?
    @State private var last: (kilograms: Double, date: Date, source: String?)?
    @State private var isSaving = false

    private let unit = TrackMassUnit.preferred()
    private let log = TrackLogStore.shared

    var body: some View {
        let metrics = theme.metrics
        let shown = kilograms ?? last?.kilograms

        TrackEntryPage(title: "Weight", scrolls: false) {
            SomaReadout(shown.map(unit.text) , unit: unit.symbol, caption: TrackClock.dayAndTime(.now))
                .padding(.top, metrics.leadSpacing)

            SomaScaleDial(
                value: Binding(
                    get: { unit.display(shown ?? 70) },
                    set: { kilograms = unit.kilograms($0) }
                ),
                range: unit == .kilograms ? 20...250 : 44...550,
                step: unit.step,
                majorEvery: unit == .kilograms ? 10 : 5,
                label: "Weight"
            ) { "\(Int($0.rounded()))" }
            .padding(.horizontal, -metrics.pagePadding)
            .padding(.top, metrics.leadSpacing)

            TrackNote(lead: lastLine)
        } footer: {
            SomaActionButton(shown.map { "Save \(unit.text($0)) \(unit.symbol)" } ?? "Save") {
                guard let value = shown else { return }
                isSaving = true
                log.addMeasure(.weight, value: value, at: .now)
                Task {
                    await TrackHealthWriter.save([.bodyMass(kilograms: value)], at: .now)
                    dismiss()
                }
            }
            .disabled(shown == nil || isSaving)
        }
        .task { await load() }
    }

    private var lastLine: String {
        guard let last else { return "Drag the scale to your weight. Nothing to compare with yet." }
        let place = last.source.map { $0.localizedCaseInsensitiveContains("soma") ? ", from Soma" : "" } ?? ""
        return "Last: \(unit.text(last.kilograms)) \(unit.symbol) on \(TrackClock.day(last.date))\(place)"
    }

    private func load() async {
        var found: (Double, Date, String?)?
        if let reading = await TrackHealthReads.latest(TrackHealthReads.Metric.bodyMass, from: health) {
            found = (reading.value, reading.start, reading.source)
        }
        if let local = log.latest(.weight), local.date > (found?.1 ?? .distantPast) {
            found = (local.value, local.date, nil)
        }
        last = found.map { (kilograms: $0.0, date: $0.1, source: $0.2) }
    }
}

#if DEBUG
#Preview("Weight") {
    NavigationStack { TrackWeightView() }
        .environment(HealthDashboard())
}
#endif
