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
/// environment sheet keeps, read only. The week (``EnvironmentWeek``) rides
/// the Health report, with the air and today's pollen laid in; a high pollen
/// morning raises an alert when the person turned that on.
///
/// Each card opens ``EnvironmentDetailSheet``: the measure over 7 or 30 days,
/// and for a Health reading the way into the Vault. Embedded by
/// `LongevityPage`, which owns the stack and the top bar.
struct LongevityEnvironmentView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var location = EnvironmentLocation.shared
    @State private var outdoorNight: Double?
    @State private var places = SleepPlaceStore.shared
    @State private var notifications = SomaNotifications.shared
    @State private var sleepInputs: ScoreDetailInputs?
    @State private var detail: EnvironmentMeasure?
    @State private var sheet: BedroomSheet?

    /// The last read, this launch's or the last one's: the lens draws it at
    /// once and the next read replaces every card in one go.
    private var cache: LongevityCache { .shared }

    private enum BedroomSheet: String, Identifiable {
        case environment
        case places
        var id: String { rawValue }
    }

    var body: some View {
        let metrics = theme.metrics
        let report = merged

        ScrollViewReader { scroller in
        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    EnvironmentLensContent(
                        report: report,
                        sky: EnvironmentSky.make(now: context.date, place: location.place),
                        bedroom: bedroom,
                        here: EnvironmentHere(access: location.access, place: location.place, isHere: location.isHere),
                        sleepPlaces: EnvironmentSleepPlace.make(store: places, scores: health.scores?.detail.sleep ?? [], now: context.date),
                        open: { detail = $0 },
                        openBedroom: { sheet = .environment },
                        openPlaces: { sheet = .places },
                        requestLocation: { location.request() },
                        pollenAlerts: notifications.schedule.pollenAlerts,
                        setPollenAlerts: setPollenAlerts
                    )
                }
                MindHealthStatus(status: health.status)
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
#if DEBUG
        .task {
            // `-environment.scroll pollen` (or week) brings that card into
            // view, for screenshots.
            if let card = UserDefaults.standard.string(forKey: "environment.scroll") {
                try? await Task.sleep(for: .seconds(1))
                scroller.scrollTo(card, anchor: .top)
            }
        }
#endif
        }
        .aspectWash(nil)
        .scoreInputs([.nights, .sound], into: $sleepInputs)
        .somaRefreshable { await load(force: true) }
        .task { await load(force: false) }
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
        var report = cache.environment ?? EnvironmentReport.make(from: EnvironmentInputs(now: Date()))
        report.outside = cache.outside
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

    /// The Health report and where you are, side by side: finding the place
    /// can take seconds, and the report does not wait on it.
    private func load(force: Bool) async {
        async let place: Void = location.refresh()
        await cache.loadEnvironment(health, force: force)
        await place
    }

    /// The weather where you are, kept thirty minutes by the client. The
    /// last one known stays drawn while the place is still being found.
    private func loadOutside() async {
        guard let place = location.place else {
            if location.access != .allowed, SleepPlaceStore.shared.weatherCity == nil { cache.setOutside(nil) }
            return
        }
        guard let conditions = await EnvironmentWeatherClient.shared.conditions(latitude: place.latitude, longitude: place.longitude) else { return }
        cache.setOutside(conditions)
        await raisePollenAlert(conditions)
    }

    /// The pollen switch, from the pollen card. Turning it on asks for
    /// notifications then, in context, if that was never asked.
    private func setPollenAlerts(_ isOn: Bool) {
        notifications.schedule.pollenAlerts = isOn
        Task {
            await notifications.apply(asking: isOn)
            if isOn, let outside = cache.outside { await raisePollenAlert(outside) }
        }
    }

    /// Today's high pollen, once a morning, when the person asked for it:
    /// into the inbox, and onto the phone when notifications are on.
    private func raisePollenAlert(_ conditions: EnvironmentConditions) async {
        guard let alert = DataAlertRules.pollenMorning(
            peak: conditions.pollen.flatMap(PollenPeak.strongest),
            schedule: notifications.schedule,
            prefs: notifications.settings.notifications,
            now: Date()
        ), !notifications.inbox.contains(where: { $0.id == alert.id }) else { return }
        notifications.add(InboxItem(id: alert.id, kind: .dataAlert, title: alert.title, body: alert.body,
                                    date: Date(), link: alert.link))
        if notifications.isOn { try? await notifications.scheduler.add(alert) }
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
