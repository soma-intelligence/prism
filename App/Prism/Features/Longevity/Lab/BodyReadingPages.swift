//
//  BodyReadingPages.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - Weight

/// Weight from Health: the latest against its usual band, the change over
/// three periods, what the weight is made of, and the weigh-in, which writes
/// to Health.
struct WeightPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var weights: [LabPoint] = []
    @State private var lean: LabPoint?
    @State private var fat: LabPoint?
    @State private var isLogging = false

    var body: some View {
        let now = Date.now
        let latest = weights.last
        let month = weights.filter { $0.date >= now.addingTimeInterval(-30 * 86_400) }
        let band = LabMath.usualBand(month.map(\.value))
        let twelve = LabMath.change(weights, days: 84, now: now, calendar: .current)
        TabPartScaffold(
            aspect: nil,
            eyebrow: latest.map { "Last weighed · \($0.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))" },
            title: latest.map { "\(LabMath.format($0.value, decimals: 1) ?? "-") kg\(abs(twelve ?? 1) < 0.5 ? ", and steady." : ".")" } ?? "No weight yet.",
            reason: reason(twelve: twelve),
            stats: []
        ) {
            SomaChartCard(
                eyebrow: "Weight",
                value: latest.flatMap { LabMath.format($0.value, decimals: 1) },
                unit: "kg",
                note: band.map { "30 days. Usually \(LabMath.format($0.lowerBound, decimals: 1) ?? "") to \(LabMath.format($0.upperBound, decimals: 1) ?? "")." }
                    ?? (latest == nil ? "A scale that writes to Health, or the weigh-in below, draws this." : "A few more weigh-ins draw your usual band.")
            ) {
                if month.count >= 2 { LabLineChart(points: month, band: band) }
            }
            coaching(MetricCoaching.weight, latest?.value, usual: band)
            LabRowGroup(heading: "By period", rows: [(7, "7 days"), (30, "30 days"), (84, "12 weeks")].map { days, title in
                LabRow(title, detail: LabMath.change(weights, days: days, now: now, calendar: .current)
                    .flatMap { LabMath.signed($0, decimals: 1) }.map { "\($0) kg" } ?? "-")
            })
            LabRowGroup(heading: "What it is made of", rows: [
                LabRow("Lean body mass", detail: lean.flatMap { LabMath.format($0.value, decimals: 1) }.map { "\($0) kg" } ?? "-", route: .leanMass),
                LabRow("Body fat", detail: fat.flatMap { LabMath.format($0.value * 100, decimals: 1) }.map { "\($0)%" } ?? "-"),
            ])
            LabLogCard(eyebrow: "Weigh-in", title: "Mornings, before breakfast",
                       detail: "Same scale, same time: the line stays honest.", actionTitle: "Log weight",
                       aspect: .body) { isLogging = true }
        }
        .labPageTitle(Text("Weight"))
        .task { await load() }
        .somaRefreshable { await load() }
        .sheet(isPresented: $isLogging, onDismiss: { Task { await load() } }) {
            LabLogSheet(kind: .weight, start: latest?.value)
        }
    }

    private func reason(twelve: Double?) -> String {
        guard !weights.isEmpty else { return "Weigh in here or with a scale that writes to Health, and the trend starts on the second morning." }
        guard let twelve else { return "Twelve weeks of weigh-ins show the trend beneath the day to day." }
        let direction = twelve < 0 ? "Down" : "Up"
        return "\(direction) \(LabMath.format(abs(twelve), decimals: 1) ?? "") kg in 12 weeks. Body fat and lean mass from a smart scale show which one moved."
    }

    private func load() async {
        let now = Date()
        guard let source = await health.prepare([LabMetric.bodyMass, LabMetric.leanBodyMass, LabMetric.bodyFat]) else { return }
        weights = await LabHealth.points(LabMetric.bodyMass, days: 120, now: now, calendar: .current, in: source)
        lean = await LabHealth.points(LabMetric.leanBodyMass, days: 365, now: now, calendar: .current, in: source).last
        fat = await LabHealth.points(LabMetric.bodyFat, days: 365, now: now, calendar: .current, in: source).last
    }
}

// MARK: - Blood pressure

