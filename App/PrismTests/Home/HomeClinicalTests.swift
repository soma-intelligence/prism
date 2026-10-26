//
//  HomeClinicalTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
#if canImport(HealthKit)
import HealthKit
#endif
@testable import Prism

/// The medical card leads with three facts Health keeps outside its samples.
/// Each must be a type the catalog knows, or the one sheet never asks for it
/// and the card shows a dash for ever; a blood type Health has not been told
/// must read as unknown rather than as a group.
@Suite("Medical card facts")
@MainActor
struct HomeClinicalTests {
    @Test("Date of birth, sex and blood type are characteristics the catalog knows")
    func characteristics() {
        for identifier in HomeClinical.characteristics {
            let metric = HealthMetricCatalog.metric(for: identifier)
            #expect(metric?.kind == .characteristic, "\(identifier)")
        }
    }

    #if canImport(HealthKit)
    @Test("Every blood group has its name, and an unset one has none")
    func bloodTypes() {
        let named: [(HKBloodType, String)] = [
            (.aPositive, "A positive"), (.aNegative, "A negative"),
            (.bPositive, "B positive"), (.bNegative, "B negative"),
            (.abPositive, "AB positive"), (.abNegative, "AB negative"),
            (.oPositive, "O positive"), (.oNegative, "O negative"),
        ]
        for (type, name) in named {
            #expect(HomeClinical.name(type) == name)
        }
        #expect(HomeClinical.name(.notSet) == nil)
    }
    #endif
}
