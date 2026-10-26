//
//  SunBudgetPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Sun Budget: how long bare skin has in today's sun, what cover buys, and
/// the sun counted toward vitamin D.
///
/// The burn time comes from the erythemal dose engine: the UV index against the
/// minimal erythemal dose of the person's skin type. The UV comes from the
/// weather where the person is (``ToolWeather``); until a place is known the
/// numbers are dashes and the page says why. The skin type and the time spent
/// in daylight never wait on it.
struct SunBudgetPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var spf: SomaTools.SunBudget.SPF = .spf30
    @State private var editingSkin = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let skin = SomaTools.Fitzpatrick(rawValue: store.record.skinType ?? 0)
        let weather = ToolWeather.current
        let reading = weather.flatMap { Self.reading($0, skin: skin ?? .assumedDefault, spf: spf, now: model.current.now) }

        ToolPage(ToolKind.sunBudget.title) {
            if let reading, let weather {
                withWeather(reading, weather: weather, skin: skin ?? .assumedDefault)
            } else {
                ToolHero(eyebrow: "UV not read yet",
                         headline: "Sun Budget needs the UV where you are.",
                         lead: "Soma reads it for the place the Environment lens knows, and there is none yet.",
                         rest: "Everything below that needs it waits as a dash; your skin type and time outside are ready.")
                ToolStats([
                    SomaStat("UV now", value: nil),
                    SomaStat("Peak", value: nil),
                    SomaStat("Burn at peak", value: nil, unit: "min"),
                ])
                ToolEmptyCard(eyebrow: "Today’s UV", message: "The day’s UV curve and the stretch where bare skin needs cover appear once the weather where you are is read.")
            }

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                    Text("Vitamin D from the sun")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    ToolReason(lead: daylightLead, rest: nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ToolButtonRow(title: "Skin type", detail: skin?.roman ?? "Not set") { editingSkin = true }
            ToolFootnote("An estimate, not a limit.")
            ToolLinkRow(title: "About Sun Budget", detail: nil, value: ToolRoute.intro(.sunBudget))
        }
        .sheet(isPresented: $editingSkin) { SkinTypeSheet() }
        .task {
            store.markOpened(.sunBudget)
            await model.load(health)
        }
    }

    private var daylightLead: String {
        guard let minutes = model.current.daylightToday else {
            return "No time in daylight recorded today."
        }
        return "\(Int(minutes.rounded())) minutes outside today."
    }

    @ViewBuilder
    private func withWeather(_ reading: SomaTools.SunBudget.Reading, weather: ToolWeather, skin: SomaTools.Fitzpatrick) -> some View {
        let peak = reading.dayPeak?.uv ?? weather.uvPeak
        let atPeak = reading.minutesToBurnAtPeak
        ToolHero(eyebrow: "UV \(ToolFormat.number(reading.uv)) now" + (peak.map { " · \(ToolFormat.number($0)) at midday" } ?? ""),
                 headline: reading.band == .noRisk ? "No burn risk right now." : reading.band.label + ".",
                 lead: atPeak.map { "At the peak, your type \(skin.roman) skin reddens in about \(Int($0.rounded())) minutes without cover." } ?? "The UV is too low to burn today.",
                 rest: "Reapply every two hours outdoors, and after swimming or sweat.")
        ToolStats([
            SomaStat("UV now", value: ToolFormat.number(reading.uv)),
            SomaStat("Peak", value: peak.map { ToolFormat.number($0) }),
            SomaStat("Burn at peak", value: atPeak.map { "\(Int($0.rounded()))" }, unit: "min"),
        ])
        let hourly = reading.hourly
        let top = max(8, (hourly.map(\.uv).max() ?? 0).rounded(.up))
        SomaChartCard(eyebrow: "Today’s UV", value: nil, note: "Above the line, bare skin needs cover.") {
            ToolCurveChart(aspect: .body, values: hourly.map { Optional($0.uv) }, top: top,
                           threshold: 3, now: nowFraction(hourly), xLabels: ["06", "09", "12", "15", "18", "21"],
                           yLabels: [ToolFormat.number(top), ToolFormat.number(top / 2), "0"])
        }
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                Text("What cover buys you")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                SomaSegmentedControl(segments: SomaTools.SunBudget.SPF.allCases.map {
                    SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.label))
                }, selection: $spf)
                ToolReason(lead: coverLead(reading), rest: nil)
            }
        }
    }

    private func coverLead(_ reading: SomaTools.SunBudget.Reading) -> String {
        switch reading.outcome {
        case .burns(let minutes): "With \(spf.label), the time to burn runs to \(ToolFormat.span(hours: minutes / 60))."
        case .outlastsDay: "With \(spf.label), your skin outlasts today’s sun."
        case .noRiskNow: "No cover needed right now."
        }
    }

    private func nowFraction(_ hourly: [SomaTools.ErythemalDoseEngine.UVSample]) -> Double? {
        guard let first = hourly.first?.date, let last = hourly.last?.date, last > first else { return nil }
        return model.current.now.timeIntervalSince(first) / last.timeIntervalSince(first)
    }

    static func reading(_ weather: ToolWeather, skin: SomaTools.Fitzpatrick, spf: SomaTools.SunBudget.SPF, now: Date) -> SomaTools.SunBudget.Reading? {
        guard let conditions = SomaTools.SunBudget.conditions(
            uvIndex: weather.uvNow, latitude: weather.latitude, longitude: weather.longitude,
            date: now, hourlyUV: weather.hourlyUV, peakUV: weather.uvPeak, calendar: .current)
        else { return nil }
        return SomaTools.SunBudget.Reading(conditions: conditions, fitzpatrick: skin, spf: spf, now: now)
    }
}

/// The skin type sheet: six types, the chosen one ticked.
struct SkinTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme

    private var store: ToolsStore { .shared }

    var body: some View {
        NavigationStack {
            ListScaffold(eyebrow: "Sun Budget", title: "Skin type") {
                ToolReason(lead: "How your skin answers midday sun before any tan.", rest: nil)
                SomaBrowseGroup(SomaTools.Fitzpatrick.allCases, hasGlyphs: false) { type in
                    SomaBrowseRow(title: type.label, detail: type.summary, opensSomething: false,
                                  action: { store.update { $0.skinType = type.rawValue } }) {
                        if store.record.skinType == type.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.colors.accent.color)
                                .accessibilityLabel("Chosen")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
