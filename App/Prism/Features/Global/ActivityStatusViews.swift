//
//  ActivityStatusViews.swift
//  Prism
//

import SwiftUI
import SomaUI

/// How are you? The four statuses, one chosen, applied with Update.
///
/// The Activity Status sheet, over Pulse. The choice is held until Update, so a
/// stray tap changes nothing.
struct ActivityStatusPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = ActivityStatusStore.shared
    @State private var selected: ActivityStatus?

    var body: some View {
        let chosen = selected ?? store.current

        ListScaffold(eyebrow: "Activity status", title: "How are you?") {

            SomaBrowseGroup(ActivityStatus.allCases) { status in
                Button { selected = status } label: {
                    ActivityStatusLine(status: status, text: status.summary, isChosen: status == chosen)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(status == chosen ? .isSelected : [])
            }


            Button {
                store.set(chosen)
                dismiss()
            } label: {
                Text("Update")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.onAccent.color)
                    .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                    .background(Capsule().fill(theme.colors.accent.color))
                    .contentShape(.capsule)
            }
            .buttonStyle(.somaGlassPress)
            .disabled(chosen == store.current)
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
        HStack(alignment: .top, spacing: theme.metrics.browseRowSpacing) {
            Image(systemName: status.symbol)
                .font(.system(size: theme.metrics.browseGlyphSize))
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(width: theme.metrics.browseGlyphColumn)
                .padding(.top, theme.metrics.scoreLabelSpacing)
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
