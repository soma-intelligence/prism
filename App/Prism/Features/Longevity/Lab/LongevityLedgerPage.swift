//
//  LongevityLedgerPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The Longevity Ledger: minutes of life expectancy earned and spent today,
/// three weeks day by day, the five factors against your usual, and the
/// one move that earns the next minute.
///
/// Steps, exercise and sleep come from Health; alcohol and late caffeine
/// from the Journal's tags. A factor with nothing recorded counts nothing
/// and shows a dash.
struct LongevityLedgerPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var days: [LongevityLedger.Day] = []
    @State private var isShowingMethod = false

    private static let window = 21

    var body: some View {
        let recent = Array(days.suffix(Self.window))
        let breakdowns = recent.map { LongevityLedger.breakdown($0) }
        let today = breakdowns.last
        let total = breakdowns.map(\.net).reduce(0, +)

        TabPartScaffold(
            aspect: nil,
            eyebrow: "Today · \(Date.now.formatted(date: .omitted, time: .shortened))",
            title: headline(today),
            reason: reason(today, day: recent.last),
            stats: [
                SomaStat("Earned", value: today.flatMap { $0.earned > 0 ? LabMath.signed($0.earned, decimals: 0) : nil }),
                SomaStat("Spent", value: today.flatMap { $0.spent < 0 ? LabMath.signed($0.spent, decimals: 0) : nil }),
                SomaStat("Three weeks", value: breakdowns.contains { !$0.isEmpty } ? LabMath.signed(total, decimals: 0) : nil),
            ]
        ) {
            SomaChartCard(
                eyebrow: "Day by day",
                value: breakdowns.contains { !$0.isEmpty } ? LabMath.signed(total, decimals: 0) : nil,
                unit: "min, three weeks",
                note: breakdowns.contains { !$0.isEmpty } ? note(recent, breakdowns) : "Your watch and the Journal fill this, a day at a time."
            ) {
                LedgerDays(values: breakdowns.map { $0.isEmpty ? nil : $0.net })
                    .frame(height: 120)
            }
            LabBandCard(title: "The five factors", eyebrow: "Minutes today, against your usual", aspect: .activity,
                        items: LongevityLedger.Factor.allCases.map { factor in item(factor, recent: recent, breakdowns: breakdowns) })
            lever(recent.last)
            SomaBrowseGroup([LabRow("How the ledger counts"), LabRow("Share the balance")], hasGlyphs: false) { row in
                if row.id == "Share the balance" {
                    ShareLink(item: shareText(today: today, total: total)) {
                        SomaBrowseRow(title: row.title, opensSomething: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    SomaBrowseRow(title: row.title) { isShowingMethod = true }
                }
            }
            LabFootnote("Group averages, not a promise.")
        }
        .navigationTitle("Longevity Ledger")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $isShowingMethod) { LedgerMethodSheet(today: today) }
    }

    // MARK: Pieces

    private func item(_ factor: LongevityLedger.Factor, recent: [LongevityLedger.Day], breakdowns: [LongevityLedger.Breakdown]) -> LabBandItem {
        let today = breakdowns.last?.minutes[factor]
        let history = breakdowns.dropLast().compactMap { $0.minutes[factor] }
        let domain = -5.0...10.0
        func position(_ v: Double) -> Double { (min(max(v, domain.lowerBound), domain.upperBound) - domain.lowerBound) / (domain.upperBound - domain.lowerBound) }
        let usual = LabMath.usualBand(history).map { position($0.lowerBound)...position($0.upperBound) }
        let day = recent.last
        let detail: String = switch factor {
        case .steps: day?.steps.map { "\(Int($0).formatted()) steps" } ?? "Nothing from your watch"
        case .exercise: day?.exerciseMinutes.map { "\(Int($0)) active minutes" } ?? "Nothing from your watch"
        case .sleep: day?.sleepHours.map { "\(BodyMath.clock($0 * 3600)) asleep" } ?? "No night recorded"
        case .alcohol: day?.drinks == nil ? "Nothing in the Journal" : "Tagged in the Journal"
        case .caffeine: day?.lateCaffeineMg == nil ? "Nothing in the Journal" : "Coffee after 14:00, one cup counted"
        }
        return LabBandItem(
            id: factor.id, title: factor.title, detail: detail,
            value: today.map { "\(LabMath.signed($0, decimals: 0) ?? "0") min" },
            band: usual, position: today.map(position), isFlagged: (today ?? 0) < 0)
    }

    @ViewBuilder
    private func lever(_ day: LongevityLedger.Day?) -> some View {
        if let steps = day?.steps, steps < 10_000 {
            let toGo = Int((10_000 - steps).rounded())
            SomaActionCard(
                eyebrow: "Today’s lever",
                title: "Walk after dinner",
                detail: "\(toGo.formatted()) more steps take you to 10,000 and earn \(LabMath.format(LongevityLedger.stepMinutes(10_000) - LongevityLedger.stepMinutes(steps), decimals: 0) ?? "") more minutes."
            ) {
                SomaOrb(aspect: .activity, scale: .mini)
            }
        } else if (day?.sleepHours ?? 0) < 7 {
            SomaActionCard(
                eyebrow: "Tonight’s lever",
                title: "Seven hours in bed",
                detail: "A night between seven and nine hours earns two minutes; under six spends three."
            ) {
                SomaOrb(aspect: .sleep, scale: .mini)
            }
        }
    }

    private func headline(_ today: LongevityLedger.Breakdown?) -> String {
        guard let today, !today.isEmpty else { return "Nothing counted yet today." }
        let net = Int(today.net.rounded())
        switch net {
        case ..<0: return "\(minutes(-net)) behind today."
        case 0: return "Even so far today."
        default: return "\(minutes(net).labCapitalized) to the good."
        }
    }

    private func minutes(_ n: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let number = n < words.count ? words[n] : "\(n)"
        return "\(number) \(n == 1 ? "minute" : "minutes")"
    }

    private func reason(_ today: LongevityLedger.Breakdown?, day: LongevityLedger.Day?) -> String {
        guard let today, !today.isEmpty else {
            return "Steps, exercise and sleep come from your watch; alcohol and late coffee from the Journal. The ledger counts them as they arrive."
        }
        let earners = LongevityLedger.Factor.allCases.filter { (today.minutes[$0] ?? 0) > 0 }.map { $0.title.lowercased() }
        let spenders = LongevityLedger.Factor.allCases.filter { (today.minutes[$0] ?? 0) < 0 }.map { $0.title.lowercased() }
        var text = earners.isEmpty ? "Nothing has earned yet." : "Your \(list(earners)) earned \(LabMath.format(today.earned, decimals: 0) ?? "")."
        if !spenders.isEmpty { text += " \(list(spenders).labCapitalized) cost \(LabMath.format(-today.spent, decimals: 0) ?? "")." }
        return text
    }

    private func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
    }

    private func note(_ days: [LongevityLedger.Day], _ breakdowns: [LongevityLedger.Breakdown]) -> String {
        let costly = zip(days, breakdowns).filter { $0.1.net < 0 }
        guard !costly.isEmpty else { return "No day in three weeks spent more than it earned." }
        let short = costly.filter { ($0.0.sleepHours ?? 9) < 6 }.count
        if short * 2 >= costly.count { return "The costly days followed short nights." }
        return "\(costly.count) of \(days.count) days spent more than they earned."
    }

    private func shareText(today: LongevityLedger.Breakdown?, total: Double) -> String {
        let net = today.flatMap { $0.isEmpty ? nil : LabMath.signed($0.net, decimals: 0) } ?? "0"
        return "My Longevity Ledger on Soma: \(net) min today, \(LabMath.signed(total, decimals: 0) ?? "0") min over three weeks."
    }

    private func load() async {
        let now = Date()
        guard let source = await health.prepare([]) else { return }
        let daily = await LabHealth.daily(from: source, now: now, calendar: .current)
        days = LongevityLedger.days(from: daily, tags: { journal.day($0).tags }, now: now, calendar: .current)
    }
}

