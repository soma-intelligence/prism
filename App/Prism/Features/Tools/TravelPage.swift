//
//  TravelPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Travel: a trip across time zones taken in steps. Sleep moves half an hour a
/// night before the flight, and light is timed after landing.
///
/// The jet lag model: recovery takes about a day per zone flying east and
/// two thirds of that flying west, sooner with daylight, and the day's actions
/// come from the same travel planner the shift tool uses.
struct TravelPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var editing = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    /// How far sleep moves each night before the flight.
    static let stepHours = 0.5
    static let stepNights = 3

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)

        ToolPage(ToolKind.travel.title) {
            if let prefs = store.record.trip, let plan = TravelPlan(prefs: prefs, day: day) {
                planned(plan, prefs: prefs)
            } else {
                ToolHero(eyebrow: "No trip planned",
                         headline: "Tell it where you are going.",
                         lead: "A destination and a departure day are enough.",
                         rest: "It then moves your sleep in steps before you fly and times light after you land.")
                ToolStats([
                    SomaStat("Time zones", value: nil),
                    SomaStat("In the air", value: nil),
                    SomaStat("To adjust", value: nil, unit: "days"),
                ])
                ToolNextCard(eyebrow: "Start", aspect: .sleep, title: "Plan a trip",
                             detail: "Nothing changes until you do.", actionTitle: "Plan", action: { editing = true })
            }
            ToolLinkRow(title: "About Travel", detail: nil, value: ToolRoute.intro(.travel))
        }
        .sheet(isPresented: $editing) { TripSheet() }
        .task {
            store.markOpened(.travel)
            await model.load(health)
        }
    }

    @ViewBuilder
    private func planned(_ plan: TravelPlan, prefs: TripPrefs) -> some View {
        ToolHero(eyebrow: "\(prefs.place) · \(ToolFormat.day(prefs.departs, weekday: true))",
                 headline: "\(ToolFormat.capitalized(ToolFormat.words(plan.zones))) hours \(plan.east ? "east" : "west"), taken in steps.",
                 lead: plan.steps.first.map { "Move bedtime half an hour \(plan.east ? "earlier" : "later") each night from \(ToolFormat.day($0.date, weekday: true))." }
                    ?? "The flight is too close to shift before it.",
                 rest: "On arrival, \(plan.east ? "get outside before noon and keep light low after 20:00" : "seek the evening light and keep the early morning dim"); most of the lag should lift by \(ToolFormat.day(plan.settledBy, weekday: true)).")
        ToolStats([
            SomaStat("Time zones", value: "\(plan.east ? "+" : "−")\(plan.zones)"),
            SomaStat("In the air", value: prefs.flightHours.map { ToolFormat.hoursMinutes($0) }),
            SomaStat("To adjust", value: "\(plan.recoveryDays)", unit: "days"),
        ])
        if !plan.steps.isEmpty {
            ToolRowsCard(title: "Before you fly", eyebrow: "Sleep window, \(plan.windowLabel)", aspect: .sleep,
                         rows: plan.steps.map { step in
                             ToolRow(title: step.isTonight ? "Tonight" : ToolFormat.shortDay(step.date),
                                     detail: "\(ToolFormat.clock(hour: step.bed)) to \(ToolFormat.clock(hour: step.wake))",
                                     value: step.shift == 0 ? "As usual" : "\(ToolFormat.span(hours: step.shift)) \(plan.east ? "earlier" : "later")",
                                     band: ToolBand(range: 0...Double(plan.zones), usual: 0...step.shift, value: nil))
                         })
        }
        ToolEyebrow("After you land, \(prefs.place) time")
        ToolRowsCard(aspect: .sleep, rows: plan.afterLanding.map {
            ToolRow(title: $0.title, detail: $0.detail, value: $0.value)
        })
        ToolEyebrow("The first evening away")
        ToolRowsCard(rows: [
            ToolRow(title: "Cut caffeine early", detail: "The last cup eight hours before bed."),
            ToolRow(title: "Bring home with you", detail: "Your pillowcase, the same wind-down sounds."),
            ToolRow(title: "Cool and dark", detail: "Block stray light and mask hallway noise."),
            ToolRow(title: "Keep your wind-down hour", detail: "Start at the usual time, in \(prefs.place) time."),
        ].map { var row = $0; row.value = ""; return row })
        ToolFootnote("Not medical advice. Ask a clinician if you take medication, are pregnant or have a heart or clotting condition.")
        ToolNextCard(eyebrow: "Your trip", aspect: .sleep, title: "Change the trip",
                     detail: "The plan follows the destination and the day.", actionTitle: "Edit", action: { editing = true })
    }
}

/// The trip turned into steps and days.
struct TravelPlan {
    struct Step {
        var date: Date
        var bed: Double
        var wake: Double
        var shift: Double
        var isTonight: Bool
    }

    struct Line {
        var title: String
        var detail: String
        var value: String
    }

