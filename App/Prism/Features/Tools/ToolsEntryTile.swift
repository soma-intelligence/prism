//
//  ToolsEntryTile.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The way into the tools from another page: a tile naming them, with the
/// sleep orb, that zooms into the hub.
///
/// One view, placed on Pulse > Explore and on Track > Rituals, so both doors
/// look the same and a change to the wording is made once.
struct ToolsEntryTile: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text("Tools")
                .somaFont(type.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)
            TileLink(value: ToolRoute.hub) {
                SomaCard {
                    HStack(spacing: theme.metrics.moveRowGap) {
                        PulseMiniOrb(aspect: .sleep, diameter: theme.metrics.checkDiameter * 1.6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Planners for your day")
                                .somaFont(type.body)
                                .foregroundStyle(colors.inkPrimary.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .multilineTextAlignment(.leading)
                }
            }
        }
    }
}
