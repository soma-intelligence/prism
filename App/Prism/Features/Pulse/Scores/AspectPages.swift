//
//  AspectPages.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - Mind

/// Mind: the Mind score (recovery, or calm when recovery is missing) with
/// its ring, a month of it against the usual, the deeper pages it is made of
/// (stress, recovery, energy), what it leans on, the one move, and the
/// readings behind it.
///
/// Opened by Mind everywhere on Today (owner, 2026-10-20: it used to open
/// Recovery).
struct MindAspectPage: View {
    @Environment(HealthDashboard.self) private var health
    @State private var inputs: ScoreDetailInputs?

    var body: some View {
        let scores = health.scores
        let recovery = ScorePages.recovery(scores, inputs)
        let lead = MindAspectPage.lead(scores, recovery: recovery.lead)

        ScorePageScaffold(aspect: .mind, title: "Mind") {
            ScoreStage(aspect: .mind, lead: lead, series: scores?.mindSeries ?? [])
            ScoreHead(lead)
            ScorePageLinks(routes: [
                (.stress, "Stress today", scores?.stress.map(String.init)),
                (.recovery, "Recovery", scores?.recovery.map(String.init)),
                (.energy, "Energy", scores?.energy.map(String.init)),
            ])
            ScoreUsualCard(title: "What it leans on", aspect: .mind, lines: recovery.lines)
            if let move = recovery.move {
                ScoreMoveCard(move: move, aspect: .mind)
            }
            AspectReadings(aspect: .mind, identifiers: AspectReadingKind.mindReadings, category: .aspect(.mind))
        }
        .scoreInputs([.heart, .breathing], into: $inputs)
    }

    /// Recovery's head when there is a recovery; on a day with only stress,
    /// the calm that stands in for it (the same choice as ``SomaScores/mind``).
    static func lead(_ scores: SomaScores?, recovery: ScorePages.Lead) -> ScorePages.Lead {
        guard scores?.recovery == nil, let mind = scores?.mind else { return recovery }
        var lead = recovery
        lead.value = mind
        lead.word = mind >= 67 ? "Calm" : mind >= 34 ? "Steady" : "Tense"
        lead.change = nil
        lead.headline = "Calm stands in until a night is scored."
        lead.reason = "Recovery needs a night of sleep and this morning's heart readings."
        lead.aside = nil
        return lead
    }
}

// MARK: - Activity

/// Activity: the day's load as the Activity score with its ring, a month of
/// it against the usual, the day's energy, steps and stand hours, the deeper
/// pages (strain, energy), the move that fits, and the readings behind it.
///
/// Opened by Activity everywhere on Today (owner, 2026-10-20: it used to
/// open Strain).
struct ActivityPage: View {
    @Environment(HealthDashboard.self) private var health
    @State private var inputs: ScoreDetailInputs?

    var body: some View {
        let scores = health.scores
        let page = ScorePages.strain(scores, inputs)

        ScorePageScaffold(aspect: .activity, title: "Activity") {
            ScoreStage(aspect: .activity, lead: page.lead, series: scores?.strainSeries ?? [], directional: false)
            ScoreHead(page.lead)
            ScoreStats(stats: [
                SomaStat("Active kcal", value: page.activeEnergy),
                SomaStat("Steps", value: page.steps),
                SomaStat("Stand hours", value: page.standHours),
            ])
            ScorePageLinks(routes: [
                (.strain, "Strain and training load", scores?.strain.map(String.init)),
                (.energy, "Energy", scores?.energy.map(String.init)),
            ])
            if let move = page.move {
                ScoreMoveCard(move: move, aspect: .activity)
            }
            AspectReadings(aspect: .activity, identifiers: AspectReadingKind.activityReadings, category: .aspect(.activity))
        }
        .scoreInputs([.today, .heartRecovery], into: $inputs)
    }
}

// MARK: - Heart, Gut, Body

/// The three aspects without a score, each led by the reading it turns on.
enum AspectReadingKind: CaseIterable, Hashable {
    case heart, gut, body

    var aspect: SomaAspect {
        switch self {
        case .heart: .heart
        case .gut: .gut
        case .body: .body
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .heart: "Heart"
        case .gut: "Gut"
        case .body: "Body"
        }
    }

    /// The reading the page leads with.
    var lead: String {
        switch self {
        case .heart: "HKQuantityTypeIdentifierRestingHeartRate"
        case .gut: "HKQuantityTypeIdentifierBloodGlucose"
        case .body: "HKQuantityTypeIdentifierBodyMass"
        }
    }

    /// Whether the lead rising is the good way, when either way means
    /// something: a lower resting rate is fitter; glucose and weight are
    /// the person's to read.
    var risingIsGood: Bool? {
        switch self {
        case .heart: false
        case .gut, .body: nil
        }
    }

