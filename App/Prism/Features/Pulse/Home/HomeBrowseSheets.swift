//
//  HomeBrowseSheets.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - Quick add

/// Six things to log from a long press on the orb, each with where the day
/// stands. Water and caffeine log on a tap; the rest open their own sheet.
struct HomeQuickAddSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: HomeSheetRoute?
    @State private var weight: HealthReading?
    @State private var lastWorkout: PulseWorkout?

    private var log: HomeLog { .shared }
    private var track: TrackLogStore { .shared }

    var body: some View {
        let now = Date()
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    Text("Add to today")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    LazyVGrid(columns: columns, spacing: 10) {
                        tile("Water", symbol: "drop.fill", aspect: .gut, detail: waterLine(now), hint: "Adds a glass, 250 ml") {
                            pour(.water, ml: 250)
                        }
                        .contextMenu {
                            Button("A bottle, 500 ml") { pour(.water, ml: 500) }
                            Button("Take back the last one") { track.removeLastDrink(on: Date()) { $0.drink == .water } }
                        }
                        tile("Caffeine", symbol: "cup.and.saucer.fill", aspect: .activity, detail: caffeineLine(now), hint: "Adds a coffee, 95 mg") {
                            pour(.coffee, ml: 250, caffeineMg: 95)
                        }
                        .contextMenu {
                            Button("An espresso, 63 mg") { pour(.coffee, ml: 30, caffeineMg: 63) }
                            Button("A tea, 47 mg") { pour(.tea, ml: 250, caffeineMg: 47) }
                            Button("Take back the last one") { track.removeLastDrink(on: Date()) { $0.caffeineMg > 0 } }
                        }
                        tile("A meal", symbol: "fork.knife", aspect: .gut, detail: mealLine(now), hint: nil) { sheet = .foodLog }
                        tile("Mood", symbol: "face.smiling", aspect: .mind, detail: "How today feels", hint: nil) { sheet = .mood }
                        tile("Weight", symbol: "scalemass", aspect: .body, detail: weightLine, hint: "Log it in Apple Health or on a smart scale") {}
                            .disabled(true)
                        tile("A workout", symbol: "figure.run", aspect: .activity, detail: workoutLine, hint: nil) { sheet = .effort }
                    }
                }
                .padding(.horizontal, theme.metrics.pagePadding)
                .padding(.bottom, theme.metrics.pagePadding)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.colors.canvas.color)
        .homeSheets($sheet)
        .task {
            let day = await HomeDay.load(health: health, log: log)
            lastWorkout = day.workouts.last
            if let source = await health.prepare([HomeMetric.bodyMass]) {
                weight = await source.homeLatest(HomeMetric.bodyMass)
            }
        }
    }

    private func tile(
        _ title: String, symbol: String, aspect: SomaAspect, detail: String, hint: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .imageScale(.large)
                    .foregroundStyle(theme.aspects[aspect].identity.color)
                Spacer(minLength: 4)
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget * 2, alignment: .leading)
            .padding(theme.metrics.cardPadding)
            .background(RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous)
                .fill(theme.colors.surface.color))
            .contentShape(.rect)
        }
        .buttonStyle(SomaGlassPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint.map { Text($0) } ?? Text(""))
    }

    /// Logs a drink the way Track's water sheet does: kept in
    /// ``TrackLogStore`` first, then written to Apple Health.
    private func pour(_ drink: TrackDrink, ml: Double, caffeineMg: Double? = nil) {
        let entry = track.addDrink(drink, ml: ml, caffeineMg: caffeineMg, at: Date())
        Task { await TrackHealthWriter.saveDrink(entry) }
    }

    private func waterLine(_ now: Date) -> String {
        let target = HomeFormat.litres(track.waterGoalMl)
        guard let ml = track.waterMl(on: now) else { return "None yet, of \(target)" }
        return "\(HomeFormat.litres(ml)) of \(target)"
    }

    private func caffeineLine(_ now: Date) -> String {
        guard let mg = track.caffeineMg(on: now) else { return "None yet today" }
        let dose = "\(HomeFormat.whole(mg)) mg"
        return track.lastCaffeine(on: now).map { "\(dose), last \(HomeFormat.clock($0))" } ?? dose
    }

    private func mealLine(_ now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        return TrackMeal.at(hour: hour).title
    }

    private var weightLine: String {
        guard let weight else { return "Nothing in Apple Health yet" }
        return "\(HomeFormat.decimal(weight.value)) kg, \(weight.start.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var workoutLine: String {
        guard let workout = lastWorkout else { return "None recorded today" }
        return "Rate \(workout.name.lowercased()) at \(HomeFormat.clock(workout.start))"
    }
}

