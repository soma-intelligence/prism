//
//  TrackIntakeView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Intake, today: the day's glass, filled by each drink in the order it was
/// poured, and the caffeine still on board against bedtime.
///
/// The drinks are the ones logged in Soma, with their times; the caffeine is
/// The caffeine model (five hour half life, 25 mg at bedtime as the line) run over
/// them. Bedtime is the usual night's from Apple Health, or 23:00 until there
/// are three nights to read.
struct TrackIntakeView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health

    @State private var window: (from: Double, to: Double)?
    @State private var adding: TrackRoute?

    private let log = TrackLogStore.shared
    private let calendar = Calendar.current
    /// The bedtime assumed before Health holds three nights.
    private static let fallbackBedtime = 23.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .task { window = await TrackHealthReads.sleepWindow(from: health) }
        .trackEntrySheet(item: $adding)
    }

    private func content(now: Date) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let drinks = log.drinks(on: now)
        let total = drinks.reduce(0) { $0 + $1.ml }
        let goal = log.waterGoalMl
        let scale = max(goal, total)

        return TrackEntryPage(title: "Today") {
            ZStack(alignment: .top) {
                SomaVessel(fill: total / scale, aspect: .mind, marks: marks(drinks, scale: scale))
                    .frame(height: metrics.vesselHeight * 1.2)
                    .padding(.trailing, metrics.orbDiameter * 0.55)
                Text(total >= goal ? "Goal reached" : "\(TrackIntake.litres(goal - total)) L to go")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.top, metrics.leadSpacing)
                    .padding(.trailing, metrics.orbDiameter * 0.55)
            }
            .frame(maxWidth: .infinity)

            SomaReadout(drinks.isEmpty ? nil : TrackIntake.litres(total), unit: "L", caption: "of \(TrackIntake.litres(goal)) L")

            caffeine(now: now)
        } footer: {
            SomaActionButton("Add a drink") { adding = .drink(.water) }
        }
    }

    private func marks(_ drinks: [TrackDrinkEntry], scale: Double) -> [SomaVessel.Mark] {
        var bottom = 0.0
        return drinks.enumerated().map { index, drink in
            let top = bottom + drink.ml / max(scale, 1)
            defer { bottom = top }
            return SomaVessel.Mark(id: index, top: top, bottom: bottom, label: "\(TrackClock.time(drink.date))   \(Int(drink.ml)) ml")
        }
    }

    private func caffeine(now: Date) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let bedHour = window?.from ?? Self.fallbackBedtime
        let bedtime = TrackFasting.nextStart(at: bedHour, from: now, calendar: calendar)
        let doses = log.caffeineDoses(before: now)
        let reading = TrackCaffeine.read(doses: doses, bedtime: bedtime, now: now)
        let today = log.drinks(on: now).reduce(0) { $0 + $1.caffeineMg }
        let curve = TrackCaffeine.curve(doses: doses, from: now, to: bedtime, count: 24)
        let peak = max(curve.max() ?? 0, 1)
        let hue = theme.aspects[.activity].identity.color

        return VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Caffeine")
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer()
                Text(today > 0 ? "\(Int(today)) mg today" : "None logged today")
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }

            ZStack(alignment: .trailing) {
                Capsule()
                    .fill(LinearGradient(
                        stops: curve.enumerated().map { index, value in
                            .init(color: hue.opacity(0.15 + 0.85 * value / peak), location: Double(index) / Double(max(curve.count - 1, 1)))
                        },
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: metrics.chartTrackHeight * 1.5)
                Circle()
                    .fill(theme.aspects[.sleep].identity.color)
                    .frame(width: metrics.aspectDotSize * 2, height: metrics.aspectDotSize * 2)
            }
            .accessibilityHidden(true)

            HStack {
                Text("\(Int(reading.onBoardNowMg.rounded())) mg now")
                Spacer()
                Text("\(Int(reading.atBedtimeMg.rounded())) mg at \(TrackClock.time(bedtime))")
            }
            .somaFont(type.captionValue)
            .foregroundStyle(colors.inkSecondary.color)

            TrackLeadText(lead: lastCallLine(reading), rest: window == nil ? "Bedtime taken as 23:00 until Health holds three nights." : nil)
                .padding(.top, metrics.cardSpacing * 0.5)
        }
    }

    private func lastCallLine(_ reading: TrackCaffeine.Reading) -> String {
        if reading.isOverBudget {
            return "No more caffeine today: bedtime is already over \(Int(TrackCaffeine.bedtimeThresholdMg)) mg."
        }
        guard let lastCall = reading.lastCall else { return "No more caffeine today." }
        if lastCall < reading.now { return "A coffee now would still be in you at bedtime." }
        return "Last coffee by \(TrackClock.time(lastCall))."
    }
}

#if DEBUG
#Preview("Intake") {
    NavigationStack { TrackIntakeView() }
        .environment(HealthDashboard())
}
#endif
