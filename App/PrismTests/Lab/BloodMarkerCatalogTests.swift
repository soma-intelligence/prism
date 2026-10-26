//
//  BloodMarkerCatalogTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The catalog is what every typed value and every printed report passes
/// through on its way into storage. A wrong factor or a unit that can never
/// match is silent: the value is refused, or stored a hundred times off, and
/// nothing on screen says why. So the catalog's own promises are checked over
/// every marker, and the factors over the conversions a lab report really
/// prints.
@Suite("Blood marker catalog")
struct BloodMarkerCatalogTests {

    func marker(_ id: String) throws -> BloodMarker {
        try #require(BloodMarkerCatalog.marker(id: id), "no marker \(id)")
    }

    func close(_ value: Double?, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < tolerance
    }

    // MARK: Promises over every marker

    @Test("The nine PhenoAge markers and the extended ones, each id once")
    func everyIDOnce() {
        let ids = BloodMarkerCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(BloodMarkerCatalog.byID.count == ids.count)
        #expect(BloodMarkerCatalog.all.filter { $0.phenoAgeKey != nil }.count == BloodMarkerKey.allCases.count)
        for key in BloodMarkerKey.allCases {
            #expect(BloodMarkerCatalog.marker(id: key.rawValue)?.phenoAgeKey == key)
        }
    }

    @Test("Every accepted unit is written the way a typed unit is normalised, or it could never match")
    func acceptedUnitsAreNormalised() {
        for marker in BloodMarkerCatalog.all {
            for unit in marker.acceptedUnits.keys {
                #expect(BloodMarkerCatalog.normalize(unit) == unit, "\(marker.id) lists \(unit)")
            }
        }
    }

    @Test("Every marker stores its own storage unit as is, and accepts the unit it shows")
    func storageAndDisplayUnitsAccepted() {
        for marker in BloodMarkerCatalog.all {
            #expect(marker.toStorage(1, from: marker.storageUnit) == 1, "\(marker.id) rescales its storage unit")
            #expect(marker.accepts(marker.displayUnit), "\(marker.id) refuses \(marker.displayUnit)")
        }
    }

    @Test("A value typed in the display unit comes back unchanged on screen")
    func displayRoundTrip() throws {
        for marker in BloodMarkerCatalog.all {
            let stored = try #require(marker.toStorage(42, from: marker.displayUnit))
            #expect(close(marker.toDisplay(stored), 42, within: 1e-9), "\(marker.id) drifts on the way back")
        }
    }

    @Test("A reference range runs low to high")
    func rangesAreOrdered() {
        for marker in BloodMarkerCatalog.all {
            if let low = marker.refLow, let high = marker.refHigh {
                #expect(low < high, "\(marker.id) runs \(low) to \(high)")
            }
        }
    }

