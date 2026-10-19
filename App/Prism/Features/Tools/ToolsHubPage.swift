//
//  ToolsHubPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Every tool in one list, grouped the way the day runs: sleep and the body
/// clock, food and energy, evenings and travel, skin and sun, the long run.
///
/// Each row says what the tool has to say today in one line, read from the
/// same numbers its page shows. A tool with something new to say carries the
/// accent dot; the headline counts them. A tool never opened lands on its
/// intro first, so the person reads what it does before it does anything.
struct ToolsHubPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let digest = ToolDigest(inputs: model.current, scores: health.scores, store: store.record)
        let speaking = ToolKind.allCases.filter { store.isOn($0) && digest.hasNews($0) }

        ToolPage("Tools") {
            ToolHero(eyebrow: ToolFormat.day(model.current.now, weekday: true),
                     headline: headline(speaking.count),
                     lead: speaking.isEmpty ? "Nothing needs you right now." : speaking.prefix(3).map { digest.line($0) }.joined(separator: " "),
                     rest: speaking.isEmpty ? "Each tool speaks up when it has something new." : "The others keep quiet until they do.")

            ForEach(ToolKind.Group.allCases) { group in
                ToolEyebrow(group.rawValue)
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        ForEach(Array(group.tools.enumerated()), id: \.element) { index, kind in
                            if index > 0 { ToolHairline().padding(.leading, orbSide + theme.metrics.moveRowGap) }
                            ToolHubRow(kind: kind,
                                       detail: store.isOn(kind) ? digest.line(kind) : "Off.",
                                       hasNews: store.isOn(kind) && speaking.contains(kind),
                                       opened: store.record.since[kind] != nil,
                                       orbSide: orbSide)
                        }
                    }
                }
            }
        }
        .task { await model.load(health) }
        .refreshable { await model.load(health, force: true) }
    }

    private var orbSide: CGFloat { theme.metrics.checkDiameter * 1.6 }

    private func headline(_ count: Int) -> String {
        switch count {
        case 0: "Your tools are quiet today."
        case 1: "One tool has something to say."
        default: "\(ToolFormat.capitalized(ToolFormat.words(count))) tools have something to say."
        }
    }
}

private struct ToolHubRow: View {
    let kind: ToolKind
    let detail: String
    let hasNews: Bool
    let opened: Bool
    let orbSide: CGFloat

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        NavigationLink(value: opened ? kind.route : ToolRoute.intro(kind)) {
            HStack(spacing: theme.metrics.moveRowGap) {
                PulseMiniOrb(aspect: kind.aspect, diameter: orbSide)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(kind.title)
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                        if hasNews {
                            Circle()
                                .fill(colors.accent.color)
                                .frame(width: theme.metrics.identityDotDiameter, height: theme.metrics.identityDotDiameter)
                                .accessibilityLabel("New")
                        }
                    }
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
            .zoomSource(opened ? kind.route : ToolRoute.intro(kind))
        }
        .buttonStyle(TilePressStyle())
    }
}