/// Blood pressure from Health: the latest reading, the last ten as columns
/// against 120/80, each half against your usual, and the next reading.
struct BloodPressurePage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var readings: [PressureReading] = []
    @State private var isLogging = false

    var body: some View {
        let last = readings.last
        let ten = Array(readings.suffix(10))
        let under = ten.filter { $0.systolic < 120 && $0.diastolic < 80 }.count
        let average = ten.isEmpty ? nil : (LabMath.mean(ten.map(\.systolic))!, LabMath.mean(ten.map(\.diastolic))!)
        TabPartScaffold(
            aspect: nil,
            eyebrow: last.map { "\($0.date.labDay) · \($0.date.formatted(date: .omitted, time: .shortened))" },
            title: last.map { "\(Int($0.systolic))/\(Int($0.diastolic)), \($0.systolic < 120 && $0.diastolic < 80 ? "under the line." : "over the line.")" } ?? "No reading yet.",
            reason: last == nil
                ? "A cuff that writes to Health, or a reading logged here, starts this page."
                : "\(under) of your last \(ten.count) readings sat under 120/80.",
            stats: []
        ) {
            SomaChartCard(
                eyebrow: "Blood pressure",
                value: last.map { "\(Int($0.systolic))/\(Int($0.diastolic))" },
                unit: "mmHg",
                note: last == nil ? "Your readings draw here, the normal zone behind them." : "The last \(ten.count), 120 and 80 marked."
            ) {
                if !ten.isEmpty { LabPressureChart(readings: ten) }
            }
            coaching(MetricProfile.systolic, last?.systolic, secondary: last?.diastolic)
            if let last {
                LabBandCard(title: "Against your usual", eyebrow: "Last ten readings", aspect: .heart, items: [
                    usualItem("Systolic", last.systolic, ten.map(\.systolic), lo: 90, hi: 160),
                    usualItem("Diastolic", last.diastolic, ten.map(\.diastolic), lo: 50, hi: 110),
                    LabBandItem(id: "avg", title: "Average", detail: "aim under 120/80",
                                value: average.map { "\(Int($0.0.rounded()))/\(Int($0.1.rounded()))" },
                                band: 0...((120 - 90) / 70.0),
                                position: average.map { min(max(($0.0 - 90) / 70, 0), 1) },
                                isFlagged: (average?.0 ?? 0) >= 120 || (average?.1 ?? 0) >= 80),
                ])
                LabRowGroup(heading: "By period", rows: [
                    LabRow("Last 7 days", detail: text(readings.filter { $0.date >= .now.addingTimeInterval(-7 * 86_400) })),
                    LabRow("Last 10 readings", detail: text(ten)),
                ])
            }
            LabLogCard(eyebrow: "Next reading", title: "Tomorrow morning",
                       detail: "Seated, arm at heart height, after five quiet minutes.", actionTitle: "Log reading",
                       aspect: .heart) { isLogging = true }
        }
        .labPageTitle(Text("Blood Pressure"))
        .task { await load() }
        .somaRefreshable { await load() }
        .sheet(isPresented: $isLogging, onDismiss: { Task { await load() } }) {
            LabLogSheet(kind: .pressure, start: last?.systolic, second: last?.diastolic)
        }
    }

    private func usualItem(_ title: String, _ value: Double, _ values: [Double], lo: Double, hi: Double) -> LabBandItem {
        let band = LabMath.usualBand(values)
        func p(_ v: Double) -> Double { min(max((v - lo) / (hi - lo), 0), 1) }
        return LabBandItem(
            id: title, title: title,
            detail: band.map { "usual \(Int($0.lowerBound.rounded())) to \(Int($0.upperBound.rounded()))" } ?? "a few more readings for your usual",
            value: "\(Int(value))", band: band.map { p($0.lowerBound)...p($0.upperBound) }, position: p(value))
    }

    private func text(_ readings: [PressureReading]) -> String {
        guard let s = LabMath.mean(readings.map(\.systolic)), let d = LabMath.mean(readings.map(\.diastolic)) else { return "-" }
        return "\(Int(s.rounded()))/\(Int(d.rounded()))"
    }

    private func load() async {
        guard let source = await health.prepare([LabMetric.systolic, LabMetric.diastolic]) else { return }
        readings = await LabHealth.pressures(days: 90, now: .now, calendar: .current, in: source)
    }
}

// MARK: - Lean body mass

