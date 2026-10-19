//
//  PulseLinksPreview.swift
//  Prism
//

#if DEBUG
import Foundation

extension CauseLinks {
    /// Ninety made up days with known effects built in, run through the real
    /// engine: what the Trends page shows a person with three months of data.
    /// For previews, the render check and `-pulse.preview`. Debug builds only.
    static var preview: Output {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: previewToday)
        return compute(previewSeries(today: today, calendar: calendar), calendar: calendar)
    }

    /// The fixture's last day, which a detail sheet's ninety days end on.
    static let previewToday = Date(timeIntervalSince1970: 1_790_985_600)

    static func previewSeries(today: Date, calendar: Calendar) -> LinkSeries {
        // A fixed linear congruential generator: the same days on every run.
        var state: UInt64 = 0x5EED
        func noise(_ scale: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double(state >> 11) / Double(1 << 53)
            return (unit * 2 - 1) * scale
        }

        var series = LinkSeries()
        let days = (0..<90).compactMap { calendar.date(byAdding: .day, value: $0 - 89, to: today) }
        var alcohol: Set<Date> = []
        var sauna: Set<Date> = []
        for (index, day) in days.enumerated() {
            if index % 9 == 3 || index % 11 == 5 { alcohol.insert(day) }
            if index % 23 == 7 { sauna.insert(day) }
        }
        series.tagDays = ["alcohol": alcohol, "sauna": sauna]
        series.firstJournalDay = days.first

        for (index, day) in days.enumerated() {
            guard let evening = calendar.date(byAdding: .day, value: -1, to: day) else { continue }
            let drank = alcohol.contains(evening)

            let sleep = 7 + noise(1.1)
            series.sleepHours[day] = sleep
            series.morningHRV[day] = 52 + 6 * (sleep - 7) + (drank ? -7 : 0) + noise(6)
            series.energy[day] = 62 + 7 * (sleep - 7) + noise(9)

            let strain = 13 + noise(5)
            series.strain[day] = strain
            if let before = series.strain[evening] {
                series.recovery[day] = 68 - 2.2 * (before - 13) + noise(9)
                series.restingHeart[day] = 55 + 0.45 * (before - 13) + noise(1.6)
            }

            let steps = 9_000 + noise(4_500)
            series.steps[day] = steps
            let stepsBefore = series.steps[evening] ?? 9_000
            series.sleepScore[day] = 76 + 0.0004 * (stepsBefore - 9_000) + (drank ? -11 : 0) + noise(6)

            let light = 65 + noise(55)
            series.daylight[day] = light
            let lightBefore = series.daylight[evening] ?? 65
            series.sleepOnset[day] = 23.7 - 0.006 * (lightBefore - 65) + noise(0.45)

            // The first fortnight of daylight is missing: a watch bought late.
            if index < 14 { series.daylight[day] = nil }
        }
        return series
    }
}
#endif
