//
//  PulseLinkDetailSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// One link opened from Trends: the effect large, the two sides compared at
/// full width, the outcome over ninety days with the driver days lit, the
/// facts in one row and one phrase that says it (owner, 2026-10-03: click a
/// trend to open a detailed modal, minimal text and colour).
///
/// A link still held back opens the same sheet, led by how far it is from its
/// gate, with whatever days it already has drawn under that.
struct PulseLinkDetailSheet: View {
    let detail: LinkDetail

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(link: CauseLink, today: Date, calendar: Calendar = .current) {
        detail = LinkDetail(link: link, today: today, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                PulseLinkDetailContent(detail: detail)
                    .padding(theme.metrics.pagePadding)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#if os(macOS)
        .frame(minWidth: theme.metrics.linkSheetMinWidth, minHeight: theme.metrics.linkSheetMinHeight)
#endif
    }
}

/// The sheet's sections, apart from its chrome, so a render can draw them.
struct PulseLinkDetailContent: View {
    let detail: LinkDetail

    @Environment(\.somaTheme) private var theme

    private var link: CauseLink { detail.link }
    /// A held link has no verdict yet, so it wears no good or cost colour.
    private var tone: SomaLinkTone { detail.progress == nil ? link.tone : .neutral }
    private var hasSides: Bool { !detail.high.isEmpty && !detail.low.isEmpty }
    private var hasTimeline: Bool { detail.timeline.contains { $0.value != nil } }

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.linkDetailSpacing) {
            VStack(alignment: .leading, spacing: metrics.linkCardSpacing * 1.5) {
                SomaLinkHeadline(
                    driver: link.driver.name,
                    outcome: link.outcome.name,
                    value: detail.progress == nil ? link.valueText : nil,
                    unit: link.outcome.unit,
                    caption: detail.progress == nil ? link.caption : nil,
                    tone: tone
                )
                if let takeaway = detail.takeaway {
                    Text(verbatim: takeaway)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }
            }

            if let progress = detail.progress {
                SomaCard {
                    SomaLinkProgress(fraction: progress.fraction, label: progress.label)
                }
            }

            if hasSides {
                SomaCard {
                    SomaLinkComparison(
                        high: detail.high,
                        low: detail.low,
                        highLabel: detail.highLabel,
                        lowLabel: detail.lowLabel,
                        gap: detail.differenceText,
                        tone: tone
                    )
                }
            }

            if hasTimeline {
                SomaCard {
                    SomaLinkTimeline(
                        days: timelineDays,
                        aspect: link.outcome.aspect,
                        tone: tone,
                        xLabels: xLabels,
                        legend: legend
                    )
                }
            }

            SomaCard {
                SomaLinkFacts(facts)
            }
        }
    }

    private var timelineDays: [SomaLinkDay] {
        detail.timeline.map { day in
            let side: SomaLinkSide = switch day.side {
            case .high: .high
            // An untagged day is every other day: drawn as the line alone.
            case .low: link.isTag ? .none : .low
            case .between, nil: .none
            }
            return SomaLinkDay(date: day.date, value: day.value, side: side)
        }
    }

    /// Four dates spread under the plot, the last one today.
    private var xLabels: [String] {
        let days = detail.timeline
        guard days.count > 1 else { return [] }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return (0..<4).map { step in
            days[(days.count - 1) * step / 3].date.formatted(style)
        }
    }

    /// What a lit day is: "Alcohol nights", "Long nights".
    private var legend: String {
        if let sides = link.driver.sides {
            return "\(sides.high.capitalized) \(link.driver.noun)"
        }
        return "\(link.driver.name) \(link.driver.noun)"
    }

    private var facts: [SomaLinkFact] {
        var facts = [SomaLinkFact("Days", value: detail.daysText)]
        if detail.progress == nil {
            facts.append(SomaLinkFact("Difference", value: detail.differenceText))
            facts.append(SomaLinkFact("Noise", value: detail.noiseText))
            facts.append(SomaLinkFact("Strength", strength: detail.strengthLevel))
        } else if link.result.verdict == .withinNoise {
            facts.append(SomaLinkFact("Difference", value: detail.differenceText))
            facts.append(SomaLinkFact("Noise", value: detail.noiseText))
        }
        facts.append(SomaLinkFact("Timing", value: detail.lagText))
        return facts
    }
}

#if DEBUG
#Preview("Shown link") {
    Color.clear.sheet(isPresented: .constant(true)) {
        if let link = CauseLinks.preview.shown.first {
            PulseLinkDetailSheet(link: link, today: CauseLinks.previewToday)
        }
    }
}

#Preview("Waiting link") {
    Color.clear.sheet(isPresented: .constant(true)) {
        if let link = CauseLinks.preview.pending.first(where: \.isTag) {
            PulseLinkDetailSheet(link: link, today: CauseLinks.previewToday)
        }
    }
}
#endif