/// Lean body mass: Health's readings over the year and its share of your
/// weight.
struct LeanMassPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var lean: [LabPoint] = []
    @State private var weight: LabPoint?
    @State private var isLogging = false

    var body: some View {
        let latest = lean.last
        let first = lean.first
        let share = latest.flatMap { l in weight.map { l.value / $0.value * 100 } }
        TabPartScaffold(
            aspect: nil,
            eyebrow: first.map { "Since \($0.date.labDay)" },
            title: latest.map { l in
                let change = first.map { l.value - $0.value } ?? 0
                let base = "\(LabMath.format(l.value, decimals: 1) ?? "-") kg"
                guard abs(change) >= 0.1, let first else { return base + "." }
                return base + ", \(LabMath.format(abs(change), decimals: 1) ?? "") \(change > 0 ? "more" : "less") than on \(first.date.labDay)."
            } ?? "No lean mass yet.",
            reason: latest == nil
                ? "A smart scale that writes to Health gives a first number."
                : "From Health, as your scale wrote it.",
            stats: [
                SomaStat("Lean mass", value: latest.flatMap { LabMath.format($0.value, decimals: 1) }, unit: "kg"),
                SomaStat("Of weight", value: share.flatMap { LabMath.format($0, decimals: 0) }, unit: "%"),
            ]
        ) {
            SomaChartCard(
                eyebrow: "Lean mass",
                value: latest.flatMap { LabMath.format($0.value, decimals: 1) },
                unit: "kg",
                note: lean.count >= 2 ? "\(lean.count) readings in a year." : "A second reading draws the line."
            ) {
                if lean.count >= 2 { LabLineChart(points: lean) }
            }
            coaching(MetricCoaching.leanMass, latest?.value, usual: LabMath.usualBand(lean.suffix(10).map(\.value)))
            SomaChartCard(eyebrow: "By region", value: nil, unit: "kg lean", note: "Your first visit to the pod draws this.") {
                BodySilhouette()
            }
            if !lean.isEmpty {
                LabRowGroup(heading: "Reading by reading", rows: lean.suffix(5).reversed().map { point in
                    LabRow(point.date.labDay, detail: "\(LabMath.format(point.value, decimals: 1) ?? "-") kg")
                })
            }
            LabLogCard(eyebrow: "Log", title: "From a scale or a scan",
                       detail: "Written to Health, where the scale’s own readings land too.", actionTitle: "Log lean mass",
                       aspect: .body) { isLogging = true }
        }
        .labPageTitle(Text("Lean Body Mass"))
        .task { await load() }
        .somaRefreshable { await load() }
        .sheet(isPresented: $isLogging, onDismiss: { Task { await load() } }) {
            LabLogSheet(kind: .leanMass, start: latest?.value)
        }
    }

    private func load() async {
        let now = Date()
        guard let source = await health.prepare([LabMetric.leanBodyMass, LabMetric.bodyMass]) else { return }
        lean = await LabHealth.points(LabMetric.leanBodyMass, days: 365, now: now, calendar: .current, in: source)
        weight = await LabHealth.points(LabMetric.bodyMass, days: 365, now: now, calendar: .current, in: source).last
    }
}

// MARK: - Blood glucose

/// Blood glucose from Health: fasting in the morning, how far the day rose
/// above where it started, HbA1c from the blood panel, and the day's line.
///
/// When more than 70 % of the fortnight's readings sit in a monitor's trace
/// the page is `GlucosePage` instead, under the same title: a finger stick's
/// fasting value says little next to a monitor's day.
struct BloodGlucosePage: View {
    /// Open the monitor's page whatever the readings, as `LabRoute.cgm` does:
    /// without a monitor it says what fills it.
    var opensMonitor = false

    @Environment(HealthDashboard.self) private var health

    @State private var samples: [HealthReading] = []
    @State private var readings: [LabPoint] = []
    @State private var isLoaded = false
    @State private var panels = BloodPanelStore.shared
    @State private var isLogging = false

    private var showsMonitor: Bool {
        opensMonitor || GlucoseSummary.isContinuous(samples.sorted { $0.start < $1.start })
    }

    var body: some View {
        Group {
            if showsMonitor {
                GlucosePage(samples: samples, isLoaded: isLoaded)
            } else {
                fingerSticks
            }
        }
        .labPageTitle(Text(showsMonitor ? "Glucose" : "Blood Glucose"))
        .task { await load() }
        .somaRefreshable { await load() }
        .sheet(isPresented: $isLogging, onDismiss: { Task { await load() } }) {
            LabLogSheet(kind: .glucose, start: readings.last?.value)
        }
    }