    let zones: Int
    let east: Bool
    let recoveryDays: Int
    let settledBy: Date
    let steps: [Step]
    let afterLanding: [Line]
    let windowLabel: String

    init?(prefs: TripPrefs, day: ToolDay) {
        let calendar = day.calendar
        let trip = SomaTools.Trip(id: UUID(), startDate: prefs.departs, destinationName: prefs.place,
                                  destinationTimeZoneID: prefs.timeZone)
        let shift = SomaTools.TripPlanner.arrivalShiftHours(
            trip: SomaTools.Trip(id: trip.id, startDate: prefs.departs, destinationName: prefs.place,
                                 destinationTimeZoneID: prefs.timeZone,
                                 legs: [SomaTools.TripLeg(id: UUID(), arriveAt: prefs.departs, toTimeZoneID: prefs.timeZone)]))
        guard let shift, let state = SomaTools.JetLagModel.state(shiftHours: shift, daysSinceArrival: 0,
                                                                 daylightMin: day.inputs.daylightToday ?? 30)
        else { return nil }
        zones = state.zones
        east = shift > 0
        recoveryDays = state.recoveryDays
        let arrival = calendar.startOfDay(for: prefs.departs)
        settledBy = calendar.date(byAdding: .day, value: state.recoveryDays, to: arrival) ?? arrival

        let bed = day.habitualSleepHour ?? SomaTools.TravelActionPlanner.fallbackSleepHour
        let wake = day.habitualWakeHour ?? SomaTools.TravelActionPlanner.fallbackWakeHour
        let today = calendar.startOfDay(for: day.inputs.now)
        let daysOut = calendar.dateComponents([.day], from: today, to: arrival).day ?? 0
        let nights = min(TravelPage.stepNights, max(daysOut, 0))
        var steps: [Step] = []
        if nights > 0 {
            for index in 0...nights {
                guard let date = calendar.date(byAdding: .day, value: index - nights, to: arrival), date >= today else { continue }
                let moved = min(Double(index) * TravelPage.stepHours, Double(state.zones))
                let signed = east ? -moved : moved
                steps.append(Step(date: date, bed: bed + signed, wake: wake + signed, shift: moved,
                                  isTonight: calendar.isDate(date, inSameDayAs: today)))
            }
        }
        self.steps = steps
        windowLabel = "\(ToolFormat.clock(hour: bed)) to \(ToolFormat.clock(hour: wake))"

        let actions = SomaTools.TravelActionPlanner.plan(state: state, habitualWakeHour: wake, habitualSleepHour: bed)
        func summary(_ list: [SomaTools.TravelAction]) -> String {
            list.filter { $0.kind != .sleep && $0.kind != .melatonin }.map { action in
                "\(action.title) \(ToolFormat.clock(hour: action.startHour))"
            }.joined(separator: ". ") + ". Bed at \(ToolFormat.clock(hour: bed))."
        }
        var lines: [Line] = []
        let firstDays = min(2, state.recoveryDays)
        for dayIndex in 0..<firstDays {
            let date = calendar.date(byAdding: .day, value: dayIndex, to: arrival) ?? arrival
            lines.append(Line(title: ToolFormat.day(date, weekday: true), detail: summary(actions), value: "Day \(dayIndex + 1)"))
        }
        if state.recoveryDays > 2 {
            lines.append(Line(title: "The days after", detail: "Back to your \(ToolFormat.clock(hour: bed)) window.",
                              value: "Days 3 to \(state.recoveryDays)"))
        }
        afterLanding = lines
    }
}

/// Planning a trip: where, which time zone, and when.
struct TripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var place = ""
    @State private var zone = TimeZone.current.identifier
    @State private var departs = Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
    @State private var flightHours = 8

    private var store: ToolsStore { .shared }

    var body: some View {
        NavigationStack {
            ListScaffold(eyebrow: "Travel", title: "Your trip") {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        TextField("Destination", text: $place)
                            .somaFont(theme.typography.body)
                        ToolHairline()
                        Picker("Time zone", selection: $zone) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                        }
                        .tint(theme.colors.inkSecondary.color)
                        ToolHairline()
                        DatePicker("Departs", selection: $departs, in: Date()..., displayedComponents: .date)
                        ToolHairline()
                        Stepper("In the air: \(flightHours) h", value: $flightHours, in: 1...20)
                    }
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                }
                if store.record.trip != nil {
                    ToolButtonRow(title: "Remove the trip", detail: nil) {
                        store.update { $0.trip = nil }
                        dismiss()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = place.trimmingCharacters(in: .whitespaces)
                        store.update {
                            $0.trip = TripPrefs(place: name.isEmpty ? zone.split(separator: "/").last.map(String.init) ?? zone : name,
                                                timeZone: zone, departs: departs, flightHours: Double(flightHours))
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let trip = store.record.trip {
                    place = trip.place
                    zone = trip.timeZone
                    departs = trip.departs
                    flightHours = Int(trip.flightHours ?? 8)
                }
            }
        }
    }
}
