//
//  FixtureGlucose.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// A fortnight of made up monitor readings, one every five minutes, with
/// three meals a day and their rises, for looking at the glucose page on a
/// simulator. Debug only, chosen with the launch argument `-health.cgm YES`,
/// and never written anywhere: neither Health nor Track sees it.
///
/// The usual sits round 98 mg/dL, a late dinner goes over 180 most nights,
/// and every fifth night dips to 64 before dawn, so every band of the bar has something.
enum FixtureGlucose {
    /// The defaults key behind `-health.cgm YES`.
    nonisolated static let launchKey = "health.cgm"

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    /// Meals at the same hours each day: breakfast, lunch and dinner.
    private static let menu: [(hour: Double, name: String, meal: TrackMeal, carbs: Double, rise: Double)] = [
        (8, "Oats and berries", .breakfast, 55, 38),
        (12.75, "Rice bowl", .lunch, 80, 62),
        (20.5, "Pasta", .dinner, 95, 118),
    ]

    static func meals(now: Date = .now, calendar: Calendar = .current) -> [TrackMealEntry] {
        let today = calendar.startOfDay(for: now)
        return (0..<14).flatMap { day -> [TrackMealEntry] in
            guard let date = calendar.date(byAdding: .day, value: -day, to: today) else { return [] }
            return menu.compactMap { item in
                let time = date.addingTimeInterval(item.hour * 3600)
                guard time <= now else { return nil }
                return TrackMealEntry(name: item.name, meal: item.meal, protein: 25, carbs: item.carbs, fat: 18,
                                      portions: 1, date: time)
            }
        }
    }

    static func readings(now: Date = .now, calendar: Calendar = .current) -> [HealthReading] {
        let start = now.addingTimeInterval(-14 * 86_400)
        var out: [HealthReading] = []
        var time = start
        var step = 0
        while time <= now {
            let hour = calendar.component(.hour, from: time)
            let minute = calendar.component(.minute, from: time)
            let clock = Double(hour) + Double(minute) / 60
            let day = Int(time.timeIntervalSince(start) / 86_400)
            var value = 98 + sin(clock / 24 * 2 * .pi) * 6
            // The dawn rise, then each meal: up for 45 minutes, down by two hours.
            if clock >= 4, clock < 8 { value += (clock - 4) * 3 }
            for item in menu {
                let since = (clock - item.hour) * 60
                let rise = item.rise * (1 + Double((day * 37 + Int(item.hour)) % 9 - 4) / 20)
                if since >= 0, since < 45 { value += rise * since / 45 }
                if since >= 45, since < 150 { value += rise * (1 - (since - 45) / 105) }
            }
            if day % 5 == 2, clock >= 3.5, clock < 4.25 { value = 64 }
            value += Double((step * 7919) % 100) / 100 * 6 - 3
            out.append(HealthReading(
                metric: LabMetric.glucose, value: value.rounded(), unit: .milligramPerDecilitre,
                start: time, end: time, source: "Dexcom", device: "Dexcom G7", deviceModel: "G7 Dexcom"
            ))
            time = time.addingTimeInterval(300)
            step += 1
        }
        return out
    }
}
#endif
