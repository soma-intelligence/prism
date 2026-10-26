//
//  AgingPacePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Aging Pace: how many years of aging the body takes on per calendar year,
/// the biological age behind it, what drives it and the lever that moves it.
///
/// The biological age model: each longitudinal signal (resting heart rate,
/// HRV, VO₂ max, sleep) read against reference ranges for the age and sex,
/// summed as years; the pace is the slope of that age over the last weeks,
/// or the model's own when it has one. It needs ninety days of coverage.
struct AgingPacePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let reading = AgingPaceReading.make(inputs: model.current, sex: store.record.screening.sex)

        ToolPage(ToolKind.agingPace.title) {
            ToolGauge(aspect: .body, fraction: reading?.model.map { min($0.reading.pace / 2, 1) },
                      display: reading?.model.map { SomaTools.AgingPace.paceText($0.reading.pace) },
                      state: reading?.model?.reading.band.label ?? reading?.gate ?? "Waiting on your age",
                      delta: nil, deltaIsWorse: false, lowLabel: "0", highLabel: "2×")

            if let reading, let aging = reading.model {
                ToolHero(headline: headline(aging.reading),
                         lead: "Biological age \(Int(aging.reading.currentBioAge.rounded())) against your \(Int(aging.reading.chronoAge)) years.",
                         rest: "Over recent weeks, each calendar year cost your body about \(months(aging.reading.pace)) months.")
            } else {
                ToolHero(headline: "The pace needs three months of heart data.",
                         lead: reading?.gate ?? "It reads your age from Apple Health, and no date of birth is set there.",
                         rest: "Resting heart rate and HRV from a watch, and VO₂ max from outdoor walks and runs, fill it in.")
            }
            ToolStats([
                SomaStat("Calendar", value: reading?.chronoAge.map { "\(Int($0))" }),
                SomaStat("Biological", value: reading?.bioAge.map { "\(Int($0.rounded()))" }),
                SomaStat("Coverage", value: reading?.coverage.map { "\($0)" }, unit: "days"),
            ])

            if store.record.screening.sex == nil {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text("The reference ranges differ by sex.")
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        ToolSettingsGroup(rows: [
                            .choice("Female", false, { store.update { $0.screening.sex = "female" } }),
                            .choice("Male", false, { store.update { $0.screening.sex = "male" } }),
                        ])
                    }
                }
            }

            if let reading, !reading.drivers.isEmpty {
                ToolRowsCard(title: "What drives it", eyebrow: "Years added or taken", aspect: .body,
                             rows: reading.drivers.map { driver in
                                 ToolRow(title: driver.title, value: String(format: "%+.1f", driver.years),
                                         tone: driver.pullsYounger ? .plain : .danger)
                             })
            }

            if let reading, !reading.weekly.isEmpty {
                SomaChartCard(eyebrow: "Biological age", value: reading.bioAge.map { "\(Int($0.rounded()))" }, unit: "today",
                              note: "Twelve weeks, one point a week.") {
                    ToolHistoryChart(aspect: .body, values: reading.weekly, band: reading.chronoAge.map { ($0 - 0.5)...($0 + 0.5) },
                                     firstLabel: "12 weeks ago")
                }
            }

            if let whatIf = reading?.whatIf {
                ToolNoteCard(title: "What if",
                             lead: "Three more points of VO₂ max would take about \(String(format: "%.1f", abs(whatIf.deltaYears))) years off.",
                             rest: "Zone 2 work, two hours a week, is the usual way there.")
            }
            ToolFootnote("Wellness estimate, not a diagnosis.")
            ToolLinkRow(title: "About Aging Pace", detail: nil, value: ToolRoute.intro(.agingPace))
        }
        .task {
            store.markOpened(.agingPace)
            await model.load(health)
        }
    }

    private func headline(_ reading: SomaTools.AgingPace.Reading) -> String {
        switch reading.band {
        case .gaining: "Your markers point to aging slower than the calendar."
        case .holding: "Your markers keep pace with the calendar."
        case .faster: "Your markers point to aging faster than the calendar."
        }
    }

    private func months(_ pace: Double) -> Int { Int((pace * 12).rounded()) }
}

/// The aging model worked out from the inputs.
struct AgingPaceReading {
    var chronoAge: Double?
    var bioAge: Double?
    var coverage: Int?
    var model: SomaTools.AgingPace.Model?
    var drivers: [SomaTools.AgingPace.Driver]
    var weekly: [Double?]
    var whatIf: SomaTools.AgingPace.WhatIf?
    var gate: String?

    static func make(inputs: ToolsInputs, sex: String?) -> AgingPaceReading? {
        guard let age = inputs.ageYears else { return nil }
        let calendar = Calendar.current
        let bioSex: SomaTools.AgingBioAge.Sex = sex == "male" ? .male : .female
        func series(through end: Date?) -> SomaTools.AgingBioAge.Inputs {
            SomaTools.AgingBioAge.Inputs(
                restingHR: ToolsInputs.dailyMeans(inputs.restingHeartRate, through: end, calendar: calendar),
                hrv: ToolsInputs.dailyMeans(inputs.heartRateVariability, through: end, calendar: calendar),
                vo2Max: ToolsInputs.dailyMeans(inputs.vo2Max, through: end, calendar: calendar),
                sleepHours: inputs.nights.filter { night in end.map { night.wakeDay <= $0 } ?? true }.map(\.asleep))
        }
        let current = series(through: nil)
        guard let result = SomaTools.AgingBioAge.compute(chronologicalAge: Int(age), sex: bioSex, inputs: current) else {
            return AgingPaceReading(chronoAge: age, drivers: [], weekly: [],
                                    gate: "Not enough heart data yet to place a biological age.")
        }
        var history: [SomaTools.AgingPace.HistoryPoint] = []
        var weekly: [Double?] = []
        for week in stride(from: 11, through: 0, by: -1) {
            let end = calendar.date(byAdding: .day, value: -7 * week, to: inputs.now) ?? inputs.now
            let past = SomaTools.AgingBioAge.compute(chronologicalAge: Int(age), sex: bioSex, inputs: series(through: end))
            weekly.append(past?.unroundedAge)
            if let past { history.append(SomaTools.AgingPace.HistoryPoint(date: end, bioAge: past.unroundedAge)) }
        }
        let model = SomaTools.AgingPace.model(current: result, history: history, chronoAge: age)
        return AgingPaceReading(
            chronoAge: age, bioAge: result.unroundedAge, coverage: result.coverageDays, model: model,
            drivers: SomaTools.AgingPace.drivers(from: result.components), weekly: weekly,
            whatIf: SomaTools.AgingPace.whatIf(.vo2Max(mlKgMin: 3), chronologicalAge: Int(age), sex: bioSex, inputs: current),
            gate: model == nil ? "\(result.coverageDays) of \(SomaTools.AgingPace.minCoverageDays) days" : nil)
    }
}
