//
//  MindCrisisSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The safety sheet, opened when an entry reads as distress.
///
/// Its words and its numbers are fixed (`MindCrisisResources`), never
/// generated, and every row opens something: the phone for a line, the
/// directory for the rest of the world. A heavy entry gets a gentler opening
/// line than a disclosure; the lines are the same.
struct MindCrisisSheet: View {
    let distress: MindDistress

    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let lines = MindCrisisResources.lines(region: Locale.current.region?.identifier)

        MindSheetFrame(title: "Support", closeTitle: "Close") {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 6) {
                Text(distress.isUrgent ? MindCrisisResources.title : "That sounds heavy.")
                    .somaFont(type.display)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(distress.isUrgent
                     ? MindCrisisResources.disclaimer
                     : "You don’t have to carry it alone. If it gets worse, or you’re not safe, these lines are there for you, day and night. " + MindCrisisResources.disclaimer)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, theme.metrics.cardSpacing)

            VStack(spacing: theme.metrics.cardSpacing) {
                ForEach(lines) { line in
                    Button {
                        if let url = line.url { openURL(url) }
                    } label: {
                        SomaCard {
                            HStack(spacing: theme.metrics.moveRowGap) {
                                VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                                    Text(line.name)
                                        .somaFont(type.cardTitle)
                                        .foregroundStyle(colors.inkPrimary.color)
                                        .multilineTextAlignment(.leading)
                                    Text(line.hours)
                                        .somaFont(type.caption)
                                        .foregroundStyle(colors.inkSecondary.color)
                                }
                                Spacer(minLength: 8)
                                Text(line.dial ?? "Open")
                                    .somaFont(type.rowValue)
                                    .foregroundStyle(colors.accent.color)
                            }
                        }
                    }
                    .buttonStyle(SomaGlassPressStyle())
                    .accessibilityLabel(line.dial.map { "Call \(line.name), \($0)" } ?? "Open \(line.name)")
                }
            }
        } footer: {
            EmptyView()
        }
    }
}