    @ViewBuilder
    private var fingerSticks: some View {
        let calendar = Calendar.current
        let fasting = GlucoseDays.fasting(readings, calendar: calendar)
        let today = readings.filter { calendar.isDateInToday($0.date) }
        let rise = GlucoseDays.rise(today)
        let hba1c = panels.latest?.value("hba1c").map { LabMath.reading($0).text }
        let usualFasting = LabMath.usualBand(fasting.map(\.value))
        let chartPoints = today.count >= 2 ? today : Array(readings.suffix(20))
        TabPartScaffold(
            aspect: nil,
            eyebrow: readings.last.map { "\(calendar.isDateInToday($0.date) ? "Today" : $0.date.labDay) · \($0.date.formatted(date: .omitted, time: .shortened))" },
            title: title(rise: rise, fasting: fasting.last?.value),
            reason: reason(fasting: fasting.last?.value, hba1c: hba1c),
            stats: [
                SomaStat("Fasting", value: fasting.last.flatMap { LabMath.format($0.value, decimals: 0) }),
                SomaStat("Rise today", value: rise.flatMap { LabMath.signed($0, decimals: 0) }),
                SomaStat("HbA1c", value: hba1c),
            ]
        ) {
            SomaChartCard(
                eyebrow: today.count >= 2 ? "Today" : "Recent readings",
                value: readings.last.flatMap { LabMath.format($0.value, decimals: 0) },
                unit: "mg/dL",
                note: readings.isEmpty ? "A monitor or a meter that writes to Health draws this." : "70 to 99 is the fasting range; after a meal it rises and settles."
            ) {
                if chartPoints.count >= 2 { LabLineChart(points: chartPoints, band: 70...99, aspect: .gut) }
            }
            coaching(MetricCoaching.glucose, fasting.last?.value, usual: usualFasting)
            if !fasting.isEmpty {
                LabBandCard(title: "Against your usual", eyebrow: "Last 14 days", aspect: .gut, items: [
                    LabBandItem(id: "fasting", title: "Fasting glucose",
                                detail: usualFasting.map { "usual \(Int($0.lowerBound)) to \(Int($0.upperBound))" } ?? "70 to 99",
                                value: fasting.last.map { "\(Int($0.value)) mg/dL" },
                                band: position(70)...position(99),
                                position: fasting.last.map { position($0.value) },
                                isFlagged: (fasting.last?.value ?? 0) >= 100),
                    LabBandItem(id: "rise", title: "Rise today", detail: "above the day’s first reading",
                                value: rise.flatMap { LabMath.signed($0, decimals: 0) },
                                band: 0...0.4, position: rise.map { min(max($0 / 100, 0), 1) },
                                isFlagged: (rise ?? 0) > 40),
                ])
            }
            if let panel = panels.latest, panel.value("hba1c") != nil {
                LabRowGroup(rows: [LabRow("HbA1c", detail: hba1c, route: .marker("hba1c"))])
            }
            LabLogCard(eyebrow: "Log", title: "A finger stick or a meter",
                       detail: "Fasting, first thing, reads cleanest.", actionTitle: "Log glucose",
                       aspect: .gut) { isLogging = true }
        }
    }

    private func position(_ v: Double) -> Double { min(max((v - 50) / 150, 0), 1) }

    private func title(rise: Double?, fasting: Double?) -> String {
        if let rise { return rise > 40 ? "Today rose more than most." : "A calm day so far." }
        guard let fasting else { return "No reading yet." }
        return fasting < 100 ? "Fasting sits in range." : "Fasting sits above 99."
    }

    private func reason(fasting: Double?, hba1c: String?) -> String {
        guard let fasting else {
            return "Glucose from a continuous monitor or a meter lands here once it is in Health. HbA1c comes from your blood panel."
        }
        var text = "Fasting glucose reads \(Int(fasting)) mg/dL, against 70 to 99."
        if let hba1c { text += " HbA1c on your last panel was \(hba1c)." }
        return text
    }

    private func load() async {
        defer { isLoaded = true }
        show(await health.glucoseFortnight())
    }

    /// The raw readings for the monitor's page, and the points the finger
    /// stick page plots, read off them the way `LabHealth.points` reads.
    private func show(_ found: [HealthReading]) {
        samples = found
        readings = found.map { LabPoint(date: $0.end, value: $0.value) }.sorted { $0.date < $1.date }
    }
}

/// The Coaching card for a reading page, on the person's age and sex.
@MainActor @ViewBuilder
private func coaching(_ identifier: String, _ value: Double?, secondary: Double? = nil,
                      usual: ClosedRange<Double>? = nil) -> some View {
    let person = MetricCoaching.Person.current()
    if let advice = MetricCoaching.advice(for: identifier, value: value, secondary: secondary, usual: usual,
                                          age: person.age, sex: person.sex) {
        MetricCoachingCard(advice: advice)
    }
}

