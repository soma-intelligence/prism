//
//  ProgramsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Guided programs: the ones you follow, with where you are and today's ask,
/// and the ones you could start.
///
/// Settings > Programs. Joining stamps the day; leaving stops
/// the program and keeps nothing hostage. Progress is counted from the day you
/// joined, never invented.
struct ProgramsPage: View {
    @Environment(\.somaTheme) private var theme

    @State private var settings = GlobalSettings.shared
    @State private var opened: Program?

    var body: some View {
        ListScaffold(eyebrow: "Programs", title: "Guided programs") {

            if !joined.isEmpty {
                SettingsSection("Yours") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        ForEach(joined, id: \.program.id) { entry in
                            ProgramProgressCard(program: entry.program, enrollment: entry.enrollment) {
                                leave(entry.program)
                            }
                        }
                    }
                }
            }

            if !others.isEmpty {
                SettingsSection(joined.isEmpty ? "Start one" : "More to try") {
                    SomaBrowseGroup(others) { program in
                        Button { opened = program } label: {
                            HStack(spacing: theme.metrics.browseRowSpacing) {
                                SomaObjectIcon(aspect: program.aspect, size: .row)
                                    .scaleEffect(0.7)
                                    .frame(width: theme.metrics.browseGlyphColumn, height: theme.metrics.miniOrbDiameter * 0.7)
                                    .accessibilityHidden(true)
                                SettingsLine(program.title, detail: program.summary) {
                                    Text(program.lengthText)
                                        .somaFont(theme.typography.rowValue)
                                        .foregroundStyle(theme.colors.inkSecondary.color)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                                        .foregroundStyle(theme.colors.inkSecondary.color)
                                }
                                .padding(.leading, -theme.metrics.browseRowPadding)
                            }
                            .padding(.leading, theme.metrics.browseRowPadding)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        }
        .confirmationDialog(
            opened?.title ?? "",
            isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } }),
            titleVisibility: .visible,
            presenting: opened
        ) { program in
            Button("Start \(program.lengthText.lowercased())") { join(program) }
            Button("Not now", role: .cancel) {}
        } message: { program in
            Text(program.dailyAsk)
        }
    }

    private var joined: [(program: Program, enrollment: ProgramEnrollment)] {
        settings.programs.compactMap { enrollment in
            ProgramCatalog.program(enrollment.programID).map { ($0, enrollment) }
        }
    }

    private var others: [Program] {
        let taken = Set(settings.programs.map(\.programID))
        return ProgramCatalog.all.filter { !taken.contains($0.id) }
    }

    private func join(_ program: Program) {
        settings.programs.append(ProgramEnrollment(programID: program.id, joined: Date()))
    }

    private func leave(_ program: Program) {
        settings.programs.removeAll { $0.programID == program.id }
    }
}

/// One program you follow: its length, where you are, and today's ask.
private struct ProgramProgressCard: View {
    let program: Program
    let enrollment: ProgramEnrollment
    let leave: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let progress = ProgramProgress.of(enrollment, program: program, on: Date(), calendar: .current)
        let metrics = theme.metrics
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(spacing: metrics.cardSpacing) {
                    SomaObjectIcon(aspect: program.aspect, size: .row)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                        Text(program.title)
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text(program.lengthText)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    Spacer(minLength: metrics.cardSpacing)
                    Text(progress.isFinished ? String(localized: "Done") : progress.label(for: program))
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(colors.inkPrimary.color)
                }

                ProgressView(value: progress.fraction)
                    .tint(colors.accent.color)
                    .accessibilityLabel(Text(progress.label(for: program)))

                Text(progress.isFinished ? String(localized: "Finished. Leave it to clear its cards, or keep going on your own.") : program.dailyAsk)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Leave program", role: .destructive, action: leave)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.danger.color)
                    .buttonStyle(.plain)
                    .frame(minHeight: metrics.minimumTapTarget)
            }
        }
    }
}

#Preview("Programs") {
    NavigationStack { ProgramsPage() }
}
