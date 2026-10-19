//
//  ToolsSmartAlarmBedtimeSchedule.swift
//  Prism
//
//  The planning half of the bedtime reminder, alone: which nights, at what
//  time. Foundation only, no UserNotifications, no copy. The notifier builds
//  a `Schedule` from the real settings and owns everything that touches
//  notifications.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmBedtimeSchedule {

        /// Seven nights: a week away from the app keeps its reminders.
        static let horizonNights = 7

        /// What planning needs and nothing else. A flat value rather than the
        /// full settings.
        nonisolated struct Schedule: Sendable, Equatable {
            var reminderEnabled: Bool
            var leadMinutes: Double
            /// Calendar convention: 1 = Sunday, 7 = Saturday. These are the
            /// active MORNINGS, not evenings.
            var activeWeekdays: Set<Int>
            /// Minutes since midnight, the hard bound set by the user.
            var wakeMinutes: Int
            var sleepNeedSeconds: Int
            var onsetLatencySeconds: Double

            init(reminderEnabled: Bool, leadMinutes: Double, activeWeekdays: Set<Int>,
                 wakeMinutes: Int, sleepNeedSeconds: Int, onsetLatencySeconds: Double) {
                self.reminderEnabled = reminderEnabled
                self.leadMinutes = leadMinutes
                self.activeWeekdays = activeWeekdays
                self.wakeMinutes = wakeMinutes
                self.sleepNeedSeconds = sleepNeedSeconds
                self.onsetLatencySeconds = onsetLatencySeconds
            }

            /// The schedule the settings describe.
            init(settings: SmartAlarmSettings, sleepNeedSeconds: Int,
                 onsetLatencySeconds: Double = SmartWakeEngine.defaultOnsetLatencySeconds) {
                self.init(reminderEnabled: settings.bedtimeReminderEnabled,
                          leadMinutes: SmartAlarmSettings.clampBedtimeLead(settings.bedtimeReminderLeadMinutes),
                          activeWeekdays: settings.activeWeekdays,
                          wakeMinutes: settings.wakeMinutes,
                          sleepNeedSeconds: max(SmartAlarmBedtime.minimumSleepNeedSeconds, sleepNeedSeconds),
                          onsetLatencySeconds: onsetLatencySeconds)
            }
        }

        nonisolated struct Slot: Sendable, Equatable {
            let index: Int
            /// When the notification fires.
            let fireDate: Date
            let lightsOut: Date
            let ring: Date
            let timeInBedSeconds: Double
        }

        /// The nights to schedule. Pure, so the whole calendar of reminders is
        /// verifiable on fixtures.
        ///
        /// Iterates over MORNINGS from today (offset 0) forward; a morning's
        /// night is the one before it. A candidate is rejected for one of two
        /// reasons, and they weigh differently on how many offsets are scanned:
        /// an inactive weekday consumes one of the offsets, full stop
        /// (compensating would land on the SAME weekday a week later); a fire
        /// date already past is the clock having turned, and it earns one more
        /// scanned offset, up to a safety cap of `horizonNights + 2`.
        static func slots(for schedule: Schedule,
                          tonight: SmartAlarmBedtime.Reading?,
                          now: Date,
                          calendar: Calendar = .current) -> [Slot] {
            guard schedule.reminderEnabled, !schedule.activeWeekdays.isEmpty else { return [] }

            var out: [Slot] = []
            let startOfToday = calendar.startOfDay(for: now)

            var scanLimit = horizonNights
            let hardCap = horizonNights + 2
            var offset = 0
            while offset <= scanLimit, out.count < horizonNights {
                defer { offset += 1 }
                guard let morning = calendar.date(byAdding: .day, value: offset, to: startOfToday)
                else { continue }
                let weekday = calendar.component(.weekday, from: morning)
                guard schedule.activeWeekdays.contains(weekday) else { continue }

                let ring = morning.addingTimeInterval(Double(schedule.wakeMinutes) * 60)
                let reading: SmartAlarmBedtime.Reading = {
                    // The real plan only holds for the ring it carries.
                    if let tonight, calendar.isDate(tonight.ring, inSameDayAs: morning) {
                        return tonight
                    }
                    return SmartAlarmBedtime.reading(ring: ring,
                                                     sleepNeedSeconds: schedule.sleepNeedSeconds,
                                                     onsetLatencySeconds: schedule.onsetLatencySeconds,
                                                     habitualLightsOut: nil)
                }()

                let fire = reading.lightsOut.addingTimeInterval(-schedule.leadMinutes * 60)
                // Nothing in the past, with at least one minute of margin: a
                // calendar notification trigger drops the seconds, so a fire
                // date a few seconds ahead of `now` in the SAME minute would
                // never fire once truncated.
                guard fire > now.addingTimeInterval(60) else {
                    if scanLimit < hardCap { scanLimit += 1 }
                    continue
                }

                out.append(Slot(index: out.count,
                                fireDate: fire,
                                lightsOut: reading.lightsOut,
                                ring: reading.ring,
                                timeInBedSeconds: reading.timeInBedSeconds))
            }
            return out
        }
    }
}
