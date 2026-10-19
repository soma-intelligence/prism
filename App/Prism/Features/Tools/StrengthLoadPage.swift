//
//  StrengthLoadPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Strength Load: the week's lifting as volume load (kilograms times reps),
/// its trend against the weeks before, and each movement's best.
///
/// The strength load engine: weekly volume load, week over week change
/// read against flat and fast bands, and an estimated one rep max per
/// movement (Epley, sets of ten reps or fewer). Apple Health counts strength
/// workouts but holds no sets, so the sets are logged here.
struct StrengthLoadPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var logging = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let sessions = Self.sessions(store.record.lifts)
        let report = SomaTools.StrengthLoad.report(from: sessions, endingOn: model.current.now)
        let bests = SomaTools.StrengthLoad.progression(from: sessions)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: model.current.now) ?? model.current.now
        let workouts = model.current.workouts.filter { ToolsInputs.strengthCodes.contains(Int($0.value)) && $0.start >= weekAgo }

        ToolPage(ToolKind.strengthLoad.title) {
            if report.isEmpty {
                ToolHero(eyebrow: "Last 7 days",
                         headline: workouts.isEmpty ? "No strength sessions this week." : "\(ToolFormat.capitalized(ToolFormat.words(workouts.count))) strength session\(workouts.count == 1 ? "" : "s") in Apple Health.",
                         lead: "Log the sets and the load builds from them.",
                         rest: "Apple Health keeps the session, not the weight or the reps.")
            } else {
                ToolHero(eyebrow: "Last 7 days",
                         headline: "\(ToolFormat.capitalized(ToolFormat.words(report.currentSessionCount))) session\(report.currentSessionCount == 1 ? "" : "s"), \(ToolFormat.number(report.currentVolume)) kg·reps.",
                         lead: report.weekOverWeekChange.map { "\($0 >= 0 ? "Up" : "Down") \(Int(abs($0 * 100).rounded()))% on last week." } ?? "The first logged week.",
                         rest: report.trend.label + ".")
            }
            ToolStats([
                SomaStat("Sessions", value: report.isEmpty ? (workouts.isEmpty ? nil : "\(workouts.count)") : "\(report.currentSessionCount)"),
                SomaStat("Load", value: report.isEmpty ? nil : ToolFormat.number(report.currentVolume), unit: "kg·reps"),
                SomaStat("Lean mass", value: model.current.leanMass.map { ToolFormat.number($0.value, decimals: 1) }, unit: "kg"),
            ])

            SomaChartCard(eyebrow: "Strength load", value: report.isEmpty ? nil : ToolFormat.number(report.currentVolume),
                          unit: "kg·reps, 7 days", note: "Eight weeks, one bar a week.") {
                ToolStackedBars(aspect: .activity, bars: report.weeksOldestFirst.map { week in
                    ToolStackedBars.Bar(label: week.index == 0 ? "Now" : "−\(week.index)", parts: [week.volumeLoad])
                }, top: max(1, (report.weeks.map(\.volumeLoad).max() ?? 0) * 1.15))
            }

            if !bests.isEmpty {
                ToolEyebrow("Movements, personal bests")
                ToolRowsCard(aspect: .activity, rows: bests.map { best in
                    ToolRow(title: best.name, detail: ToolFormat.day(best.latestDate, weekday: true),
                            value: "\(ToolFormat.number(best.bestOneRepMax)) kg", tone: best.isNewPersonalBest ? .accent : .plain)
                })
                ToolFootnote("Estimated 1RM, sets of 10 or fewer")
            }
            ToolNextCard(eyebrow: "Log", aspect: .activity, title: "Log a set",
                         detail: "A movement, the reps and the weight.", actionTitle: "Log", action: { logging = true })
            ToolLinkRow(title: "About Strength Load", detail: nil, value: ToolRoute.intro(.strengthLoad))
        }
        .sheet(isPresented: $logging) { LiftLogSheet() }
        .task {
            store.markOpened(.strengthLoad)
            await model.load(health)
        }
    }

    /// Logged sets grouped into one session per day.
    static func sessions(_ lifts: [LiftSet], calendar: Calendar = .current) -> [SomaTools.StrengthLoad.Session] {
        let byDay = Dictionary(grouping: lifts) { calendar.startOfDay(for: $0.date) }
        return byDay.map { day, sets in
            let byExercise = Dictionary(grouping: sets, by: \.exercise)
            return SomaTools.StrengthLoad.Session(date: day, exercises: byExercise.map { name, sets in
                SomaTools.StrengthLoad.Exercise(exerciseID: name.lowercased(), name: name,
                                                sets: sets.map { .init(reps: $0.reps, weightKg: $0.kilograms) })
            })
        }
    }
}

/// Logging one set.
struct LiftLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var exercise = ""
    @State private var reps = 8
    @State private var kilograms = 20.0

    private var store: ToolsStore { .shared }

    var body: some View {
        let known = Array(Set(store.record.lifts.map(\.exercise))).sorted()
        NavigationStack {
            ListScaffold(eyebrow: "Strength Load", title: "Log a set") {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        TextField("Movement, such as Goblet squat", text: $exercise)
                        ToolHairline()
                        Stepper("Reps: \(reps)", value: $reps, in: 1...50)
                        ToolHairline()
                        Stepper("Weight: \(ToolFormat.number(kilograms, decimals: 1)) kg", value: $kilograms, in: 0...400, step: 2.5)
                    }
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                }
                if !known.isEmpty {
                    ToolEyebrow("Your movements")
                    ToolSettingsGroup(rows: known.map { name in .choice(name, exercise == name, { exercise = name }) })
                }
                ToolFootnote("Kept on this phone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let name = exercise.trimmingCharacters(in: .whitespaces)
                        store.update { $0.lifts.append(LiftSet(exercise: name, date: Date(), reps: reps, kilograms: kilograms)) }
                        dismiss()
                    }
                    .disabled(exercise.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
