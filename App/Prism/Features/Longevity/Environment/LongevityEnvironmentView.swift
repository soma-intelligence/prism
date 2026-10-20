//
//  LongevityEnvironmentView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// The Longevity tab's Environment lens: light, air, sound and the bedroom,
/// laid out like the Body lens and drawn rather than written (owner,
/// 2026-10-03: more visual, fewer words, colour for data, everything
/// tappable).
///
/// Daylight, UV and sound come from Apple Health. Where you are comes from
/// ``EnvironmentLocation`` (coarse, asked in context the first time only);
/// the weather, air quality and last night's outdoor temperature there from
/// Open-Meteo (``EnvironmentWeatherClient``), since the app has no WeatherKit
/// capability. Sunrise and sunset are worked out on the device
/// (``EnvironmentSun``). The bedroom and the sleep places are what the Sleep
/// environment sheet keeps, read only.
///
/// Each card opens ``EnvironmentDetailSheet``: the measure over 7 or 30 days,
/// and for a Health reading the way into the Vault. Embedded by
/// `LongevityPage`, which owns the stack and the top bar.
struct LongevityEnvironmentView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var report: EnvironmentReport?
    @State private var location = EnvironmentLocation.shared
    @State private var outside: EnvironmentConditions?
    @State private var outdoorNight: Double?
    @State private var places = SleepPlaceStore.shared
    @State private var sleepInputs: ScoreDetailInputs?
    @State private var detail: EnvironmentMeasure?
    @State private var sheet: BedroomSheet?

    private enum BedroomSheet: String, Identifiable {
        case environment
        case places
        var id: String { rawValue }
    }

    var body: some View {
        let metrics = theme.metrics
        let report = merged

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    EnvironmentLensContent(
                        report: report,
                        sky: EnvironmentSky.make(now: context.date, place: location.place),
                        bedroom: bedroom,
                        here: EnvironmentHere(access: location.access, place: location.place, isHere: location.isHere,
                                              exact: location.exact),
                        sleepPlaces: EnvironmentSleepPlace.make(store: places, scores: health.scores?.detail.sleep ?? [], now: context.date),
                        open: { detail = $0 },
                        openBedroom: { sheet = .environment },
                        openPlaces: { sheet = .places },
                        requestLocation: { location.request() }
                    )
                }
                MindHealthStatus(status: health.status)
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(nil)
        .scoreInputs([.nights, .sound], into: $sleepInputs)
        .refreshable { await load() }
        .task { await load() }
        .task(id: location.place) { await loadOutside() }
        .task(id: sleepInputs?.nights.last ?? nil) { await loadNight() }
        .sheet(item: $detail) { measure in
            EnvironmentDetailSheet(measure: measure, report: report)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .environment: SleepEnvironmentSheet(scores: health.scores, inputs: sleepInputs)
            case .places: SleepPlaceLedgerSheet(scores: health.scores, inputs: sleepInputs)
            }
        }
    }

    /// The Health report with the weather where you are laid in.
    private var merged: EnvironmentReport {
        var report = self.report ?? EnvironmentReport.make(from: EnvironmentInputs(now: Date()))
        report.outside = outside
        return report
    }

    private var bedroom: EnvironmentBedroom {
        EnvironmentBedroom(
            outdoor: outdoorNight,
            noise: sleepInputs?.nightSound.last ?? nil,
            temperature: places.bedroom.temperature,
            isDark: places.bedroom.isDark,
            place: places.place(forNightEnding: Date())?.name
        )
    }

    private func load() async {
        let calendar = Calendar.current
        let now = Date()
        await location.refresh()
#if DEBUG
        if EnvironmentReport.usesPreview {
            report = EnvironmentReport.preview
            return
        }
#endif
        guard let source = await health.prepare(EnvironmentInputs.metrics) else {
            report = EnvironmentReport.make(from: EnvironmentInputs(now: now), calendar: calendar)
            return
        }
        let inputs = await EnvironmentInputs.read(from: source, now: now, calendar: calendar, wholeYear: true)
        report = EnvironmentReport.make(from: inputs, calendar: calendar)
    }

    /// The weather where you are, kept thirty minutes by the client.
    private func loadOutside() async {
        guard let place = location.place else {
            outside = nil
            return
        }
        outside = await EnvironmentWeatherClient.shared.conditions(latitude: place.latitude, longitude: place.longitude)
    }

    /// The outdoor temperature over last night, where it was slept: the
    /// place set for it, else where you are now.
    private func loadNight() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let window = (sleepInputs?.nights.last ?? nil).map { ($0.start, $0.end) }
            ?? (today.addingTimeInterval(-3600), today.addingTimeInterval(7 * 3600))
        let slept = places.place(forNightEnding: Date())
        guard let latitude = slept?.latitude ?? location.place?.latitude,
              let longitude = slept?.longitude ?? location.place?.longitude,
              let conditions = await EnvironmentWeatherClient.shared.conditions(latitude: latitude, longitude: longitude)
        else {
            outdoorNight = nil
            return
        }
        outdoorNight = conditions.mean(from: window.0, to: window.1)
    }
}

#Preview("Environment") {
    NavigationStack {
        LongevityEnvironmentView()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
}