private extension String {
    var labCapitalized: String { prefix(1).uppercased() + dropFirst() }
}

/// Three weeks as stems from zero: earned days up, spent days down, today in
/// full colour.
private struct LedgerDays: View {
    let values: [Double?]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let limit = max(values.compactMap { $0 }.map(abs).max() ?? 5, 5)
            let mid = size.height / 2
            let step = size.width / CGFloat(values.count)
            let dot = theme.metrics.chartDotDiameter
            let hairline = theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: mid))
            axis.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(axis, with: .color(hairline), lineWidth: 1)
            let hue = theme.aspects[.activity].identity.color
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let x = step * (CGFloat(index) + 0.5)
                let y = mid - (mid - dot) * CGFloat(value / limit)
                let colour = value < 0 ? theme.colors.danger.color : hue
                let opacity = index == values.count - 1 ? 1 : theme.metrics.chartContextOpacity
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: mid))
                stem.addLine(to: CGPoint(x: x, y: y))
                context.stroke(stem, with: .color(colour.opacity(opacity)), lineWidth: 1.5)
                context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)), with: .color(colour.opacity(opacity)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// How the ledger counts, on the explainer: today's minutes per factor as
/// signed bars, and each factor's coefficient as a row.
private struct LedgerMethodSheet: View {
    let today: LongevityLedger.Breakdown?

    @Environment(\.dismiss) private var dismiss

    private static let looks: [LongevityLedger.Factor: (symbol: String, hue: SomaHealthHue, line: String, rate: String)] = [
        .steps: ("figure.walk", .activity, "Counts up to 10,000.", "+1 per 1,000"),
        .exercise: ("flame.fill", .mobility, "Each active minute.", "+0.3"),
        .sleep: ("moon.fill", .sleep, "7 to 9 hours earns; under 6 or over 9 spends.", "+2 or \u{2212}3"),
        .alcohol: ("wineglass.fill", .symptoms, "The first is free. A tag counts one.", "\u{2212}5 a drink"),
        .caffeine: ("cup.and.saucer.fill", .nutrition, "After 14:00. A tag counts one cup.", "\u{2212}2 per 100 mg"),
    ]

    var body: some View {
        let net = today.flatMap { $0.isEmpty ? nil : $0.net }

        SomaExplainer(title: "How it counts", summary: "Minutes of life expectancy, from large studies. A day is the sum.",
                      aspect: .activity, onClose: { dismiss() }) {
            SomaExplainerRing(fraction: min(1, max(0, ((net ?? 0) + 10) / 20)),
                              value: net.map { LabMath.signed($0, decimals: 0) ?? "-" } ?? "-",
                              caption: "min today", aspect: .activity)
        } content: {
            if let today, !today.isEmpty {
                SomaExplainerMoves("Today", moves: LongevityLedger.Factor.allCases.compactMap { factor in
                    guard let minutes = today.minutes[factor], let look = Self.looks[factor] else { return nil }
                    return SomaExplainerMove(title: factor.title, value: LabMath.signed(minutes, decimals: 1) ?? "-",
                                             hue: look.hue, shape: .signed(minutes / 10))
                })
            }
            SomaExplainerSection("Each factor") {
                ForEach(LongevityLedger.Factor.allCases) { factor in
                    if let look = Self.looks[factor] {
                        SomaExplainerRow(symbol: look.symbol, hue: look.hue, term: factor.title, line: look.line,
                                         trailing: look.rate)
                    }
                }
            }
            SomaExplainerNote("Group averages, not a promise.")
        }
    }
}

#Preview("Longevity ledger") {
    NavigationStack {
        LongevityLedgerPage()
    }
    .environment(HealthDashboard())
    .environment(JournalStore(url: nil))
}
