//
//  SleepEnvironmentSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// The room and the place: the outside temperature curve (which needs a
/// weather source Soma does not have yet, and says so), the bedroom last
/// night against your best nights, your sleep score place by place, and the
/// ledger of where each night was slept.
///
/// Sound is measured (Apple Health's environmental audio over the sleep
/// window); temperature and light are what the person sets; places are set by
/// hand, night by night.
struct SleepEnvironmentSheet: View {
    let scores: SomaScores?
    let inputs: ScoreDetailInputs?

    @State private var places = SleepPlaceStore.shared
    @State private var showsLedger = false
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let sound = inputs?.nightSound ?? []
        let byPlace = placeScores()

        ScoreSheet(eyebrow: "Sleep · Environment", title: "Sleep environment") {
            ScoreParagraph(lead: "Your room and where you slept, against your best nights.",
                           rest: "Sound comes from your watch or phone overnight. Temperature, light and places are yours to set.")
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    SomaCardHeader("Your comfort curve", caption: "Sleep score by outside temperature")
                    ScoreEmptyPlot(message: "Outside temperature needs a weather source, and Soma has none yet. The curve draws once it does.")
                }
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 0) {
                    SomaCardHeader("Your bedroom last night", caption: "As you set it")
                    ScoreRows([
                        ScoreMath.usualLine(title: "Noise", value: sound.last ?? nil,
                                            usual: ScoringUsual.of(Array(sound.dropLast()), spreadFloor: 2),
                                            worse: .higher, format: { ScoreMath.number($0) }, unit: " dB",
                                            empty: "best under 40 dB"),
                    ]) { line in
                        ScoreUsualRow(line: line, aspect: .sleep)
                    }
                    BedroomTemperatureRow(bedroom: $places.bedroom)
                    Rectangle().fill(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)).frame(height: 0.5)
                    Toggle(isOn: Binding(get: { places.bedroom.isDark ?? false },
                                         set: { places.bedroom.isDark = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fully dark").somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                            Text(places.bedroom.isDark == nil ? "not set" : "best fully dark")
                                .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                    .toggleStyle(.soma)
                    .padding(.vertical, theme.metrics.scoreRowSpacing)
                }
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 0) {
                    SomaCardHeader("Place by place", caption: "Average sleep score")
                    if byPlace.isEmpty {
                        Text("Three nights a place")
                            .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                            .padding(.top, 10)
                    } else {
                        ScoreRows(byPlace) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                                    Text("\(row.nights) nights").somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                                }
                                Spacer()
                                Text(row.nights >= 3 ? row.score.map { "\(Int($0.rounded()))" } ?? "-" : "-")
                                    .somaFont(type.rowValue).foregroundStyle(colors.inkPrimary.color)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            ScoreLinks(links: [ScoreLink(title: "Night by night", detail: "\(inputs?.recordedNights.count ?? 0) nights") {
                showsLedger = true
            }])
            ScoreAbout(lead: "Sound over your sleep window.",
                       rest: "A place ranks after three nights. One you set by hand is never replaced.",
                       symbol: "ear.fill", hue: .hearing)
        }
        .sheet(isPresented: $showsLedger) { SleepPlaceLedgerSheet(scores: scores, inputs: inputs) }
    }

    struct PlaceRow: Identifiable {
        var id: String { name }
        var name: String
        var nights: Int
        var score: Double?
    }

    private func placeScores() -> [PlaceRow] {
        let detail = scores?.detail.sleep ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var groups: [String: [Double?]] = [:]
        for (offset, score) in detail.reversed().enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let place = places.place(forNightEnding: day) else { continue }
            groups[place.name, default: []].append(score)
        }
        return groups.map { PlaceRow(name: $0.key, nights: $0.value.count, score: ScoreMath.mean($0.value)) }
            .sorted { $0.nights > $1.nights }
    }
}

/// The bedroom temperature as the person sets it, in half degrees.
private struct BedroomTemperatureRow: View {
    @Binding var bedroom: SleepPlaceStore.Bedroom

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        Stepper(value: Binding(get: { bedroom.temperature ?? 19 }, set: { bedroom.temperature = $0 }),
                in: 10...30, step: 0.5) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature").somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                    Text("best 16 to 19 °C").somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                }
                Spacer()
                Text(bedroom.temperature.map { "\(ScoreMath.number($0, decimals: 1)) °C" } ?? "-")
                    .somaFont(type.rowValue).foregroundStyle(colors.inkPrimary.color)
            }
        }
        .padding(.vertical, theme.metrics.scoreRowSpacing)
    }
}

/// Where you slept, night by night: tap a night to set its place.
struct SleepPlaceLedgerSheet: View {
    let scores: SomaScores?
    let inputs: ScoreDetailInputs?

    @State private var places = SleepPlaceStore.shared
    @State private var picking: PickedNight?
    @Environment(\.somaTheme) private var theme

    struct PickedNight: Identifiable {
        var id: Date { day }
        var day: Date
    }

    struct Night: Identifiable {
        var id: Date { day }
        var day: Date
        var score: Double?
    }

    /// Where the device is now, as a place to sleep: its own spot, named by
    /// the city the Environment lens already looked up. Nil without the
    /// device's position.
    static func here(_ location: EnvironmentLocation) -> SleepPlaceStore.Place? {
        guard let exact = location.exact else { return nil }
        return SleepPlaceStore.Place(name: exact.name ?? String(localized: "Where you were"),
                                     latitude: exact.latitude, longitude: exact.longitude)
    }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let recorded = Set((inputs?.recordedNights ?? []).map { calendar.startOfDay(for: $0.end) })
        let sleep = scores?.detail.sleep ?? []
        let nights: [Night] = (0..<30).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            guard recorded.contains(day) || inputs == nil else { return nil }
            let index = sleep.count - 1 - back
            return Night(day: day, score: sleep.indices.contains(index) ? sleep[index] : nil)
        }

        ScoreSheet(eyebrow: "Sleep · Places", title: "Where you slept") {
            ScoreParagraph(lead: "Tap a night to set where you slept.", rest: "A place you set by hand is never replaced.")
            if nights.isEmpty {
                ScoreFootnote(text: "Nights appear here once your watch records them.")
            } else {
                SomaBrowseGroup(nights, hasGlyphs: false) { night in
                    SomaBrowseRow(title: night.day == today ? "Last night" : night.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                  detail: nil, action: { picking = PickedNight(day: night.day) }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(night.score.map { "\(Int($0.rounded()))" } ?? "-")
                                .somaFont(type.rowValue).foregroundStyle(colors.inkPrimary.color)
                            Text(places.place(forNightEnding: night.day).map {
                                places.isSetByHand(forNightEnding: night.day) ? "\($0.name) · set by you" : "\($0.name) · found"
                            } ?? "not set")
                                .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                }
            }
            ScoreFootnote(text: "The number is the sleep score for that night.")
        }
        .sheet(item: $picking) { night in
            CityPickerSheet(eyebrow: "Sleep · Places", title: "Where did you sleep?",
                            current: places.place(forNightEnding: night.day), recent: places.recentPlaces,
                            here: Self.here(EnvironmentLocation.shared), isPrecise: true) { place in
                places.setPlace(place, forNightEnding: night.day)
            }
        }
    }
}
