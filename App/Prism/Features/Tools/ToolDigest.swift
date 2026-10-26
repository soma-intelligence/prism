//
//  ToolDigest.swift
//  Prism
//

import Foundation

/// The one line each tool says on the hub, read from the same numbers its
/// page shows, and whether that line is news today.
///
/// Worked out once per hub render from one ``ToolDay``; the heavier models
/// (aging pace, the sleep forecast) say what they are rather than run here.
struct ToolDigest {
    let day: ToolDay
    let scores: SomaScores?
    let store: ToolsStore.Record

    init(inputs: ToolsInputs, scores: SomaScores?, store: ToolsStore.Record) {
        self.day = ToolDay(inputs: inputs, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: scores?.sleepNeedHours)
        self.scores = scores
        self.store = store
    }

    func line(_ kind: ToolKind) -> String {
        switch kind {
        case .phaseAlignment:
            guard day.hasEnoughNights, let plan = day.plan, let score = plan.alignmentScore else {
                return "Scores after seven nights; \(day.nightCount) so far."
            }
            let next = SomaTools.CircadianPhaseAlignment.nextWindow(after: day.nowHour, in: plan.windows)
            return "\(score) today." + (next.map { " Next window at \(ToolFormat.clock(hour: $0.startHour))." } ?? "")
        case .sleepForecast:
            return day.hasEnoughNights ? "Tonight’s forecast is ready." : "Forecasts after seven nights; \(day.nightCount) so far."
        case .smartAlarm:
            guard store.alarm.isOn else { return "Off. One ring inside a window you choose." }
            return "Never after \(ToolFormat.clock(hour: Double(store.alarm.neverAfter) / 60))."
        case .socialJetlag:
            let recent = day.inputs.series(days: 28, calendar: day.calendar)
            guard let gap = SomaTools.SocialJetlag.compare(bedHours: recent.bed, wakeHours: recent.wake, today: day.inputs.now)?.signedGapHours else {
                return "Needs work nights and two free nights."
            }
            return abs(gap) < 0.25 ? "Weekends keep weekday time." : "Weekends run \(ToolFormat.span(hours: abs(gap))) \(gap > 0 ? "later" : "earlier")."
        case .napArchitect:
            guard let night = day.inputs.lastNight(calendar: day.calendar),
                  let plan = SomaTools.NapArchitectEngine.plan(lastNightBed: night.bed, wake: night.wake, now: day.inputs.now,
                                                               cbtMinHour: day.phase?.cbtMinHours ?? SomaTools.SAFTEEngine.Chronotype.intermediate.seedCBTminHour,
                                                               calendar: day.calendar)
            else { return "Needs last night’s sleep." }
            if plan.pastCutoff { return "Past the cutoff for today." }
            return plan.hasWindow ? "Window from \(ToolFormat.clock(hour: plan.windowStartHour))." : "No room for a nap today."
        case .caffeineWindow:
            guard let reading = day.caffeine else { return "Needs your bedtime from recent nights." }
            guard let last = reading.lastCall else { return "Closed for today." }
            let bed = "\(Int(reading.atBedtimeMg.rounded())) mg left at bedtime."
            return reading.lastCallHasPassed ? "Closed at \(ToolFormat.clock(last)); \(bed)" : "Open until \(ToolFormat.clock(last))."
        case .supplementWindow:
            guard !store.supplements.isEmpty else { return "Add what you take." }
            let taken = store.supplements.filter { item in store.taken[item.id]?.contains { day.calendar.isDateInToday($0) } == true }.count
            return "\(taken) of \(store.supplements.count) taken."
        case .eveningClose:
            return "Closes at \(ToolFormat.clock(hour: Double(store.evening.closes) / 60))."
        case .travel:
            guard let trip = store.trip else { return "No trip planned." }
            return "\(trip.place) on \(ToolFormat.day(trip.departs))."
        case .shiftWork:
            guard let starts = store.shift.starts else { return "Off. For nights and early starts." }
            return "Shift at \(ToolFormat.clock(hour: Double(starts) / 60))."
        case .sunBudget:
            return ToolWeather.current == nil ? "Waiting on the weather where you are." : "UV read for today."
        case .skinForecast:
            return ToolWeather.current == nil ? "Waiting on the weather where you are." : "Today’s index is ready."
        case .agingPace:
            return day.inputs.ageYears == nil ? "Needs your date of birth in Health." : "Your pace against the calendar."
        case .strengthLoad:
            let sessions = StrengthLoadPage.sessions(store.lifts)
            let report = SomaTools.StrengthLoad.report(from: sessions, endingOn: day.inputs.now)
            return report.isEmpty ? "Log sets to build the load." : "\(ToolFormat.number(report.currentVolume)) kg·reps in 7 days."
        case .screeningLedger:
            guard let age = day.inputs.ageYears else { return "Needs your date of birth in Health." }
            let sex = store.screening.sex.flatMap(SomaTools.ScreeningEligibility.from(profileSex:))
            let due = store.screening.ledger.statuses(age: Int(age), sex: sex, today: day.inputs.now)
                .filter { $0.item.tier == .recommended && $0.isDue }
            return due.isEmpty ? "Nothing due." : "\(due.count) due; \(due[0].item.title.lowercased()) first."
        }
    }

    /// Whether the tool has something to say today worth the accent dot.
    func hasNews(_ kind: ToolKind) -> Bool {
        switch kind {
        case .caffeineWindow:
            guard let reading = day.caffeine else { return false }
            return reading.atBedtimeMg > SomaTools.CaffeineModel.bedtimeThresholdMg
        case .smartAlarm:
            return store.alarm.isOn
        case .eveningClose:
            let hours = (Double(store.evening.closes) / 60 - day.nowHour + 24).truncatingRemainder(dividingBy: 24)
            return store.evening.closesByItself && hours < 4
        case .screeningLedger:
            guard let age = day.inputs.ageYears else { return false }
            let sex = store.screening.sex.flatMap(SomaTools.ScreeningEligibility.from(profileSex:))
            return store.screening.ledger.statuses(age: Int(age), sex: sex, today: day.inputs.now).contains { $0.item.tier == .recommended && $0.isDue }
        case .travel:
            guard let trip = store.trip else { return false }
            let days = day.calendar.dateComponents([.day], from: day.calendar.startOfDay(for: day.inputs.now), to: trip.departs).day ?? 99
            return (0...TravelPage.stepNights).contains(days)
        default:
            return false
        }
    }
}
