//
//  AskLogHub.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Tell Soma: what the plus in Ask's composer opens.
///
/// The chat log hub, a sheet over Ask: the shortcuts the
/// Shortcuts page leaves on, in its order, each with a line from today's own
/// numbers. Logging itself lives in Track, so a tile hands over to it; the
/// record tile opens Health records.
struct AskLogHub: View {
    let choose: (LogShortcut) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var settings = GlobalSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.browseSectionSpacing) {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text("Tell Soma")
                            .somaFont(theme.typography.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                        Text("Log something")
                            .somaFont(theme.typography.display)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }

                    if settings.shortcuts.offered.isEmpty {
                        NoteCard(title: "Every shortcut is off", message: "Turn some back on in Settings, under Shortcuts. You can still tell Soma anything in words.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: theme.metrics.cardSpacing),
                                            GridItem(.flexible(), spacing: theme.metrics.cardSpacing)],
                                  spacing: theme.metrics.cardSpacing) {
                            ForEach(settings.shortcuts.offered) { shortcut in
                                Button {
                                    dismiss()
                                    choose(shortcut)
                                } label: {
                                    tile(shortcut)
                                }
                                .buttonStyle(.somaGlassPress)
                            }
                        }
                    }

                }
                .padding(theme.metrics.pagePadding)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tile(_ shortcut: LogShortcut) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing * 2) {
            LogShortcutGlyph(shortcut: shortcut)
            Spacer(minLength: theme.metrics.cardSpacing)
            Text(shortcut.title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Text(line(for: shortcut))
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(theme.metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget * 2.6, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous).fill(theme.colors.surface.color))
        .contentShape(.rect)
    }

    /// A line from today's own numbers, or what the tile is for when there is
    /// nothing to read yet.
    private func line(for shortcut: LogShortcut) -> String {
        switch shortcut {
        case .meal:
            return String(localized: "Last meal by \(settings.customization.lastMealBy.text)")
        case .workout:
            if let minutes = health.value("HKQuantityTypeIdentifierAppleExerciseTime") {
                return String(localized: "\(minutes) min of exercise today")
            }
            return shortcut.summary
        case .journal:
            return journal.day(Date()).feeling == nil ? String(localized: "How today felt") : String(localized: "Logged today")
        case .weight:
            if let weight = health.value("HKQuantityTypeIdentifierBodyMass", decimals: 1) {
                return String(localized: "Last: \(weight) kg")
            }
            return shortcut.summary
        case .sleep:
            if let slept = health.today?.sleepCard.value {
                return String(localized: "Last night: \(slept)")
            }
            return String(localized: "A nap, or last night")
        case .record:
            return String(localized: "A lab or a letter")
        }
    }
}

#Preview("Log hub") {
    AskLogHub { _ in }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
