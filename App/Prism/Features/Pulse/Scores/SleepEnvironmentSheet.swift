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
/// hand night by night, or detected from the phone when the person turned
/// that on in the ledger.
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
                            .padding(.top, theme.metrics.spaceM)
                    } else {
                        ScoreRows(byPlace) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                                    Text("\(row.nights) nights").somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                                }
                                Spacer()
                                SomaNumber(row.nights >= 3 ? row.score.map { "\(Int($0.rounded()))" } : nil, type.rowValue)
                                    .foregroundStyle(colors.inkPrimary.color)
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
                SomaNumber(bedroom.temperature.map { ScoreMath.number($0, decimals: 1) }, type.rowValue, unit: "°C",
                           unitSpec: type.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
            }
        }
        .padding(.vertical, theme.metrics.scoreRowSpacing)
    }
}

/// Where you slept, night by night: tap a night to set its place. The switch
/// for detecting it lives here too, beside the nights it fills, and each night
/// says whether its place was detected or set by hand.
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
            #if os(iOS)
            SleepPlaceDetectionCard()
            #endif
            if nights.isEmpty {
                ScoreFootnote(text: "Nights appear here once your watch records them.")
            } else {
                SomaBrowseGroup(nights, hasGlyphs: false) { night in
                    SomaBrowseRow(title: night.day == today ? "Last night" : night.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                  detail: nil, action: { picking = PickedNight(day: night.day) }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            SomaNumber(night.score.map { "\(Int($0.rounded()))" }, type.rowValue)
                                .foregroundStyle(colors.inkPrimary.color)
                            let place = places.place(forNightEnding: night.day)
                            Text(place.map { "\($0.name) · \($0.wasDetected ? "detected" : "set by you")" } ?? "not set")
                                .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                            // The street line is in the name already; the full
                            // address adds the postcode and the building.
                            if let address = place?.address, address != place?.name {
                                Text(address)
                                    .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                                    .lineLimit(1).truncationMode(.middle)
                            }
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

#if os(iOS)
/// The switch for detecting where each night was slept, and the one step the
/// Location answer still needs, if any: Always, so a night is noted even when
/// the app stays closed, or Settings, when Location or its precision is off.
private struct SleepPlaceDetectionCard: View {
    @State private var recorder = SleepPlaceRecorder.shared
    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL

    private struct Step {
        var title: String
        var detail: String
        var action: (() -> Void)?
    }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(get: { recorder.isOn }, set: { recorder.setOn($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detect where you sleep").somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                        Text("Soma notes the street your phone spent the night on, and keeps it on this phone.")
                            .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .toggleStyle(.soma)
                .tint(colors.accent.color)
                .padding(.vertical, theme.metrics.scoreRowSpacing)
                if recorder.isOn, let step {
                    Rectangle().fill(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)).frame(height: 0.5)
                    Button { step.action?() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).somaFont(type.body).foregroundStyle(colors.inkPrimary.color)
                                Text(step.detail).somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                            }
                            Spacer(minLength: theme.metrics.spaceS)
                            if step.action != nil {
                                Image(systemName: "chevron.right")
                                    .somaFont(type.caption).foregroundStyle(colors.inkSecondary.color)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(step.action == nil)
                    .padding(.vertical, theme.metrics.scoreRowSpacing)
                }
            }
        }
    }

    /// What is left to do once the switch is on. Nothing while the system's
    /// own question is still on screen.
    private var step: Step? {
        let settings = OpenSystemSettings(openURL: openURL)
        switch recorder.access {
        case .notAsked:
            return nil
        case .denied:
            return Step(title: "Location is off for Soma",
                        detail: "Turn it on in Settings, while using the app or always.",
                        action: { settings() })
        case _ where !recorder.isPrecise:
            return Step(title: "Precise Location is off",
                        detail: "Without it the place is a district, not a street. Turn it on in Settings.",
                        action: { settings() })
        case .whenInUse:
            return Step(title: "Also when Soma stays closed",
                        detail: recorder.canAskAlways
                            ? "Allow Location always and Soma notes the place even on mornings you never open it."
                            : "Change Location to Always in Settings and Soma notes the place even on mornings you never open it.",
                        action: recorder.canAskAlways ? { recorder.requestAlways() } : { settings() })
        case .always:
            return Step(title: "Detecting every night",
                        detail: "Even with Soma closed. A night you set by hand stays yours.",
                        action: nil)
        }
    }
}
#endif
