//
//  AppointmentSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Booking an appointment into the medical record, or changing one: when,
/// with whom (someone on the care team in one tap), what for, a note, and
/// the two reminders.
///
/// Opened from the record's Appointments section and from Track's "Add to
/// today" ("Appointment"). The reminders come the evening before at 18:00
/// and an hour before (`AppointmentReminderRules`).
struct AppointmentSheet: View {
    /// The appointment to change, nil for a new one.
    let appointment: Appointment?

    @Environment(\.somaTheme) private var theme
    @State private var date = AppointmentSheet.defaultDate()
    @State private var with = ""
    @State private var memberID: UUID?
    @State private var reason: Appointment.Reason? = .checkup
    @State private var notes = ""
    @State private var remind = true

    private var store: MedicalRecordStore { .shared }

    var body: some View {
        let team = store.careTeam
        HomeInputSheet(title: appointment == nil ? "Add appointment" : "Appointment", actionTitle: "Save",
                       isEnabled: reason != nil, action: save) {
            ToolSettingsGroup(rows: [
                .date(String(localized: "Day"), Binding(get: { date }, set: { day in
                    if let day { date = Self.combine(day: day, time: date) }
                })),
                .time(String(localized: "Time"), Binding(get: { ToolSettingsGroup.minutes(of: date) }, set: { minutes in
                    date = Self.combine(day: date, minutes: minutes)
                })),
            ])
            // The owner's clock is 24 hour: the picker shows 09:00, not 9:00 AM.
            .environment(\.locale, Self.twentyFourHour)
            if !team.isEmpty {
                RecordChoice(title: "From your care team", options: team.map(\.id),
                             label: { id in team.first { $0.id == id }?.name ?? "" },
                             selection: Binding(get: { memberID }, set: { id in
                                 memberID = id
                                 guard let member = team.first(where: { $0.id == id }) else { return }
                                 with = member.name
                                 if member.role == .dentist { reason = .dental }
                             }))
            }
            HomeTextField(title: "With", text: $with, prompt: "Dr Maya Chen, or the clinic")
            RecordChoice(title: "What for", options: Appointment.Reason.allCases, label: \.title, selection: $reason)
            HomeTextField(title: "Notes", text: $notes, prompt: "Questions to ask, what to bring")
            ToolSettingsGroup(rows: [.toggle(String(localized: "Remind me"), $remind)])
            ToolFootnote("The evening before at \(ScoreMath.clock(Self.eveningDate)), and an hour before.")
            if let appointment {
                RecordRemoveButton("Remove appointment") {
                    MedicalRecordStore.shared.update { $0.appointments.removeAll { $0.id == appointment.id } }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let appointment else { return }
        date = appointment.date
        with = appointment.with
        memberID = appointment.careTeamID
        reason = appointment.reason
        notes = appointment.notes ?? ""
        remind = appointment.remind
    }

    private func save() {
        guard let reason else { return }
        var entry = appointment ?? Appointment(date: date, with: "", reason: reason)
        entry.date = date
        entry.with = with.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reason = reason
        entry.notes = notes.homeNonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name typed over the one picked from the team is someone else.
        entry.careTeamID = store.record.member(memberID)?.name == entry.with ? memberID : nil
        entry.remind = remind
        store.update { record in
            if let index = record.appointments.firstIndex(where: { $0.id == entry.id }) {
                record.appointments[index] = entry
            } else {
                record.appointments.append(entry)
            }
        }
        if remind { Task { await AppointmentReminders.sync(asking: true) } }
    }

    /// Tomorrow at 9:00, the first slot most offices open.
    static func defaultDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// `day`'s date at `time`'s hour and minute.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        combine(day: day, minutes: ToolSettingsGroup.minutes(of: time), calendar: calendar)
    }

    static func combine(day: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    /// The current locale with a 00 to 23 hour cycle.
    static var twentyFourHour: Locale {
        var components = Locale.Components(locale: .current)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    /// The evening reminder's time as a date, for its 24 hour label.
    private static var eveningDate: Date {
        let rule = AppointmentReminderRules.evening
        return Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date()
    }
}

#Preview("Appointment") {
    AppointmentSheet(appointment: nil)
}
