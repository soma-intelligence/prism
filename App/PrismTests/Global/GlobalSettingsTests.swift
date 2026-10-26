//
//  GlobalSettingsTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Every app wide preference sits in one small file. What is checked here is
/// that each section comes back after a relaunch, that a section or a field
/// a build cannot read costs only itself, that a file not yet opened is never
/// written over, that units start from the phone's region, and that each
/// picker offers the value it starts on.
@Suite("Global settings")
@MainActor
struct GlobalSettingsTests {
    func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    // MARK: Time of day

    @Test("A time of day wraps round the clock whichever way it is pushed")
    func clockWraps() {
        #expect(ClockTime(minutes: 1440) == ClockTime(hour: 0))
        #expect(ClockTime(minutes: -30) == ClockTime(hour: 23, minute: 30))
        #expect(ClockTime(hour: 25, minute: 15).text == "01:15")
        #expect(ClockTime(hour: 23, minute: 50).adding(minutes: 20) == ClockTime(hour: 0, minute: 10))
        let time = ClockTime(hour: 9, minute: 41)
        #expect(time.hour == 9)
        #expect(time.minute == 41)
    }

    @Test("A window inside one day holds its start but not its end, and an empty window holds nothing")
    func windows() {
        let nine = ClockTime(hour: 9), five = ClockTime(hour: 17)
        #expect(nine.isInside(from: nine, until: five))
        #expect(!five.isInside(from: nine, until: five))
        #expect(!ClockTime(hour: 8, minute: 59).isInside(from: nine, until: five))
        #expect(!nine.isInside(from: nine, until: nine))
    }

    // MARK: Pickers and units

    @Test("Every picker offers the value it starts on")
    func pickersHoldTheirDefaults() {
        let start = CustomizationPreferences()
        #expect(CustomizationPreferences.usualWindows.contains(start.usualWindowDays))
        #expect(CustomizationPreferences.moveGoals.contains(start.moveGoalKilocalories))
        #expect(CustomizationPreferences.zoneTwoTargets.contains(start.zoneTwoMinutesPerWeek))
        #expect(CustomizationPreferences.waterTargets.contains(start.waterMillilitres))
        #expect(CustomizationPreferences.mealCutoffs.contains(start.lastMealBy))
        #expect(CustomizationPreferences.mealCutoffs.first == ClockTime(hour: 17))
        #expect(CustomizationPreferences.mealCutoffs.last == ClockTime(hour: 23))
    }

    @Test("Units start from the phone's region: the United States reads imperial, elsewhere metric")
    func unitsFromRegion() {
        let us = UnitPreferences(locale: Locale(identifier: "en_US"), calendar: calendar(firstWeekday: 1))
        #expect(us.measures == .imperial)
        #expect(us.temperature == .fahrenheit)

        let france = UnitPreferences(locale: Locale(identifier: "fr_FR"), calendar: calendar(firstWeekday: 2))
        #expect(france.measures == .metric)
        #expect(france.temperature == .celsius)

        let britain = UnitPreferences(locale: Locale(identifier: "en_GB"), calendar: calendar(firstWeekday: 2))
        #expect(britain.measures == .metric)

        for units in [us, france, britain] {
            #expect(units.glucose == .milligrams)
            #expect(units.energy == .kilocalories)
            #expect(units.clock == .twentyFour)
        }
    }

    @Test("A week starts on Sunday, Monday or Saturday, and any other first day falls back to Monday")
    func weekStart() {
        let cases: [(Int, WeekStart)] = [(1, .sunday), (2, .monday), (7, .saturday), (4, .monday)]
        for (first, expected) in cases {
            let units = UnitPreferences(locale: Locale(identifier: "fr_FR"), calendar: calendar(firstWeekday: first))
            #expect(units.weekStart == expected, "first weekday \(first)")
        }
    }

    // MARK: Shortcuts

    @Test("A stored order missing a newer shortcut gets it at the end, and a hidden one keeps its place")
    func shortcutOrder() {
        var prefs = ShortcutPreferences()
        prefs.order = [.record, .sleep]
        prefs.hidden = [.sleep]
        #expect(prefs.fullOrder == [.record, .sleep, .meal, .workout, .journal, .weight])
        #expect(prefs.offered == [.record, .meal, .workout, .journal, .weight])
        #expect(ShortcutPreferences().offered == LogShortcut.allCases)
    }

