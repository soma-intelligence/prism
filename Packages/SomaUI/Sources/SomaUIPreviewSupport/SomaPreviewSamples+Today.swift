//
//  SomaPreviewSamples+Today.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// Sample readings for Today's body figure, its tiles and its day plan: one
/// ordinary weekday morning, every number in a believable range.
public extension SomaPreviewSamples {
    static let overnightChest: [SomaBodyCallout] = [
        SomaBodyCallout(title: "Breathing", value: "14.2", unit: "/min", note: "Usual 13.6 to 15.0"),
        SomaBodyCallout(title: "Blood oxygen", value: "97", unit: "%", note: "Usual 95 to 98"),
    ]

    static let overnightHeart: [SomaBodyCallout] = [
        SomaBodyCallout(title: "Resting heart rate", value: "52", unit: "bpm", note: "Usual 51 to 56"),
        SomaBodyCallout(title: "HRV", value: "58", unit: "ms", note: "Above usual 44 to 56", tone: .good),
    ]

    static let overnightWrist: [SomaBodyCallout] = [
        SomaBodyCallout(title: "Wrist temperature", value: "+0.12", unit: "°C", note: "Against your usual"),
    ]

    static let longTermPins: [SomaBodyFigure.Pinned] = [
        .init(.heart, SomaBodyCallout(title: "Blood pressure", value: "118/76", unit: "mmHg", note: "Cuff, Oct 20")),
        .init(.trailingLung, SomaBodyCallout(title: "VO2 max", value: "46.8", unit: "ml/kg/min", note: "Watch, 90 days")),
        .init(.innerElbow, SomaBodyCallout(title: "Blood glucose", value: "5.1", unit: "mmol/L", note: "Usual 4.6 to 5.4")),
        .init(.belly, SomaBodyCallout(title: "Weight", value: "74.2", unit: "kg", note: "Body fat 15.8 %")),
    ]

    /// Hours asleep on the last seven nights, oldest first, and the need.
    static let weekOfSleep: [Double?] = [6.7, 7.4, 6.5, 7.5, 6.9, nil, 7.2]
    static let sleepNeed = 7.67

    /// The day's plan, set on today's date.
    static func dayPlan(on day: Date = Calendar.current.startOfDay(for: .now)) -> [SomaPlanItem] {
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)) }
        return [
            SomaPlanItem(id: "wake", title: "Woke up", detail: "7 h 12 asleep", state: .done, start: at(7, 21)),
            SomaPlanItem(id: "focus", title: "Focus window", detail: "Alertness peaks until 13:00", state: .next, start: at(10, 30), end: at(13)),
            SomaPlanItem(id: "coffee", title: "Last coffee", detail: "Keeps caffeine low by bedtime", state: .later, start: at(14)),
            SomaPlanItem(id: "windDown", title: "Wind down", detail: "Lights low, screens away", state: .later, start: at(22, 45)),
            SomaPlanItem(id: "bed", title: "In bed", detail: "Gives you the 7 h 40 you need", state: .later, start: at(23, 15)),
        ]
    }

    static func planNow(on day: Date = Calendar.current.startOfDay(for: .now)) -> Date {
        day.addingTimeInterval(7 * 3600 + 42 * 60)
    }
}
