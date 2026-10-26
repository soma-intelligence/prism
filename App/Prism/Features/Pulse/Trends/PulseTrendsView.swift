//
//  PulseTrendsView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The Pulse tab's Trends page: cause and effect on the person's own days.
///
/// Each card is one link (yesterday's strain and today's recovery, a night
/// after alcohol and its sleep score), strongest first: the cause's glyph
/// leading to the effect's, a plain headline with one number under it, and
/// the two sides as a pair of columns, before and after, every day a faint
/// dot and the averages joined (owner, 2026-10-20: more visual). A link that has too few days, or whose difference sits inside the
/// outcome's day to day noise, is never drawn: it is named in one "Still
/// learning" row at the foot (owner, 2026-10-03: link cause and effect,
/// visuals first, fewer words; 2026-10-19: less scientific).
///
/// Read from Health, the score engine and the Journal when the part opens and
/// on pull to refresh.
struct PulseTrendsView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @State private var links: CauseLinks.Output?
    @State private var today: Date = .now

    var body: some View {
        TabPartScaffold(aspect: nil, stats: []) {
            if let links {
                PulseLinksList(links: links, today: today)
            } else {
                ReadingRows()
            }
            MindHealthStatus(status: health.status)
        }
        .somaRefreshable { await load(force: true) }
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        let calendar = Calendar.current
        let now = Date()
        today = now
#if DEBUG
        // `-pulse.preview YES` draws the preview fixture, to check the cards
        // on a Simulator whose Health store is empty. Debug builds only.
        if UserDefaults.standard.bool(forKey: "pulse.preview") {
            links = CauseLinks.preview
            today = CauseLinks.previewToday
            return
        }
#endif
        let logged = Dictionary(journal.loggedDays.map { ($0.date, $0.day) }, uniquingKeysWith: { first, _ in first })
        guard let source = await health.prepare(PulseLinksInputs.metrics) else {
            let series = PulseLinksInputs.series(health: .init(), scores: health.scores, journal: logged,
                                                 now: now, calendar: calendar)
            links = CauseLinks.compute(series, calendar: calendar)
            return
        }
        async let scoresRead: Void = health.loadScores(force: force)
        let read = await PulseLinksInputs.read(from: source, now: now, calendar: calendar)
        await scoresRead
        let series = PulseLinksInputs.series(health: read, scores: health.scores, journal: logged,
                                             now: now, calendar: calendar)
        links = CauseLinks.compute(series, calendar: calendar)
    }
}

/// The link cards, strongest first, then the row naming the held ones. A
/// card, or a held name, opens the link's detail sheet.
struct PulseLinksList: View {
    let links: CauseLinks.Output
    /// The day a detail sheet's ninety days end on.
    var today: Date = .now

    @Environment(\.somaTheme) private var theme
    @State private var open: CauseLink?

    var body: some View {
        // Two links side by side where the width holds them; the held names
        // run under both.
        SomaCardColumns {
            ForEach(links.shown) { link in
                Button { open = link } label: {
                    SomaLinkCard(
                        headline: link.headline,
                        detail: link.plainDetail,
                        highLabel: link.driver.sideLabels.high,
                        lowLabel: link.driver.sideLabels.low,
                        tone: link.tone,
                        high: link.result.high.map { $0 * link.outcome.scale },
                        low: link.result.low.map { $0 * link.outcome.scale },
                        cause: link.driver.aspect,
                        effect: link.outcome.aspect,
                        highText: link.outcome.columnText(link.result.high),
                        lowText: link.outcome.columnText(link.result.low)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPress)
                .accessibilityHint(Text("Opens the details"))
            }
            if !links.pending.isEmpty {
                SomaLinkPendingRow(title: "Still learning", names: links.pendingNames) { name in
                    open = links.pending.first { $0.plainTitle == name }
                }
                .somaColumnSpan(.full)
            }
        }
        .sheet(item: $open) { link in
            PulseLinkDetailSheet(link: link, today: today)
        }
    }
}

#if DEBUG
#Preview("Trends") {
    SomaPageScroll {
        PulseLinksList(links: CauseLinks.preview, today: CauseLinks.previewToday)
            .padding()
    }
    .softScrollEdges()
    .background(SomaTheme.standard.colors.canvas.color)
}
#endif