    @Test("Every shortcut wears an orb but the record, which has a glyph of its own")
    func shortcutOrbs() {
        #expect(LogShortcut.allCases.filter { $0.aspect == nil } == [.record])
    }

    // MARK: The file

    @Test("Every section survives a relaunch")
    func persistence() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "settings.json")
            let settings = GlobalSettings(url: url)
            settings.notifications.morningTime = ClockTime(hour: 6, minute: 45)
            settings.notifications.quietHours = false
            settings.customization.skinType = .three
            settings.customization.answers = .detailed
            settings.units.measures = .imperial
            settings.shortcuts.hidden = [.weight]
            settings.diagnostics.shareUsage = true
            settings.programs = [ProgramEnrollment(programID: "test-program", joined: Date(timeIntervalSince1970: 1_791_028_800))]

            let reopened = GlobalSettings(url: url)
            #expect(reopened.notifications == settings.notifications)
            #expect(reopened.customization == settings.customization)
            #expect(reopened.units == settings.units)
            #expect(reopened.shortcuts == settings.shortcuts)
            #expect(reopened.diagnostics == settings.diagnostics)
            #expect(reopened.programs == settings.programs)
        }
    }

    @Test("A section this build cannot read falls back alone, and the others stay as they were")
    func oneSectionFallsBack() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "settings.json")
            let settings = GlobalSettings(url: url)
            settings.notifications.morningTime = ClockTime(hour: 6, minute: 45)
            settings.shortcuts.hidden = [.weight]
            settings.customization.waterMillilitres = 3000

            let written = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            var stored = try #require(written as? [String: Any])
            stored["customization"] = "a section this build cannot read"
            try JSONSerialization.data(withJSONObject: stored).write(to: url)

            let reopened = GlobalSettings(url: url)
            #expect(reopened.customization == CustomizationPreferences())
            #expect(reopened.notifications.morningTime == ClockTime(hour: 6, minute: 45))
            #expect(reopened.shortcuts.hidden == [.weight])
        }
    }

    @Test("A setting added since the file was written starts on its default, and the rest of its section stays")
    func oneFieldFallsBack() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "settings.json")
            let settings = GlobalSettings(url: url)
            settings.notifications.morningTime = ClockTime(hour: 6, minute: 45)
            settings.notifications.quietHours = false
            settings.customization.waterMillilitres = 3000
            settings.customization.skinType = .two

            let written = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            var stored = try #require(written as? [String: Any])
            var notifications = try #require(stored["notifications"] as? [String: Any])
            notifications["quietHours"] = nil
            stored["notifications"] = notifications
            var customization = try #require(stored["customization"] as? [String: Any])
            customization["skinType"] = 9
            stored["customization"] = customization
            try JSONSerialization.data(withJSONObject: stored).write(to: url)

            let reopened = GlobalSettings(url: url)
            #expect(reopened.notifications.morningTime == ClockTime(hour: 6, minute: 45))
            #expect(reopened.notifications.quietHours == NotificationPreferences().quietHours)
            #expect(reopened.customization.waterMillilitres == 3000)
            #expect(reopened.customization.skinType == nil)
        }
    }

    @Test("A settings file that is there but cannot be opened yet is never written over")
    func unopenedFileIsKept() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "settings.json")
            let settings = GlobalSettings(url: url)
            settings.notifications.morningTime = ClockTime(hour: 6, minute: 45)

            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            let locked = GlobalSettings(url: url)
            locked.notifications.quietHours = false
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

            let reopened = GlobalSettings(url: url)
            #expect(reopened.notifications.morningTime == ClockTime(hour: 6, minute: 45))
            #expect(reopened.notifications.quietHours == NotificationPreferences().quietHours)
        }
    }

    @Test("A file that does not read opens on the defaults")
    func unreadableFile() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "settings.json")
            try Data("{".utf8).write(to: url)
            let settings = GlobalSettings(url: url)
            #expect(settings.notifications == NotificationPreferences())
            #expect(settings.customization == CustomizationPreferences())
            #expect(settings.programs.isEmpty)
        }
    }
}
