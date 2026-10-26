//
//  ActivityStatusViews.swift
//  Prism
//

import SwiftUI
import SomaUI

/// How are you? The four statuses, one chosen.
///
/// the earlier app's Activity Status sheet (20b.11), drawn as a Soma sheet over Pulse. A
/// tap applies the status at once, with a tick and a haptic, the way a
/// Settings list picks a value; the big Update button under it read as a
/// form (owner, 2026-10-24).
struct ActivityStatusPage: View {
    @State private var store = ActivityStatusStore.shared

    var body: some View {
        let chosen = store.current

        ListScaffold(eyebrow: "Activity status", title: "How are you?") {
            SomaBrowseGroup(ActivityStatus.allCases) { status in
                Button { store.set(status) } label: {
                    ActivityStatusLine(status: status, text: status.summary, isChosen: status == chosen)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(status == chosen ? .isSelected : [])
            }
            .sensoryFeedback(.selection, trigger: chosen)
        }
    }
}

/// What each status changes, for the calendar's info button.
///
/// The Activity Statuses legend.
struct ActivityStatusLegendPage: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        ListScaffold(eyebrow: "Calendar", title: "What statuses change") {
            SomaBrowseGroup(ActivityStatus.allCases) { status in
                ActivityStatusLine(status: status, text: status.legend, isChosen: false)
            }
        }
    }
}

/// One status: its glyph, its name, a line about it, and a mark when chosen.
struct ActivityStatusLine: View {
    let status: ActivityStatus
    let text: String
    let isChosen: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        // The glyph centred on the row, the way every other glyph row in
        // Soma sets it; pinned to the top it floated above the title.
        HStack(alignment: .center, spacing: theme.metrics.browseRowSpacing) {
            Image(systemName: status.symbol)
                .font(.system(size: theme.metrics.browseGlyphSize, weight: .light))
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(width: theme.metrics.browseGlyphColumn)
            SettingsLine(status.title, detail: text) {
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(theme.colors.accent.color)
                }
            }
            .padding(.leading, -theme.metrics.browseRowPadding)
        }
        .padding(.leading, theme.metrics.browseRowPadding)
        .contentShape(.rect)
    }
}

/// A route page presented as a sheet: its own stack and a Done button.
struct GlobalSheet<Content: View>: View {
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#Preview("Activity status") {
    GlobalSheet { ActivityStatusPage() }
}

#Preview("Statuses legend") {
    GlobalSheet { ActivityStatusLegendPage() }
}
