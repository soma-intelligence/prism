//
//  HomeLogSheets.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - Daily check-in

/// The evening check-in: energy and stress on five levels, the body in one
/// word, and anything unusual as tags. Tags the Journal also offers are
/// ticked there too, so its effects count them.
struct HomeCheckInSheet: View {
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme
    @State private var energy = 3
    @State private var stress = 2
    @State private var body_: Set<String> = [HomeBodyFeel.normal.title]
    @State private var tags: Set<String> = []

    private var log: HomeLog { .shared }

    /// Check-in tags and the Journal tag each one ticks.
    static let tags: [(String, String?)] = [
        ("Alcohol", "alcohol"), ("Late caffeine", "coffee-late"), ("Travel", "travel"),
        ("Period", nil), ("Poor sleep", nil), ("A cold", nil), ("Big meal", "late-meal"),
    ]

    var body: some View {
        HomeInputSheet(title: "Evening check-in", actionTitle: "Save check-in", action: save) {
            Text("How was today?")
                .somaFont(theme.typography.title)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(maxWidth: .infinity)

            HomeLevelsRow(title: "Energy", words: ["Very low", "Low", "Some", "High", "Very high"], aspect: .activity, level: $energy)
            HomeLevelsRow(title: "Stress", words: ["None", "Some", "Moderate", "High", "Very high"], aspect: .mind, level: $stress)

            HomeChipGroup(title: "Body", options: HomeBodyFeel.allCases.map(\.title), chosen: $body_, single: true)
            HomeChipGroup(title: "Anything else today?", options: Self.tags.map(\.0), chosen: $tags)
        }
        .onAppear {
            guard let saved = log.checkIn(on: Date()) else { return }
            energy = saved.energy
            stress = saved.stress
            body_ = [saved.body.title]
            tags = Set(saved.tags)
        }
    }

    private func save() {
        let now = Date()
        let feel = HomeBodyFeel.allCases.first { body_.contains($0.title) } ?? .normal
        log.addCheckIn(HomeCheckIn(date: now, energy: energy, stress: stress, body: feel, tags: tags.sorted()))
        let offered = Set(journal.offeredTags.map(\.id))
        for (title, id) in Self.tags {
            guard let id, tags.contains(title), offered.contains(id), !journal.day(now).tags.contains(id) else { continue }
            journal.toggle(id, on: now)
        }
        Confirmations.shared.done("Check-in saved")
    }
}