    /// The readings listed at the foot, the lead first.
    var readings: [String] {
        let q = "HKQuantityTypeIdentifier"
        return switch self {
        case .heart: [q + "RestingHeartRate", q + "HeartRateVariabilitySDNN", q + "HeartRate", q + "WalkingHeartRateAverage",
                      q + "VO2Max", q + "HeartRateRecoveryOneMinute", q + "BloodPressureSystolic"]
        case .gut: [q + "BloodGlucose", q + "DietaryEnergyConsumed", q + "DietaryWater", q + "DietaryCaffeine",
                    q + "DietaryProtein", q + "DietaryFiber"]
        case .body: [q + "BodyMass", q + "BodyFatPercentage", q + "LeanBodyMass", q + "BodyMassIndex",
                     q + "WaistCircumference", q + "Height"]
        }
    }

    /// The deeper pages it links to.
    var links: [(route: ScoreRoute, title: String)] {
        switch self {
        case .heart: [(.recovery, "Recovery"), (.stress, "Stress today")]
        case .gut, .body: []
        }
    }

    static let mindReadings: [String] = [
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", "HKQuantityTypeIdentifierRestingHeartRate",
        "HKCategoryTypeIdentifierMindfulSession", "HKQuantityTypeIdentifierTimeInDaylight",
    ]

    static let activityReadings: [String] = [
        "HKQuantityTypeIdentifierStepCount", "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKQuantityTypeIdentifierAppleExerciseTime", "HKQuantityTypeIdentifierDistanceWalkingRunning",
        "HKQuantityTypeIdentifierFlightsClimbed", "HKQuantityTypeIdentifierWalkingSpeed",
    ]

    static let sleepReadings: [String] = [
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
        "HKQuantityTypeIdentifierRespiratoryRate", "HKQuantityTypeIdentifierOxygenSaturation",
    ]
}

/// Heart, Gut or Body: the lead reading with a ring that marks where today
/// sits against the usual, a month of it, the deeper pages, and the readings
/// behind the aspect. Built from the same parts as the score pages, so all
/// six aspects read alike.
struct AspectReadingPage: View {
    let kind: AspectReadingKind

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var days: [Double?] = []
    @State private var unit: String?
    @State private var isRead = false

    private var metric: HealthMetric? { HealthMetricCatalog.metric(for: kind.lead) }

    var body: some View {
        let usual = AspectPageMath.usual(days)
        let latest = AspectPageMath.latest(days)
        let format = Self.format
        let meaning = MetricPageWords.meaning(
            value: latest?.value, band: usual, isReference: false,
            known: days.compactMap { $0 }.count, todayOpen: false,
            risingIsGood: kind.risingIsGood, format: format, unit: unit
        )
        let calendar = Calendar.current
        let day = latest.flatMap { calendar.date(byAdding: .day, value: -$0.back, to: calendar.startOfDay(for: Date())) }

        ScorePageScaffold(aspect: kind.aspect, title: kind.title) {
            AspectStage(
                aspect: kind.aspect,
                lead: SomaMetricLead(
                    caption: MetricPageWords.caption(for: day, kind: .reading(manyADay: false)).map { caption in
                        "\(MetricPageWords.title(identifier: kind.lead, fallback: metric?.displayName ?? "")) · \(caption)"
                    },
                    value: latest.map { format($0.value) },
                    unit: unit,
                    meaning: isRead ? (meaning?.text ?? "Still learning your usual") : nil,
                    tone: meaning?.tone ?? .neutral
                ),
                dial: SomaStageDial(aspect: kind.aspect, scale: .marker, value: latest?.value, usual: usual),
                values: days, unit: unit, scale: nil,
                higherIsBetter: kind.risingIsGood, style: kind == .heart ? .line : .points, format: format
            )
            if !kind.links.isEmpty {
                ScorePageLinks(routes: kind.links.map { link in
                    (link.route, link.title, value(of: link.route))
                })
            }
            AspectReadings(aspect: kind.aspect, identifiers: kind.readings, category: .aspect(kind.aspect))
        }
        .task { await load() }
    }

    private func value(of route: ScoreRoute) -> String? {
        switch route {
        case .recovery: health.scores?.recovery.map(String.init)
        case .stress: health.scores?.stress.map(String.init)
        default: nil
        }
    }

    /// Whole numbers past ten, one decimal under it.
    static let format: @Sendable (Double) -> String = { value in
        abs(value) >= 10 ? ScoreMath.number(value) : ScoreMath.number(value, decimals: 1)
    }

    private func load() async {
        guard !isRead, let metric else { return }
        await health.loadScores()
        guard let source = await health.prepare([metric.identifier]) else {
            isRead = true
            return
        }
        let reader = VaultReader(source: source)
        let points = await reader.series(metric, period: .month, now: Date())
        days = points.map { $0.value.map { VaultFormat.scaled($0, unit: metric.unit) } }
        unit = MetricPageWords.unit(identifier: metric.identifier, fallback: metric.unit.shortLabel)
        isRead = true
    }
}
