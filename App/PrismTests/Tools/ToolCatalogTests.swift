//
//  ToolCatalogTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The hub lists every tool once, in its group, and each intro page names what
/// the tool reads and the study behind it. A tool's name is also the key its
/// switch and first visit are stored under, so renaming one would lose them.
@Suite("Tool catalog")
@MainActor
struct ToolCatalogTests {
    @Test("The stored names never change: tools.json keys the switches and visits by them")
    func storedNames() {
        #expect(ToolKind.allCases.map(\.rawValue) == [
            "phaseAlignment", "sleepForecast", "smartAlarm", "socialJetlag", "napArchitect",
            "caffeineWindow", "supplementWindow",
            "eveningClose", "travel", "shiftWork",
            "sunBudget", "skinForecast",
            "agingPace", "strengthLoad", "screeningLedger",
        ])
    }

    @Test("The hub's groups hold every tool once, in catalog order")
    func groups() {
        #expect(ToolKind.Group.allCases.flatMap(\.tools) == ToolKind.allCases)
        #expect(ToolKind.Group.allCases.allSatisfy { !$0.tools.isEmpty })
    }

    @Test("Each tool has a title and a page of its own")
    func titlesAndRoutes() {
        #expect(Set(ToolKind.allCases.map(\.title)).count == ToolKind.allCases.count)
        let routes = ToolKind.allCases.map(\.route)
        #expect(Set(routes).count == routes.count)
        #expect(!routes.contains(.hub))
    }

    @Test("Each intro names what the tool reads, from a source Soma has, and a dated study")
    func intros() {
        let sources: Set<String> = ["Health", "Watch", "Soma", "Weather"]
        for kind in ToolKind.allCases {
            #expect(!kind.reads.isEmpty, "\(kind)")
            #expect(kind.reads.allSatisfy { sources.contains($0.source) }, "\(kind)")
            #expect(!kind.science.text.isEmpty, "\(kind)")
            #expect(kind.science.citation.contains { $0.isNumber }, "\(kind)")
            #expect(kind.changes.lead.hasSuffix("."), "\(kind)")
            #expect(kind.startStop.lead.hasSuffix("."), "\(kind)")
        }
    }
}
