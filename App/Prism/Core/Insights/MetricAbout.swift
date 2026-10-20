//
//  MetricAbout.swift
//  Prism
//
//  What a metric's info sheet says: what the number is, how its band is
//  read, where the readings come from and the unit. The long words live
//  here so the page itself can stay short. Wellness words only: what a
//  reading tends to follow, never a verdict on health.
//

import Foundation
import SomaUI

enum MetricAbout {
    /// One or two plain lines on what the number is, for the metrics Soma
    /// reads closely. Nil for the rest, which get a line built from the name.
    static func whatItIs(_ identifier: String) -> String? {
        switch identifier {
        case "HKQuantityTypeIdentifierStepCount":
            "Every step your phone and watch count through the day. Apple Health counts a step once when both see it."
        case "HKCategoryTypeIdentifierSleepAnalysis":
            "The time you spent asleep each night, filed under the morning you woke. Time awake in bed is left out."
        case "HKQuantityTypeIdentifierOxygenSaturation":
            "How much oxygen your blood is carrying, as your watch reads it, mostly while you sleep. It tends to sit high and steady."
        case "HKQuantityTypeIdentifierHeartRate":
            "Your heart's beats a minute, read through the day. It rises with movement, stress and heat, and settles when you rest."
        case "HKQuantityTypeIdentifierRestingHeartRate":
            "Your heart rate when you're still for a while. A lower, steady number tends to follow good sleep and regular activity."
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            "The small changes in time between heartbeats. It tends to rise when you're rested and dip after hard days, late nights or alcohol."
        case "HKQuantityTypeIdentifierRespiratoryRate":
            "Breaths a minute while you sleep. It's usually very steady, so a change from your own normal is the part worth noticing."
        case "HKQuantityTypeIdentifierAppleSleepingWristTemperature":
            "Your wrist's temperature overnight, against your own baseline. It shifts with your cycle, a warm room, a late meal or alcohol."
        case "HKQuantityTypeIdentifierVO2Max":
            "An estimate of how much oxygen your body can use during hard effort. It climbs slowly with regular cardio."
        case "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute":
            "How far your heart rate drops in the minute after a workout. A bigger drop tends to come with fitness."
        case "HKQuantityTypeIdentifierWalkingSpeed":
            "How fast you walk on flat ground, read by your phone as you go about the day."
        case "HKQuantityTypeIdentifierBodyMass":
            "Your weight, from a scale or entered by hand. Day to day it moves with water and meals, so the trend says more than one reading."
        case "HKQuantityTypeIdentifierBodyFatPercentage":
            "The share of your weight that's fat, as a smart scale estimates it. Read the trend rather than one morning."
        case "HKQuantityTypeIdentifierLeanBodyMass":
            "Your weight minus fat, as a smart scale estimates it."
        case "HKQuantityTypeIdentifierBodyMassIndex":
            "Weight against height. A rough guide that can't tell muscle from fat."
        case "HKQuantityTypeIdentifierBloodPressureSystolic", "HKQuantityTypeIdentifierBloodPressureDiastolic":
            "The pressure in your arteries as your heart beats, over the pressure between beats, from a cuff."
        case "HKQuantityTypeIdentifierBloodGlucose":
            "The sugar in your blood, from a sensor or a meter. It rises after meals and settles between them."
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            "The energy you burned moving, on top of what your body uses at rest."
        default:
            nil
        }
    }

    /// The sheet's sections for a page.
    static func sections(
        identifier: String,
        title: String,
        band: ClosedRange<Double>?,
        isReference: Bool,
        accumulates: Bool,
        hasSources: Bool,
        unit: String?,
        format: (Double) -> String
    ) -> [SomaInfoSection] {
        var sections = [
            SomaInfoSection("What it is", body: whatItIs(identifier) ?? "Your \(title.lowercased()) readings from Apple Health, day by day."),
        ]

        var usual: String
        if isReference, let band {
            usual = "The shaded band is the range most adults sit in, \(format(band.lowerBound)) to \(format(band.upperBound))\(unit.map { " \($0)" } ?? "")."
        } else {
            usual = "The shaded band is your usual: the range your last two weeks sat in. It moves with you, so a change shows against your own normal rather than anyone else's."
        }
        if accumulates {
            usual += " Today keeps adding up until midnight, so the page compares it with a usual full day."
        }
        sections.append(SomaInfoSection(isReference ? "The band" : "Your usual", body: usual))

        if hasSources {
            sections.append(SomaInfoSection(
                "Sources",
                body: "Each app or device's share of the readings in the span you're looking at, and how it took them: measured by a sensor, estimated from motion or a formula, or entered by hand."
            ))
        }
        if let unit {
            sections.append(SomaInfoSection("Unit", body: unit))
        }
        sections.append(SomaInfoSection(
            "Good to know",
            body: "Soma reads these numbers for everyday wellness. If something worries you, talk to a doctor."
        ))
        return sections
    }
}
