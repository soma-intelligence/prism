//
//  ToolFormatTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// How the tool pages write hours, spans and counts. The clock itself follows
/// the region, so it is checked for what it wraps to rather than for its
/// spelling.
@Suite("Tool format")
@MainActor
struct ToolFormatTests {
    @Test("A decimal hour past midnight, before it, or a minute short of the hour lands on the right clock time")
    func clockWraps() {
        #expect(ToolFormat.clock(hour: 25.5) == ToolFormat.clock(hour: 1.5))
        #expect(ToolFormat.clock(hour: -0.5) == ToolFormat.clock(hour: 23.5))
        #expect(ToolFormat.clock(hour: 6.9999) == ToolFormat.clock(hour: 7))
        #expect(ToolFormat.clock(hour: 23.9999) == ToolFormat.clock(hour: 0))
        #expect(ToolFormat.clock(hour: 7) != ToolFormat.clock(hour: 19))
    }

    @Test("Axis hours are two digits, round to the nearest hour and wrap the day")
    func hourLabels() {
        #expect(ToolFormat.hourLabel(22) == "22")
        #expect(ToolFormat.hourLabel(4.2) == "04")
        #expect(ToolFormat.hourLabel(25) == "01")
        #expect(ToolFormat.hourLabel(-1) == "23")
        #expect(ToolFormat.hourLabel(23.6) == "00")
    }

    @Test("Hours read as hours and minutes, whichever sign they carry")
    func hoursMinutes() {
        #expect(ToolFormat.hoursMinutes(7.2) == "7:12")
        #expect(ToolFormat.hoursMinutes(-1.5) == "1:30")
        #expect(ToolFormat.hoursMinutes(0.9999) == "1:00")
        #expect(ToolFormat.hoursMinutes(0) == "0:00")
    }

    @Test("A span drops whichever part is zero")
    func spans() {
        #expect(ToolFormat.span(hours: 3 + 28.0 / 60) == "3 h 28")
        #expect(ToolFormat.span(hours: 1 + 5.0 / 60) == "1 h 05")
        #expect(ToolFormat.span(hours: 0.75) == "45 min")
        #expect(ToolFormat.span(hours: 2) == "2 h")
        #expect(ToolFormat.span(hours: 0) == "0 min")
    }

    @Test("Counts up to twelve are words, the rest are numbers")
    func words() {
        #expect(ToolFormat.words(0) == "no")
        #expect(ToolFormat.words(3) == "three")
        #expect(ToolFormat.words(12) == "twelve")
        #expect(ToolFormat.words(13) == "13")
        #expect(ToolFormat.words(-1) == "-1")
    }

    @Test("Only the first letter is raised")
    func capitalized() {
        #expect(ToolFormat.capitalized("three nights in a row") == "Three nights in a row")
        #expect(ToolFormat.capitalized("") == "")
        #expect(ToolFormat.capitalized("REM") == "REM")
    }
}
