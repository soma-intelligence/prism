//
//  OralHealthPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Mouth and teeth over thirty days: how many days had two brushings, each
/// day's count as a bar, the average brushing against two minutes, floss,
/// mouthwash and bleeding gums from the Journal, and the next dental visit.
///
/// Brushing comes from an electric toothbrush's app writing to Health, or
/// from the log at the foot of the page. Without it the page still reads the
/// Journal, and says in one line what fills the rest. The last visit is read
/// from the screening ledger and the booked one from the medical record,
/// both read only.
struct OralHealthPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme

    /// Thirty days of brushings, nil until Health has answered.
    @State private var brushing: [HealthReading]?
    @State private var logOutcome: LabHealthWriter.Outcome?

    private var words: MetricWords { MetricWords() }

    var body: some View {
        let now = Date.now
        let summary = summary(now: now)
        let lead = MetricLead.override(health.status)
        let axis = words.axis(days: OralSummary.windowDays, now: now)

        TabPartScaffold(
            aspect: .body,
            eyebrow: "Last \(OralSummary.windowDays) days",
            title: lead?.title ?? headline(summary),
            reason: lead?.reason ?? reason(summary),
            stats: [
                SomaStat("Twice a day", value: summary.brushedTwiceDays.map { "\($0)" }, unit: "of \(OralSummary.windowDays) days"),
                SomaStat("Brushing", value: OralSummary.duration(summary.averageSeconds), unit: "min"),
                SomaStat("Next visit", value: summary.nextVisit.map(words.short)),
            ]
        ) {
            if let gums = summary.gumBleedDays, gums > 0 {
                // ADA: bleeding gums are the first sign of gingivitis, which
                // brushing, cleaning between the teeth and a cleaning usually
                // reverse. Informative, never a diagnosis.
                MetricTextCard(
                    eyebrow: "Gums",
                    lead: gums == 1 ? "Your gums bled once this month." : "Your gums bled on \(gums) days this month.",
                    rest: "That's often the first sign of gingivitis, which careful brushing and flossing usually turn around. If it keeps up for two weeks, see your dentist."
                )
            }
            SomaChartCard(
                eyebrow: "Brushings a day",
                value: summary.brushedTwiceDays.map { "\($0)" },
                unit: summary.hasBrushing ? "days twice" : nil,
                note: summary.hasBrushing
                    ? "The line is two a day, morning and night."
                    : "An electric toothbrush app such as Oral-B or Philips Sonicare writes each brushing to Health, or log one below."
            ) {
                MetricDailyBars(
                    values: summary.perDay,
                    limit: summary.hasBrushing ? 2 : nil,
                    aspect: .body,
                    leadingLabel: summary.hasBrushing ? axis.0 : nil,
                    middleLabel: summary.hasBrushing ? axis.1 : nil,
                    trailingLabel: summary.hasBrushing ? axis.2 : nil
                )
            }
            MetricRowsCard(
                eyebrow: "Habits",
                rows: [
                    MetricRowItem("Brushing time", detail: summary.isShortBrush
                                    ? "Under the two minutes a brushing needs. Spend 30 seconds on each quarter of your mouth."
                                    : "Two minutes each time reaches every surface.",
                                  value: OralSummary.duration(summary.averageSeconds)),
                    MetricRowItem("Last brushing",
                                  detail: summary.lastBrushing.map { words.relativeDay($0, now: now) },
                                  value: summary.lastBrushing.map { ScoreMath.clock($0) }),
                    MetricRowItem("Flossed", detail: "Tag Floss in the Journal. Once a day between the teeth.",
                                  value: days(summary.flossDays)),
                    MetricRowItem("Mouthwash", detail: "Tag Mouthwash in the Journal.", value: days(summary.mouthwashDays)),
                    MetricRowItem("Gums bled", detail: "Asked once a week in the evening.", value: days(summary.gumBleedDays)),
                ],
                footnote: "From the American Dental Association: brush twice a day for two minutes, clean between your teeth once a day."
            )
            MetricRowsCard(
                eyebrow: "Dentist",
                rows: [
                    MetricRowItem("Last checkup", detail: summary.lastVisit.map(words.day), value: summary.lastVisit.map(words.short)),
                    MetricRowItem("Next checkup",
                                  detail: nextVisitDetail(summary, now: now),
                                  value: summary.nextVisit.map(words.short)),
                ],
                footnote: "Log a dental checkup in the Screening ledger and the next one is counted from it. A dental appointment in your medical record shows here once it's booked."
            )
            // Lockhart et al., AHA scientific statement, Circulation 2012;125:2520:
            // periodontal disease and heart disease go together, but treating
            // the gums has not been shown to prevent heart disease.
            MetricTextCard(
                eyebrow: "Why it matters",
                lead: "Gum disease and heart disease often go together.",
                rest: "The American Heart Association found the link but no proof that one causes the other. Healthy gums are worth keeping for their own sake."
            )
            LabLogCard(eyebrow: "Log", title: "A brushing", detail: logDetail,
                       actionTitle: "Log brushing", aspect: .body) {
                Task { await logBrushing() }
            }
            LabFootnote("Informative, not a diagnosis. Pain, swelling or a loose tooth is for your dentist.")
        }
        .task { await load() }
        .somaRefreshable { await load() }
    }

    private func summary(now: Date) -> OralSummary {
        #if DEBUG && targetEnvironment(simulator)
        if FixtureOral.isOn {
            return OralSummary.make(brushing: FixtureOral.brushings(now: now), journalDays: FixtureOral.journalDays(now: now),
                                    lastVisit: FixtureOral.lastVisit(now: now), now: now)
        }
        #endif
        return OralSummary.make(brushing: brushing ?? [], journal: journal, lastVisit: Self.lastDentalVisit,
                                bookedVisit: MedicalRecordStore.shared.record.nextDentalVisit(now: now), now: now)
    }

    /// The last dental checkup logged in the screening ledger. Read only:
    /// the ledger is the Screening page's to write.
    static var lastDentalVisit: Date? {
        ToolsStore.shared.record.screening.ledger.lastRecord(for: "dental")?.performedOn
    }

    /// A booked visit says when and with whom; otherwise the six months.
    private func nextVisitDetail(_ summary: OralSummary, now: Date) -> String? {
        guard let next = summary.nextVisit else { return nil }
        let record = MedicalRecordStore.shared.record
        if let booked = record.upcoming(now: now).first(where: record.isDental), booked.date == next {
            let who = booked.with.homeNonEmpty.map { " with \($0)" } ?? ""
            return "Booked\(who), at \(ScoreMath.clock(booked.date))."
        }
        return summary.isVisitDue ? "Due now: six months since the last one." : "Six months after the last one."
    }

    private var logDetail: String {
        switch logOutcome {
        case .saved?: "Saved to Health: two minutes, ending now."
        case .failed(let message)?: "Not saved. \(message)"
        case .notWritten?, nil: "Two minutes, ending now, for a manual brush. An electric one logs itself."
        }
    }

    private func days(_ count: Int?) -> String? {
        count.map { "\($0) of \(OralSummary.windowDays)" }
    }

    private func headline(_ summary: OralSummary) -> String {
        if brushing == nil, !summary.hasBrushing { return "Reading your brushing." }
        guard let twice = summary.brushedTwiceDays else {
            return summary.isEmpty ? "Nothing on your teeth yet." : "No brushing in Health yet."
        }
        if twice >= OralSummary.windowDays - 3 { return "Twice a day, nearly every day." }
        return "Twice a day on \(twice) of \(OralSummary.windowDays) days."
    }

    private func reason(_ summary: OralSummary) -> String {
        if !summary.hasBrushing {
            return "An electric toothbrush app writes each brushing to Health, or log one at the foot of this page. Floss, mouthwash and gums come from the Journal."
        }
        if summary.isShortBrush {
            return "Your brushings average under two minutes. A little longer reaches the back teeth."
        }
        return "Brushing time sits at two minutes or more. Keep cleaning between your teeth once a day."
    }

    private func load() async {
        brushing = await health.toothbrushing()
    }

    private func logBrushing() async {
        logOutcome = await OralHealthWriter.logBrushing()
        if logOutcome == .saved { await load() }
    }
}

// MARK: - Reading

extension HealthDashboard {
    /// Thirty days of brushings from Health, through the same once-per-set
    /// request as every page. Empty when Health is not there or the read
    /// threw; the page then shows its dashes and says what fills them.
    func toothbrushing(now: Date = .now) async -> [HealthReading] {
        guard let source = await prepare([OralSummary.brushingID]),
              let metric = HealthMetricCatalog.metric(for: OralSummary.brushingID),
              let start = Calendar.current.date(byAdding: .day, value: -OralSummary.windowDays, to: now) else { return [] }
        return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
    }
}

#Preview("Mouth and teeth") {
    NavigationStack { OralHealthPage() }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
