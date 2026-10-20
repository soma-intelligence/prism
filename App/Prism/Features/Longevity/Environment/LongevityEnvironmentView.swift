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

    /// What the lens drew the last time, kept on the device, so it opens on
    /// its numbers rather than on dashes (``LongevitySnapshotStore``). Each
    /// part below stands in for its read until that read lands.
    @State private var kept = LongevitySnapshotStore.shared.environment
    @State private var report: EnvironmentReport?
    @State private var location = EnvironmentLocation.shared
    /// Whether this opening has asked where you are yet.
    @State private var locationLanded = false
    @State private var outside: EnvironmentConditions?
    @State private var outsideLanded = false
    @State private var outdoorNight: Double?
    @State private var nightLanded = false
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
        let lens = shownLens
        let report = lens.report
        let updated = LongevityShown(kept: kept, fresh: self.report.map { _ in lens }).updated(now: Date())

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                if let updated {
                    SomaUpdatedNote(updated)
                        .padding(.top, metrics.heroTopPadding)
                        .transition(.opacity)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    EnvironmentLensContent(
                        report: report,
                        sky: EnvironmentSky.make(now: context.date, place: lens.place),
                        bedroom: bedroom(lens),
                        here: EnvironmentHere(access: location.access, place: lens.place, isHere: lens.isHere,
                                              exact: location.exact),
                        sleepPlaces: lens.sleepPlaces,
                        open: { detail = $0 },
                        openBedroom: { sheet = .environment },
                        openPlaces: { sheet = .places },
                        requestLocation: { location.request() }
                    )
                    .padding(.top, updated == nil ? 0 : -metrics.heroTopPadding)
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
        .task(id: NightKey(night: (sleepInputs?.nights.last ?? nil)?.start, place: location.place)) { await loadNight() }
        .onChange(of: lens) { _, lens in
            // Kept for the next opening once Health's part has landed.
            if self.report != nil { LongevitySnapshotStore.shared.save(environment: lens) }
        }
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

    /// What reruns last night's outdoor temperature: the night, and where
    /// you are.
    private struct NightKey: Equatable {
        var night: Date?
        var place: EnvironmentSun.Place?
    }

    /// The lens as drawn now: each part read in this opening, else the one
    /// kept from the last, else nothing yet.
    private var shownLens: EnvironmentLensSnapshot {
        let kept = kept?.value
        var report = self.report ?? kept?.report ?? EnvironmentReport.make(from: EnvironmentInputs(now: Date()))
        report.outside = outsideLanded ? outside : kept?.report.outside
        let place = location.place ?? (locationLanded ? nil : kept?.place)
        return EnvironmentLensSnapshot(
            report: report,
            outdoorNight: nightLanded ? outdoorNight : kept?.outdoorNight,
            noise: sleepInputs.map { $0.nightSound.last ?? nil } ?? kept?.noise,
            place: place,
            isHere: location.place != nil ? location.isHere : (place == nil ? false : kept?.isHere ?? false),
            sleepPlaces: health.scores == nil && kept != nil
                ? kept?.sleepPlaces ?? []
                : EnvironmentSleepPlace.make(store: places, scores: health.scores?.detail.sleep ?? [], now: Date())
        )
    }

    private func bedroom(_ lens: EnvironmentLensSnapshot) -> EnvironmentBedroom {
        EnvironmentBedroom(
            outdoor: lens.outdoorNight,
            noise: lens.noise,
            temperature: places.bedroom.temperature,
            isDark: places.bedroom.isDark,
            place: places.place(forNightEnding: Date())?.name
        )
    }

    /// A read landing: the numbers roll to it.
    private func land(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : theme.motion.numberRoll, change)
    }

    private func load() async {
        let calendar = Calendar.current
        let now = Date()
        await location.refresh()
        locationLanded = true
        if location.place == nil {
            // Nowhere to ask the weather for: the kept weather goes too.
            land {
                outside = nil
                outsideLanded = true
            }
        }
        await loadNight()
#if DEBUG
        if EnvironmentReport.usesPreview {
            land { report = EnvironmentReport.preview }
            return
        }
#endif
        guard let source = await health.prepare(EnvironmentInputs.metrics) else {
            land { report = EnvironmentReport.make(from: EnvironmentInputs(now: now), calendar: calendar) }
            return
        }
        let inputs = await EnvironmentInputs.read(from: source, now: now, calendar: calendar, wholeYear: true)
        let read = EnvironmentReport.make(from: inputs, calendar: calendar)
        land { report = read }
        LongevitySnapshotStore.shared.save(environment: shownLens)
    }

    /// The weather where you are, kept thirty minutes by the client. Until
    /// this opening knows where you are, and when the service could not be
    /// reached (or the place moved on before it answered), the last weather
    /// stands.
    private func loadOutside() async {
        guard let place = location.place else { return }
        let read = await EnvironmentWeatherClient.shared.conditions(latitude: place.latitude, longitude: place.longitude)
        guard !Task.isCancelled, let read else { return }
        land {
            outside = read
            outsideLanded = true
        }
    }

    /// The outdoor temperature over last night, where it was slept: the
    /// place set for it, else where you are now. Waits for the night and
    /// for where you are, keeping the last value until then.
    private func loadNight() async {
        guard let sleepInputs, locationLanded else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let window = (sleepInputs.nights.last ?? nil).map { ($0.start, $0.end) }
            ?? (today.addingTimeInterval(-3600), today.addingTimeInterval(7 * 3600))
        let slept = places.place(forNightEnding: Date())
        var night: Double?
        if let latitude = slept?.latitude ?? location.place?.latitude,
           let longitude = slept?.longitude ?? location.place?.longitude {
            // The service out of reach keeps the last night's value.
            guard let conditions = await EnvironmentWeatherClient.shared.conditions(latitude: latitude, longitude: longitude),
                  !Task.isCancelled else { return }
            night = conditions.mean(from: window.0, to: window.1)
        }
        land {
            outdoorNight = night
            nightLanded = true
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

#Preview("Environment") {
    NavigationStack {
        LongevityEnvironmentView()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
}