/// Five bars that rise, the chosen level lit in the aspect's hue.
struct HomeLevelsRow: View {
    let title: String
    let words: [String]
    let aspect: SomaAspect
    @Binding var level: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color

        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(words[level - 1])
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(1...5, id: \.self) { step in
                    Button { level = step } label: {
                        RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius * 2)
                            .fill(step <= level ? hue : theme.colors.surface.color)
                            .frame(width: metrics.minimumTapTarget * 0.5, height: metrics.minimumTapTarget * (0.3 + 0.18 * CGFloat(step)))
                    }
                    .buttonStyle(SomaGlassPressStyle())
                    .accessibilityLabel(Text("\(title) \(words[step - 1])"))
                    .accessibilityAddTraits(step == level ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Workout effort

/// How hard today's last workout was, on a dial from 1 to 10, beside Soma's
/// own read from the heart. The rating feeds the week's load.
struct HomeEffortSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var day: HomeDay?
    @State private var rating = 5

    private var log: HomeLog { .shared }

    var body: some View {
        let workout = day?.workouts.last
        let read = workout.flatMap { HomeEffortMath.somaRead(averageHeartRate: $0.averageHeartRate ?? averageHeart($0), age: day?.inputs.age) }

        HomeInputSheet(
            title: workout.map { "\($0.name), \(HomeFormat.clock($0.start))" } ?? "Workout",
            actionTitle: "Save effort",
            isEnabled: workout != nil,
            action: { save(workout) }
        ) {
            Text("How hard was it?")
                .somaFont(theme.typography.title)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(maxWidth: .infinity)
            if let workout {
                HomeNote(detail(workout))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                HomeEffortDial(rating: $rating, somaRead: read)
                    .frame(maxWidth: .infinity)
                HomeNote(loadLine)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                HomeNote(day == nil ? "Reading workouts." : "No workout today.")
            }
        }
        .task {
            day = await HomeDay.load(health: health, log: log)
            if let workout = day?.workouts.last {
                rating = log.effort(for: workout.start)?.rating
                    ?? HomeEffortMath.somaRead(averageHeartRate: workout.averageHeartRate ?? averageHeart(workout), age: day?.inputs.age)
                    ?? 5
            }
        }
    }

    private func averageHeart(_ workout: PulseWorkout) -> Double? {
        let during = day?.inputs.heartRate.filter { $0.start >= workout.start && $0.start <= workout.end }.map(\.value) ?? []
        return during.isEmpty ? nil : during.reduce(0, +) / Double(during.count)
    }

    private func detail(_ workout: PulseWorkout) -> String {
        var parts = [SomaFormat.duration(workout.minutes * 60)]
        if let zone = workout.zoneThreeMinutes { parts.append("\(SomaFormat.duration(zone * 60)) in zone 3 and above") }
        if let steps = workout.steps { parts.append("\(HomeFormat.whole(steps)) steps") }
        return parts.joined(separator: " · ")
    }

    private var loadLine: String {
        guard let load = HomeEffortMath.weekLoad(log.efforts, now: Date(), calendar: .current) else {
            return "Each rating times its minutes adds up to the week’s load."
        }
        return "This week’s load so far: \(HomeFormat.whole(load)), from the workouts you rated."
    }

    private func save(_ workout: PulseWorkout?) {
        guard let workout else { return }
        log.setEffort(HomeEffort(workoutStart: workout.start, minutes: workout.minutes, rating: rating))
        Confirmations.shared.done("Effort saved")
    }
}

/// A dial from 1 to 10 that warms as it rises. Drag round it or tap a step;
/// Soma's own read sits as a dot on its step.
struct HomeEffortDial: View {
    @Binding var rating: Int
    let somaRead: Int?

    @Environment(\.somaTheme) private var theme

    /// The dial's sweep, in degrees clockwise from twelve.
    private let startAngle = -130.0
    private let sweep = 260.0

    var body: some View {
        let diameter = theme.metrics.orbDiameter * 0.9
        let hue = theme.aspects[.activity].identity.color

        ZStack {
            ForEach(1...10, id: \.self) { step in
                let from = (Double(step - 1) / 10) * sweep / 360
                let to = (Double(step) / 10) * sweep / 360 - 0.008
                Circle()
                    .trim(from: from, to: to)
                    .stroke(step <= rating ? hue.opacity(0.35 + 0.065 * Double(step)) : theme.colors.surface.color,
                            style: StrokeStyle(lineWidth: diameter * 0.06, lineCap: .round))
                    .rotationEffect(.degrees(startAngle - 90))
            }
            if let somaRead {
                Circle()
                    .fill(theme.colors.inkPrimary.color)
                    .frame(width: theme.metrics.chartDotDiameter, height: theme.metrics.chartDotDiameter)
                    .offset(y: -diameter / 2 - theme.metrics.cardSpacing)
                    .rotationEffect(.degrees(startAngle + (Double(somaRead) - 0.5) / 10 * sweep))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 2) {
                Text("\(rating)")
                    .somaFont(theme.typography.display)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .contentTransition(.numericText())
                Text(HomeEffortMath.word(rating))
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                if let somaRead {
                    Text("Soma read \(somaRead)")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(.circle)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - diameter / 2
            let dy = value.location.y - diameter / 2
            var angle = atan2(dx, -dy) * 180 / .pi
            if angle < startAngle - 20 { angle += 360 }
            let share = (angle - startAngle) / sweep
            rating = min(10, max(1, Int((share * 10).rounded(.up))))
        })
        .padding(theme.metrics.spaceXL)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Effort"))
        .accessibilityValue(Text("\(rating), \(HomeEffortMath.word(rating))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(10, rating + 1)
            case .decrement: rating = max(1, rating - 1)
            @unknown default: break
            }
        }
    }
}
