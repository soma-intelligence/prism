//
//  ToolsSmartAlarmSettings.swift
//  Prism
//
//  The alarm settings value, Codable. Every field decodes with
//  decodeIfPresent plus a default: a field added later must never wipe the
//  user's saved settings. Persistence (where the JSON lives) is the caller's
//  job; this file only owns the value, its bounds and its JSON shape.
//
//  One mode. `wakeMinutes` is ALWAYS the hard "never after" bound, and
//  `earlyWindowMinutes` says how far the app may bring the ring forward.
//  `priority` is a GOAL, not a mode: the seven engine steps all run whatever
//  its value, and `.balanced` returns exactly the earlier plan.
//

import Foundation

extension SomaTools {

    nonisolated struct SmartAlarmSettings: Codable, Equatable, Sendable {

        /// Suggested storage key for the JSON blob.
        static let storageKey = "smartAlarm.settings.v1"

        /// How far the app may bring the ring forward before the bound. `0`
        /// deliberately degenerates to a fixed alarm (`earliest == latest`).
        static let minEarlyWindowMinutes: Double = 0
        static let maxEarlyWindowMinutes: Double = 90

        /// Margin between the ring and the start of the first morning meeting.
        static let minCalendarPrepMinutes: Double = 15
        static let maxCalendarPrepMinutes: Double = 120

        /// The same bounds as a slider wants them, here so the slider and the
        /// clamp cannot diverge.
        static let earlyWindowRange = minEarlyWindowMinutes...maxEarlyWindowMinutes
        static let calendarPrepRange = minCalendarPrepMinutes...maxCalendarPrepMinutes

        static let minBedtimeLeadMinutes: Double = 0
        static let maxBedtimeLeadMinutes: Double = 120
        static let bedtimeLeadRange = minBedtimeLeadMinutes...maxBedtimeLeadMinutes

        var isEnabled: Bool
        /// Minutes since midnight. Hard bound: the ring NEVER falls after it.
        var wakeMinutes: Int
        /// Always read clamped, including from disk.
        var earlyWindowMinutes: Double
        /// The first morning meeting may bring the ring forward. Off by
        /// default: an alarm that moves on its own from the first launch
        /// would be a surprise, not a service.
        var calendarAware: Bool
        /// Always read clamped, including from disk.
        var calendarPrepMinutes: Double
        /// Calendar convention: 1 = Sunday, 7 = Saturday.
        var activeWeekdays: Set<Int>
        var snoozeEnabled: Bool
        var snoozeMinutes: Int
        /// nil means the system default alarm sound.
        var soundName: String?
        /// What the alarm optimises. Changes no engine step, only the weight
        /// of its levers.
        var priority: SmartAlarmPriority
        /// Bedtime reminder. Off by default: it rings in the evening.
        var bedtimeReminderEnabled: Bool
        /// Minutes BEFORE lights out. Always read clamped.
        var bedtimeReminderLeadMinutes: Double

        static let `default` = SmartAlarmSettings(
            isEnabled: false,
            wakeMinutes: 7 * 60,
            earlyWindowMinutes: 45,
            calendarAware: false,
            calendarPrepMinutes: 60,
            activeWeekdays: [2, 3, 4, 5, 6],
            snoozeEnabled: true,
            snoozeMinutes: 9,
            soundName: nil,
            priority: .balanced,
            bedtimeReminderEnabled: false,
            bedtimeReminderLeadMinutes: 30)

        init(isEnabled: Bool,
             wakeMinutes: Int,
             earlyWindowMinutes: Double,
             calendarAware: Bool,
             calendarPrepMinutes: Double,
             activeWeekdays: Set<Int>,
             snoozeEnabled: Bool,
             snoozeMinutes: Int,
             soundName: String?,
             priority: SmartAlarmPriority = .balanced,
             bedtimeReminderEnabled: Bool,
             bedtimeReminderLeadMinutes: Double) {
            self.isEnabled = isEnabled
            self.wakeMinutes = wakeMinutes
            self.earlyWindowMinutes = earlyWindowMinutes
            self.calendarAware = calendarAware
            self.calendarPrepMinutes = calendarPrepMinutes
            self.activeWeekdays = activeWeekdays
            self.snoozeEnabled = snoozeEnabled
            self.snoozeMinutes = snoozeMinutes
            self.soundName = soundName
            self.priority = priority
            self.bedtimeReminderEnabled = bedtimeReminderEnabled
            self.bedtimeReminderLeadMinutes = bedtimeReminderLeadMinutes
        }

        // MARK: Bounds

        static func clampEarlyWindow(_ raw: Double) -> Double {
            min(max(raw, minEarlyWindowMinutes), maxEarlyWindowMinutes)
        }

        static func clampCalendarPrep(_ raw: Double) -> Double {
            min(max(raw, minCalendarPrepMinutes), maxCalendarPrepMinutes)
        }

        static func clampBedtimeLead(_ raw: Double) -> Double {
            min(max(raw, minBedtimeLeadMinutes), maxBedtimeLeadMinutes)
        }

        // MARK: JSON

        /// Decodes a stored blob, falling back to `seed` (the default with the
        /// wake time the app already knows, when it has one) on missing or
        /// unreadable data.
        static func decoded(from data: Data?, seed: SmartAlarmSettings = .default) -> SmartAlarmSettings {
            guard let data,
                  let decoded = try? JSONDecoder().decode(SmartAlarmSettings.self, from: data)
            else { return seed }
            return decoded
        }

        /// The JSON blob to store, or nil if encoding fails.
        func encoded() -> Data? {
            try? JSONEncoder().encode(self)
        }

        /// `mode` is never written: it only exists to read settings saved
        /// before the single mode.
        private enum CodingKeys: String, CodingKey {
            case isEnabled, wakeMinutes, earlyWindowMinutes
            case calendarAware, calendarPrepMinutes
            case activeWeekdays, snoozeEnabled, snoozeMinutes, soundName
            case priority
            case bedtimeReminderEnabled, bedtimeReminderLeadMinutes
            case mode
        }

        /// Shape of the old mode value: exactly one of the two keys was written.
        private enum LegacyModeKeys: String, CodingKey {
            case window
            case optimized
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = SmartAlarmSettings.default
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
            wakeMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeMinutes) ?? fallback.wakeMinutes
            if let raw = try c.decodeIfPresent(Double.self, forKey: .earlyWindowMinutes) {
                earlyWindowMinutes = Self.clampEarlyWindow(raw)
            } else {
                earlyWindowMinutes = Self.legacyEarlyWindow(from: c) ?? fallback.earlyWindowMinutes
            }
            calendarAware = try c.decodeIfPresent(Bool.self, forKey: .calendarAware)
                ?? fallback.calendarAware
            calendarPrepMinutes = Self.clampCalendarPrep(
                try c.decodeIfPresent(Double.self, forKey: .calendarPrepMinutes)
                    ?? fallback.calendarPrepMinutes)
            activeWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .activeWeekdays)
                ?? fallback.activeWeekdays
            snoozeEnabled = try c.decodeIfPresent(Bool.self, forKey: .snoozeEnabled)
                ?? fallback.snoozeEnabled
            snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes)
                ?? fallback.snoozeMinutes
            soundName = try c.decodeIfPresent(String.self, forKey: .soundName)
            // Read as a STRING, then converted: decoding the enum directly
            // would throw on an unknown value (a newer or corrupt blob) and
            // reseed EVERY field, not just this one.
            let rawPriority = try? c.decodeIfPresent(String.self, forKey: .priority)
            priority = rawPriority.flatMap(SmartAlarmPriority.init(rawValue:)) ?? fallback.priority
            bedtimeReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .bedtimeReminderEnabled)
                ?? fallback.bedtimeReminderEnabled
            bedtimeReminderLeadMinutes = Self.clampBedtimeLead(
                try c.decodeIfPresent(Double.self, forKey: .bedtimeReminderLeadMinutes)
                    ?? fallback.bedtimeReminderLeadMinutes)
        }

        /// Written by hand: `mode` must stay out of the blob, and the sliders
        /// are clamped BEFORE they reach the disk, so a round trip can never
        /// return an out of bounds value.
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(isEnabled, forKey: .isEnabled)
            try c.encode(wakeMinutes, forKey: .wakeMinutes)
            try c.encode(Self.clampEarlyWindow(earlyWindowMinutes), forKey: .earlyWindowMinutes)
            try c.encode(calendarAware, forKey: .calendarAware)
            try c.encode(Self.clampCalendarPrep(calendarPrepMinutes), forKey: .calendarPrepMinutes)
            try c.encode(activeWeekdays, forKey: .activeWeekdays)
            try c.encode(snoozeEnabled, forKey: .snoozeEnabled)
            try c.encode(snoozeMinutes, forKey: .snoozeMinutes)
            try c.encodeIfPresent(soundName, forKey: .soundName)
            try c.encode(priority, forKey: .priority)
            try c.encode(bedtimeReminderEnabled, forKey: .bedtimeReminderEnabled)
            try c.encode(Self.clampBedtimeLead(bedtimeReminderLeadMinutes),
                         forKey: .bedtimeReminderLeadMinutes)
        }

        /// Reads a blob written before the single mode. The old optimised mode
        /// searched `[bound - 90 min, bound]`, so it becomes a 90 min early
        /// latitude; the old window mode searched `[time-flex, time+flex]`,
        /// so it becomes an early latitude of `flex`. The migration can only
        /// make the ring EARLIER, never later. `try?` everywhere: a malformed
        /// legacy blob returns nil rather than failing the whole decode.
        private static func legacyEarlyWindow(
            from container: KeyedDecodingContainer<CodingKeys>
        ) -> Double? {
            guard let mode = try? container.nestedContainer(keyedBy: LegacyModeKeys.self,
                                                            forKey: .mode) else { return nil }
            if let flex = try? mode.decodeIfPresent(Double.self, forKey: .window) {
                return clampEarlyWindow(flex)
            }
            if let optimized = try? mode.decodeIfPresent(Bool.self, forKey: .optimized),
               optimized {
                return maxEarlyWindowMinutes
            }
            return nil
        }
    }
}
