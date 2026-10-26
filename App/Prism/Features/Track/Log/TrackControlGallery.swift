//
//  TrackControlGallery.swift
//  Prism
//

import SwiftUI
import SomaUI
import SomaUIPreviewSupport

/// The visual inputs' entries in the component gallery: the glass, the
/// scale, the ruler, the clock, the dials, the moons, the valence track, the
/// macro ring, the readout, chips and the action button.
struct TrackControlGallery: View {
    @Environment(\.somaTheme) private var theme

    @State private var water = SomaPreviewSamples.waterMillilitres
    @State private var weight = SomaPreviewSamples.weightKilograms
    @State private var height = SomaPreviewSamples.heightCentimetres
    @State private var start = SomaPreviewSamples.fastStartHour
    @State private var length = SomaPreviewSamples.fastLengthHours
    @State private var minutes = SomaPreviewSamples.plungeMinutes
    @State private var grams = SomaPreviewSamples.scoopGrams
    @State private var rating = SomaPreviewSamples.wakeRating
    @State private var feeling = SomaPreviewSamples.feeling

    var body: some View {
        VStack(spacing: theme.metrics.leadSpacing) {
            entry("SomaReadout") {
                SomaReadout(String(format: "%.1f", weight), unit: "kg", caption: "Today, 18:02")
            }
            entry("SomaChoiceChip, SomaActionButton") {
                VStack(spacing: theme.metrics.cardSpacing) {
                    HStack {
                        SomaChoiceChip("Drink", symbol: "plus") {}
                        SomaChoiceChip("One bowl", isOn: true) {}
                        SomaChoiceChip("Sauna", isOn: true, style: .outline) {}
                    }
                    SomaActionButton("Add \(Int(water)) ml") {}
                }
            }
            entry("SomaVesselInput, SomaVessel") {
                VStack(spacing: theme.metrics.cardSpacing) {
                    SomaVesselInput(value: $water, capacity: 1000, step: 50, label: "Water")
                        .frame(height: theme.metrics.vesselHeight)
                    HStack {
                        ForEach(Array(SomaPreviewSamples.dayGlasses.enumerated()), id: \.offset) { _, fill in
                            SomaVessel(fill: fill, isGlyph: true).frame(height: theme.metrics.vesselGlyphHeight)
                        }
                    }
                    SomaVessel(fill: 0.73, marks: SomaPreviewSamples.dayPours)
                        .frame(height: theme.metrics.vesselHeight)
                        .padding(.trailing, theme.metrics.orbDiameter * 0.55)
                }
            }
            entry("SomaScaleDial") {
                SomaScaleDial(value: $weight, range: 20...250, step: 0.1, label: "Weight")
            }
            entry("SomaHeightRuler") {
                SomaHeightRuler(value: $height, label: "Height")
            }
            entry("SomaDayClock") {
                SomaDayClock(start: $start, length: $length, band: SomaPreviewSamples.sleepWindow, now: 18) {
                    SomaReadout("\(Int(length))", unit: "h")
                }
            }
            entry("SomaArcDial") {
                VStack {
                    SomaArcDial(value: $minutes, range: 0...10, step: 0.5, style: .ring(segments: 10), label: "Minutes") {
                        SomaReadout(SomaArcDial<EmptyView>.number(minutes), unit: "min")
                    }
                    SomaArcDial(value: $grams, range: 0...20, step: 0.5, style: .gauge(tick: 1, label: 5), aspect: .body, label: "Grams") {
                        SomaReadout(SomaArcDial<EmptyView>.number(grams), unit: "g")
                    }
                }
            }
            entry("SomaMoon, SomaMoonScale") {
                VStack {
                    SomaMoon(lit: Double(rating ?? 0) / 10, glows: true)
                        .frame(width: theme.metrics.moonDiameter)
                    SomaMoonScale(value: $rating, low: "Drained", high: "Fully rested")
                }
            }
            entry("SomaValenceSlider") {
                SomaValenceSlider(value: $feeling, low: "Very unpleasant", high: "Very pleasant", names: SomaPreviewSamples.feelingNames)
            }
            entry("SomaMacroRing") {
                SomaMacroRing(parts: SomaPreviewSamples.dinnerParts) {
                    SomaReadout("598", caption: "kcal")
                }
            }
        }
    }

    private func entry(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: theme.metrics.cardSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(.horizontal, theme.metrics.pagePadding)
    }
}

#Preview("Track controls") {
    SomaPageScroll { TrackControlGallery() }
}