// MARK: - All categories

/// Every category of data, from Today's foot: a search over the 192 measures,
/// the six aspects with their glyphs and today's scores, then cycle, environment and the
/// medical card.
struct HomeAllCategoriesSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var query = ""

    private struct Aspect: Identifiable {
        var id: String { route.hashValue.description + title }
        var aspect: SomaAspect
        var title: String
        var detail: String
        var score: Int?
        var route: ScoreRoute
    }

    var body: some View {
        HomeSheet(eyebrow: "Pulse", title: "All categories") {
            // The search runs over the Vault's categories, so it names their count.
            TextField(VaultWords.searchPrompt(BodyCatalog.measureCount), text: $query)
                .somaFont(theme.typography.body)
                .padding(.horizontal, theme.metrics.cardPadding)
                .frame(minHeight: theme.metrics.minimumTapTarget + 4)
                .background(Capsule().fill(theme.colors.surface.color))

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                HomeEyebrow("Your six aspects")
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                        ForEach(Array(aspects.enumerated()), id: \.offset) { index, item in
                            if index > 0 { HomeHairline() }
                            NavigationLink(value: item.route) {
                                HStack(spacing: theme.metrics.moveRowGap) {
                                    SomaAspectGlyph(item.aspect, style: .badge)
                                    HomeValueRow(name: item.title, detail: item.detail, value: item.score.map(String.init))
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(theme.colors.inkSecondary.color)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(.rect)
                                .zoomSource(item.route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HomeEyebrow("More of you")
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                        link(HomeRoute.cycle, "moon", "Cycle", "Day and phase, from Cycle Tracking")
                        HomeHairline()
                        link(PulseRoute.category("Vitals"), "waveform.path.ecg", "Vitals", "Temperature, oxygen and breathing")
                        HomeHairline()
                        link(HomeRoute.medicalCard, "list.clipboard", "Medical card", "Blood type, allergies, who to call")
                    }
                }
            } else {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                        let found = matches
                        if found.isEmpty {
                            HomeNote("No match")
                        }
                        ForEach(Array(found.prefix(40).enumerated()), id: \.offset) { index, hit in
                            if index > 0 { HomeHairline() }
                            NavigationLink(value: PulseRoute.category(hit.category)) {
                                HomeValueRow(name: hit.title, detail: hit.category, value: nil)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await health.loadScores() }
    }

    private func link<Value: Hashable>(_ value: Value, _ symbol: String, _ title: String, _ detail: String) -> some View {
        NavigationLink(value: value) {
            HStack(spacing: theme.metrics.moveRowGap) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .frame(width: theme.metrics.aspectBadgeSide, height: theme.metrics.aspectBadgeSide)
                    .background(RoundedRectangle(cornerRadius: theme.metrics.aspectBadgeCornerRadius, style: .continuous)
                        .fill(theme.colors.surfaceRecessed.color))
                HomeValueRow(name: title, detail: detail, value: nil)
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .zoomSource(value)
        }
        .buttonStyle(.plain)
    }

    private var aspects: [Aspect] {
        let scores = health.scores
        return [
            Aspect(aspect: .sleep, title: "Sleep", detail: "Stages, timing, debt and the bedroom", score: scores?.sleep, route: TodayRoutes.allCategories(.sleep)),
            Aspect(aspect: .mind, title: "Mind", detail: "Stress, energy and mindful minutes", score: scores?.mind, route: TodayRoutes.allCategories(.mind)),
            Aspect(aspect: .heart, title: "Heart", detail: "Resting rate, HRV and blood pressure", score: nil, route: TodayRoutes.allCategories(.heart)),
            Aspect(aspect: .activity, title: "Activity", detail: "Steps, strain, zones and workouts", score: scores?.strain, route: TodayRoutes.allCategories(.activity)),
            Aspect(aspect: .gut, title: "Gut", detail: "Meals, glucose, water and caffeine", score: nil, route: TodayRoutes.allCategories(.gut)),
            Aspect(aspect: .body, title: "Body", detail: "Weight, composition and fitness age", score: nil, route: TodayRoutes.allCategories(.body)),
        ]
    }

    private var matches: [(title: String, category: String)] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return BodyCatalog.categories.flatMap { category in
            category.types.filter { $0.title.lowercased().contains(needle) }.map { ($0.title, category.title) }
        }
    }
}

// MARK: - Stand hours

/// The day's stand hours in a sheet: hours stood against the goal, the day
/// hour by hour, and the goal. The reminder belongs to Settings, Notifications
/// (``SomaNotifications``): this sheet only says whether it is on and links there.
struct HomeStandSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var hours: [HomeStandHour] = Array(repeating: .open, count: 24)
    @State private var isRead = false
    @State private var notifications = SomaNotifications.shared

    private var log: HomeLog { .shared }

    var body: some View {
        let stood = hours.filter { $0 == .stood }.count
        let missed = hours.filter { $0 == .missed }.count

        HomeSheet(eyebrow: "Activity · Stand", title: "Stand hours") {
            HomeValue(value: isRead ? "\(stood)" : nil, unit: "of \(log.standGoal) hours")
            HomeReason(reason(stood: stood, missed: missed))

            SomaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HomeEyebrow("Today, hour by hour")
                    HomeStandBars(hours: hours)
                }
            }

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                    NavigationLink(value: SettingsRoute.notifications) {
                        HStack(spacing: theme.metrics.moveRowGap) {
                            HomeValueRow(name: "Stand reminder", value: standReminderValue)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.colors.inkSecondary.color)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens notification settings"))
                    HomeHairline()
                    Stepper(value: Binding(get: { log.standGoal }, set: { log.standGoal = $0 }), in: 6...16) {
                        HomeValueRow(name: "Daily goal", value: "\(log.standGoal) hours")
                    }
                }
            }
            // Declared inside the sheet's own stack, so the link above lands.
            .navigationDestination(for: SettingsRoute.self) { $0.page }
        }
        .presentationDetents([.medium, .large])
        .task {
            await notifications.refreshAuthorization()
            guard let source = await health.prepare([HomeMetric.standHour]) else { isRead = true; return }
            let now = Date()
            let samples = await source.home(HomeMetric.standHour, days: 0, now: now)
            hours = HomeStandHour.day(samples, now: now, calendar: .current)
            isRead = true
        }
    }

    /// On only when the stand switch in Settings is on and Soma may notify.
    private var standReminderValue: String {
        notifications.isOn && notifications.schedule.stand
            ? String(localized: "On")
            : String(localized: "Off")
    }

    private func reason(stood: Int, missed: Int) -> String {
        guard isRead else { return "Reading today’s stand hours from Apple Health." }
        let left = log.standGoal - stood
        let open = hours.filter { $0 == .open || $0 == .now }.count
        if stood == 0 && missed == 0 {
            return "No stand hours recorded yet. Apple Watch counts an hour once you stand and move for a minute in it."
        }
        if left <= 0 { return "Goal reached. Every hour you stand from here is a bonus." }
        let tail = missed > 0 ? " \(missed == 1 ? "One hour" : "\(missed) hours") went by without one." : ""
        if left <= open {
            return "\(left == 1 ? "One more makes" : "\(left) more make") \(log.standGoal). A minute on your feet in each of the next \(left) hours will do it.\(tail)"
        }
        return "Too few hours left for \(log.standGoal) today; stand in the ones that remain.\(tail)"
    }
}