    @Test("No two markers answer to the same label once case and accents are folded")
    func labelsAreUnambiguous() {
        func fold(_ text: String) -> String {
            text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var owner: [String: String] = [:]
        for marker in BloodMarkerCatalog.all {
            for label in Set(([marker.name] + marker.aliases).map(fold)) {
                if let other = owner[label] {
                    Issue.record("\"\(label)\" reads as both \(other) and \(marker.id)")
                }
                owner[label] = marker.id
            }
        }
    }

    // MARK: Units a report prints

    @Test("Cholesterol in mmol/L and g/L lands in mg/dL")
    func lipids() throws {
        let total = try marker("totalCholesterol")
        #expect(close(total.toStorage(5.17, from: "mmol/L"), 199.9, within: 0.1))
        #expect(close(total.toStorage(2.0, from: "g/L"), 200))
        let triglycerides = try marker("triglycerides")
        #expect(close(triglycerides.toStorage(1.7, from: "mmol/L"), 150.6, within: 0.1))
    }

    @Test("Vitamin D in nmol/L and insulin in µIU/mL land in the stored units")
    func vitaminsAndInsulin() throws {
        let vitaminD = try marker("vitaminD")
        let insulin = try marker("insulin")
        #expect(close(vitaminD.toStorage(75, from: "nmol/L"), 30.0, within: 0.1))
        #expect(close(insulin.toStorage(10, from: "\u{00B5}IU/mL"), 69.45))
    }

    @Test("Fasting glucose is stored in mmol/L and shown in mg/dL")
    func glucose() throws {
        let glucose = try marker(BloodMarkerKey.glucose.rawValue)
        #expect(close(glucose.toStorage(90, from: "mg/dL"), 4.995, within: 0.001))
        #expect(close(glucose.toDisplay(5.0), 90.09))
        let albumin = try marker(BloodMarkerKey.albumin.rawValue)
        #expect(close(albumin.toDisplay(45), 4.5))
    }

    @Test("The micro sign, the Greek mu, a plain u and stray spaces are one unit")
    func microSpellings() throws {
        let ferritin = try marker("ferritin")
        for unit in ["\u{00B5}g/L", "\u{03BC}g/L", "ug/l", "ug / L", "ng/mL"] {
            #expect(ferritin.toStorage(80, from: unit) == 80, "\(unit) refused")
        }
    }

    @Test("A unit the marker does not take is refused rather than guessed")
    func unknownUnit() throws {
        let hba1c = try marker("hba1c")
        #expect(hba1c.toStorage(42, from: "mmol/mol") == nil)
        #expect(!hba1c.accepts("mmol/mol"))
    }

    // MARK: Range badges

    @Test("A value on the edge of its range is still in it")
    func rangeEdges() throws {
        let ldl = try marker("ldl")
        #expect(ldl.status(forStorage: 130) == .normal)
        #expect(ldl.status(forStorage: 131) == .high)

        let hdl = try marker("hdl")
        #expect(hdl.status(forStorage: 40) == .normal)
        #expect(hdl.status(forStorage: 39) == .low)
    }

    @Test("Any coronary calcium reads high; a marker with no range reads unknown")
    func openRanges() throws {
        let calcium = try marker("cacScore")
        #expect(calcium.status(forStorage: 0) == .normal)
        #expect(calcium.status(forStorage: 1) == .high)
        let testosterone = try marker("testosterone")
        #expect(testosterone.status(forStorage: 18) == .unknown)
    }

    // MARK: Groups and custom markers

    @Test("Groups follow the panel's order and keep every marker")
    func grouping() {
        let groups = BloodMarkerCatalog.grouped(BloodMarkerCatalog.all)
        let orders = groups.map(\.category.sortOrder)
        #expect(orders == orders.sorted())
        #expect(groups.reduce(0) { $0 + $1.items.count } == BloodMarkerCatalog.all.count)
        #expect(groups.allSatisfy { group in group.items.allSatisfy { $0.category == group.category } })
        #expect(Set(BloodMarkerCategory.allCases.map(\.sortOrder)).count == BloodMarkerCategory.allCases.count)
    }

    @Test("A marker the catalog does not know gets a stable id from its name")
    func customIDs() {
        #expect(BloodMarkerCatalog.customID(for: "Omega 3 Index") == "custom:omega-3-index")
        #expect(BloodMarkerCatalog.customID(for: "%") == "custom:marker")
    }

    @Test("An unknown value is read in its own unit, with its own name and no range")
    func customDefinition() {
        let value = BloodMarkerValue(key: "custom:omega-3-index", value: 6.2, enteredUnit: "%",
                                     source: .manual, customName: "Omega 3 Index")
        let definition = BloodMarkerCatalog.definition(for: value)
        #expect(definition.name == "Omega 3 Index")
        #expect(definition.category == .other)
        #expect(definition.toStorage(6.2, from: "%") == 6.2)
        #expect(definition.status(forStorage: 6.2) == .unknown)

        let known = BloodMarkerValue(key: "ferritin", value: 80, enteredUnit: "ng/mL", source: .extracted)
        #expect(BloodMarkerCatalog.definition(for: known).name == "Ferritin")
    }
}