/// Glucose arithmetic: a morning's fasting value and a day's rise.
enum GlucoseDays {
    /// The first reading before 10:00 of each day.
    static func fasting(_ readings: [LabPoint], calendar: Calendar) -> [LabPoint] {
        Dictionary(grouping: readings.filter { calendar.component(.hour, from: $0.date) < 10 },
                   by: { calendar.startOfDay(for: $0.date) })
            .compactMap { $0.value.min { $0.date < $1.date } }
            .sorted { $0.date < $1.date }
    }

    /// How far a day's highest reading rose above its first. Nil below two readings.
    static func rise(_ day: [LabPoint]) -> Double? {
        guard day.count >= 2, let first = day.min(by: { $0.date < $1.date }), let high = day.map(\.value).max() else { return nil }
        return high - first.value
    }
}

// MARK: - Logging

/// The card a reading page ends on: when to take the next one, and the log.
struct LabLogCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String
    var aspect: SomaAspect = .body
    let action: () -> Void

    var body: some View {
        SomaActionCard(
            eyebrow: eyebrow,
            title: title,
            detail: LabHealthWriter.canWrite ? detail : "\(detail) Log it in the Health app: this build does not write to Health.",
            actionTitle: LabHealthWriter.canWrite ? actionTitle : nil,
            action: LabHealthWriter.canWrite ? action : nil
        ) {
            SomaObjectIcon(aspect: aspect, size: .row)
        }
    }
}

/// Logging one reading: the value on a ruler (two for blood pressure), the
/// time, and the save, which writes it to Health.
struct LabLogSheet: View {
    enum Kind {
        case weight, pressure, leanMass, glucose

        var title: String {
            switch self {
            case .weight: "Log weight"
            case .pressure: "Log a reading"
            case .leanMass: "Log lean mass"
            case .glucose: "Log glucose"
            }
        }

        var unit: String {
            switch self {
            case .weight, .leanMass: "kg"
            case .pressure: "mmHg"
            case .glucose: "mg/dL"
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .weight: 30...250
            case .leanMass: 20...120
            case .pressure: 70...220
            case .glucose: 40...400
            }
        }

        var step: Double {
            switch self {
            case .weight, .leanMass: 0.1
            case .pressure, .glucose: 1
            }
        }

        var fallback: Double {
            switch self {
            case .weight: 70
            case .leanMass: 52
            case .pressure: 120
            case .glucose: 90
            }
        }
    }

    let kind: Kind
    var start: Double?
    var second: Double?

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var value = 0.0
    @State private var low = 80.0
    @State private var date = Date()
    @State private var status: String?
    @State private var isSaving = false

    var body: some View {
        LabSheet(eyebrow: "Apple Health", title: kind.title, reason: "Written to Health, where every app you allow can read it.", doneTitle: "Cancel") {
            valueBlock(title: kind == .pressure ? "Systolic" : nil, value: $value, range: kind.range)
            if kind == .pressure {
                valueBlock(title: "Diastolic", value: $low, range: 40...140)
            }
            DatePicker("Taken", selection: $date, in: ...Date())
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
            if let status { LabFootnote(status) }
            LabPrimaryButton(title: isSaving ? "Saving" : "Save", isEnabled: !isSaving) {
                Task { await save() }
            }
        }
        .onAppear {
            value = start ?? kind.fallback
            low = second ?? 80
        }
    }

    private func valueBlock(title: String?, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: theme.metrics.spaceS) {
            if let title { LabEyebrow(title) }
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
                Text(LabMath.format(value.wrappedValue, decimals: kind.step < 1 ? 1 : 0) ?? "-")
                    .somaFont(theme.typography.metric)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(kind.unit)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            LabRuler(value: value, range: range, step: kind.step, labelEvery: kind.step < 1 ? 1 : 10,
                     spacing: kind.step < 1 ? 12 : 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let entry: LabHealthEntry = switch kind {
        case .weight: .weight(kilograms: value)
        case .leanMass: .leanMass(kilograms: value)
        case .glucose: .glucose(milligramsPerDecilitre: value)
        case .pressure: .pressure(systolic: value, diastolic: low)
        }
        switch await LabHealthWriter.save(entry, at: date) {
        case .saved: dismiss()
        case .notWritten: status = "Health is not available here, so nothing was saved."
        case .failed(let message): status = "Health did not save it: \(message)"
        }
    }
}
