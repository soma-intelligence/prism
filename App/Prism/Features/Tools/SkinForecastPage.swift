//
//  SkinForecastPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Skin Forecast: one index for what today's UV, air, heat and wind ask of the
/// skin, and the conditions behind it against their comfortable range.
///
/// the earlier app's skin index engine, unchanged. Every input is the weather where the
/// person is (``ToolWeather``); until a place is known the page holds its
/// shape with dashes and says so.
struct SkinForecastPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let weather = ToolWeather.current
        let reading = weather.flatMap {
            SomaTools.SkinForecastEngine.reading(uvIndex: $0.uvPeak ?? $0.uvNow, aqi: $0.aqi, windKph: $0.windKph,
                                                 temperatureC: $0.temperatureC, humidityPercent: $0.humidityPercent)
        }

        ToolPage(ToolKind.skinForecast.title) {
            ToolGauge(aspect: .body, fraction: reading.map { Double($0.index) / 100 },
                      display: reading.map { "\($0.index)" },
                      state: reading.map { ToolFormat.capitalized($0.band.rawValue) } ?? "Waiting on the weather",
                      delta: nil, deltaIsWorse: false)

            if let reading, let weather {
                ToolHero(headline: headline(reading.band),
                         lead: lever(reading),
                         rest: "A wellness estimate from local weather and air in \(weather.place).")
            } else {
                ToolHero(headline: "The forecast needs the weather where you are.",
                         lead: "UV, air quality, temperature and wind make the index, read for the place the Environment lens knows.",
                         rest: "Each condition below waits as a dash until it can.")
            }

            ToolRowsCard(title: "Today’s conditions", eyebrow: "Against a comfortable range", aspect: .body,
                         rows: conditionRows(weather))

            ToolLinkRow(title: "Sun Budget", detail: weather?.uvNow.map { "UV \(ToolFormat.number($0)) now" }, value: ToolRoute.sunBudget)
            ToolFootnote("A wellness estimate, not a diagnosis.")
            ToolLinkRow(title: "About Skin Forecast", detail: nil, value: ToolRoute.intro(.skinForecast))
        }
        .task {
            store.markOpened(.skinForecast)
            await model.load(health)
        }
    }

    private func headline(_ band: SomaTools.SkinBand) -> String {
        switch band {
        case .calm: "A calm day for your skin."
        case .mild: "A mild day for your skin."
        case .reactive: "A demanding day for your skin."
        case .high: "A harsh day for your skin."
        }
    }

    private func lever(_ reading: SomaTools.SkinForecastReading) -> String {
        switch reading.topLever {
        case .uv: "UV is the one thing to cover."
        case .airQuality: "The air is the one thing to watch."
        case .wind: "Wind is the one thing to shield from."
        case .temperature: "The temperature is the one thing to dress for."
        case nil: "Nothing in the air asks much of it."
        }
    }

    private func conditionRows(_ weather: ToolWeather?) -> [ToolRow] {
        typealias Engine = SomaTools.SkinForecastEngine
        func row(_ title: String, _ feature: SomaTools.SkinFeature, _ value: Double?, _ text: String?) -> ToolRow {
            let zone = Engine.comfortZone(feature)
            let low = zone.harshLow ?? 0
            let usual = "comfortable \(ToolFormat.number(zone.comfort.lowerBound)) to \(ToolFormat.number(zone.comfort.upperBound))\(zone.unit.isEmpty ? "" : " " + zone.unit)"
            let isBad = value.map { !zone.comfort.contains($0) } ?? false
            return ToolRow(title: title, detail: usual, value: text, tone: isBad ? .danger : .plain,
                           band: ToolBand(range: low...zone.harshHigh, usual: zone.comfort, value: value))
        }
        return [
            row("UV at its peak", .uv, weather?.uvPeak, weather?.uvPeak.map { ToolFormat.number($0) }),
            row("Air quality", .airQuality, weather?.aqi.map(Double.init), weather?.aqi.map { "\($0)" }),
            ToolRow(title: "Humidity", detail: "comfortable 40 to 60%", value: weather?.humidityPercent.map { "\(Int($0.rounded()))%" }),
            row("Temperature", .temperature, weather?.temperatureC, weather?.temperatureC.map { "\(Int($0.rounded())) °C" }),
            row("Wind", .wind, weather?.windKph, weather?.windKph.map { "\(Int($0.rounded())) km/h" }),
        ]
    }
}
