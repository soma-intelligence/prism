import AppIntents
import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// How the day's log reads as text.
public enum LogText {
    public static let waterLabel = "Water"
    public static let caffeineLabel = "Caffeine"
    public static let moodsLabel = "Moods"
    public static let mealsLabel = "Meals"

    /// The day's water as its number and unit: "1.25" and "L" from a litre
    /// on, "400" and "ml" under it, "-" and no unit when the value is not a
    /// volume.
    public static func waterParts(ml: Double) -> (number: String, unit: String?) {
        guard ml.isFinite, ml >= 0 else { return ("-", nil) }
        let whole = min(ml, 100_000).rounded()
        guard whole >= 1000 else { return (String(Int(whole)), "ml") }
        let centilitres = Int((whole / 10).rounded())
        let litres = centilitres / 100
        let rest = centilitres % 100
        if rest == 0 { return (String(litres), "L") }
        let decimals = rest % 10 == 0 ? String(rest / 10) : String(format: "%02d", rest)
        return ("\(litres).\(decimals)", "L")
    }

    /// The day's water on one line: 1250 reads "1.25 L", 400 reads "400 ml".
    public static func water(ml: Double) -> String {
        let parts = waterParts(ml: ml)
        guard let unit = parts.unit else { return parts.number }
        return "\(parts.number) \(unit)"
    }

    /// The day's caffeine as a whole number of milligrams, or "-".
    public static func caffeine(mg: Double) -> String {
        guard let number = caffeineNumber(mg: mg) else { return "-" }
        return "\(number) mg"
    }

    static func caffeineNumber(mg: Double) -> String? {
        guard mg.isFinite, mg >= 0 else { return nil }
        return String(Int(min(mg, 100_000).rounded()))
    }

    /// How many moods or meals today, or "-" for a count that cannot be one.
    public static func count(_ n: Int) -> String {
        n >= 0 ? String(n) : "-"
    }

    /// What VoiceOver reads for the day's log, with the age when stale.
    public static func accessibility(_ model: LogMedium.Model) -> String {
        let tally = model.tally
        let reading = "\(waterLabel) \(water(ml: tally.waterMl)), "
            + "\(caffeineLabel) \(caffeine(mg: tally.caffeineMg)), "
            + "\(moodsLabel) \(count(tally.moods)), \(mealsLabel) \(count(tally.meals))"
        guard case .data(let freshness) = model.display, let age = StaleAge.text(freshness) else {
            return reading
        }
        return "\(reading), \(age)"
    }
}

/// What a log button does: two drinks logged in place, and two links that
/// open Prism on the right sheet.
enum LogAction: CaseIterable {
    case water, coffee, mood, meal

    /// The SF Symbol on the button.
    var symbol: String {
        switch self {
        case .water: "drop"
        case .coffee: "cup.and.saucer"
        case .mood: "face.smiling"
        case .meal: "fork.knife"
        }
    }

    /// What VoiceOver reads for the button.
    var label: String {
        switch self {
        case .water: "Log water"
        case .coffee: "Log coffee"
        case .mood: "Log mood"
        case .meal: "Log meal"
        }
    }
}

/// One log button: the glyph in ink on a circle of track ink. Water and
/// coffee run `LogDrinkIntent` without opening the app; mood and meal open
/// Prism where that entry is made.
struct LogButton: View {
    let action: LogAction
    /// Draws the faces alone, without a `Link` or an intent: the render review
    /// (`ImageRenderer` cannot draw a `Link` and leaves a placeholder in its
    /// place) and the app's gallery (a tap there must not log a real drink).
    /// The widget never sets it.
    var facesOnly = false
    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Group {
            switch action {
            case .water, .coffee:
                if runsIntent {
                    Button(intent: LogDrinkIntent(kind: action == .water ? .water : .coffee, ml: LogInbox.defaultMl)) { face }
                        .buttonStyle(.plain)
                } else {
                    face
                }
            case .mood:
                link(WidgetLink.mood.url)
            case .meal:
                link(WidgetLink.meal.url)
            }
        }
        .accessibilityLabel(Text(action.label))
    }

    /// Whether a tap logs a drink: water and coffee, unless drawn as faces.
    var runsIntent: Bool {
        !facesOnly && (action == .water || action == .coffee)
    }

    @ViewBuilder
    private func link(_ url: URL) -> some View {
        if facesOnly {
            face
        } else {
            Link(destination: url) { face }
        }
    }

    private var face: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        let diameter = theme.metrics.widgetLogButton
        return Image(systemName: action.symbol)
            .symbolVariant(.none)
            .symbolRenderingMode(.monochrome)
            .somaFont(theme.typography.widgetGlyph)
            .foregroundStyle(ink.primary)
            .widgetAccentable()
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(ink.track))
            .contentShape(Circle())
    }
}

/// The four buttons spread across the widget's width.
private struct LogButtonRow: View {
    let facesOnly: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(LogAction.allCases.enumerated()), id: \.offset) { index, action in
                if index > 0 { Spacer(minLength: 0) }
                LogButton(action: action, facesOnly: facesOnly)
            }
        }
    }
}

/// The day's water: its word over the number and unit.
private struct WaterFigure: View {
    let model: LogMedium.Model
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let parts = LogText.waterParts(ml: model.tally.waterMl)
        VStack(alignment: .leading, spacing: 0) {
            ValueLabel(LogText.waterLabel, aspect: .mind)
            NumberWithUnit(text: parts.number, unit: parts.unit, number: theme.typography.widgetHero, freshness: freshness)
        }
    }
}

/// A second figure: its word over a smaller number.
private struct LogFigure: View {
    let label: String
    let text: String
    let unit: String?
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ValueLabel(label)
            NumberWithUnit(text: text, unit: unit, number: theme.typography.widgetFigure, freshness: freshness)
        }
    }
}

/// The day's caffeine as a figure.
private struct CaffeineFigure: View {
    let model: LogMedium.Model
    let freshness: Freshness

    var body: some View {
        let number = LogText.caffeineNumber(mg: model.tally.caffeineMg)
        LogFigure(label: LogText.caffeineLabel, text: number ?? "-", unit: number == nil ? nil : "mg", freshness: freshness)
    }
}

/// The values of a log widget read as one element, so VoiceOver hears the
/// day once and then each button on its own.
private struct LogReading: ViewModifier {
    let model: LogMedium.Model

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LogText.accessibility(model)))
    }
}

/// The small Log widget: the day's water over its goal bar, and the water
/// button.
public struct LogSmall: View {
    private let model: LogMedium.Model

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date) {
        model = LogMedium.Model(snapshot: snapshot, pending: pending, now: now)
    }

    public var body: some View {
        Group {
            switch model.display {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                let metrics = theme.metrics
                VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                    WaterFigure(model: model, freshness: freshness)
                        .modifier(LogReading(model: model))
                    ThinBar(fraction: model.waterFraction, dimmed: freshness != .fresh, aspect: .mind)
                        .frame(height: metrics.widgetBarHeight)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        StaleAge(freshness)
                        Spacer(minLength: 0)
                        LogButton(action: .water)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(WidgetLink.journal.url)
    }
}

/// The medium Log widget: the day's water and caffeine over the four buttons.
public struct LogMedium: View {
    /// What every Log widget shows: the snapshot's tally with the taps not yet
    /// drained added for the day `now` falls on, so a tap shows at once.
    public struct Model: Equatable {
        /// The empty state without a snapshot, or the day and how fresh the
        /// snapshot is.
        let display: WidgetDisplay
        public let tally: SomaWidgetSnapshot.Tally

        public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date, calendar: Calendar = .current) {
            let day = SomaWidgetSnapshot.Tally.dayString(now, calendar: calendar)
            let base = snapshot?.tally ?? .empty(day: day)
            tally = base.adding(pending, day: day, calendar: calendar)
            // Logging needs the App Group, not Health data: any snapshot
            // shows the buttons, so a new user logs before the first scores.
            // No snapshot means the App Group was never written, and the
            // intent would throw.
            display = snapshot.map { .data($0.freshness(now: now)) } ?? .empty
        }

        /// How much of the water goal the day has reached, or nil without a
        /// goal, so the ring draws its track alone.
        public var waterFraction: Double? {
            let goal = tally.waterGoalMl
            guard goal.isFinite, goal > 0, tally.waterMl.isFinite else { return nil }
            return min(max(tally.waterMl / goal, 0), 1)
        }
    }

    private let model: Model
    private let facesOnly: Bool

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date) {
        self.init(snapshot: snapshot, pending: pending, now: now, facesOnly: false)
    }

    /// `facesOnly` draws the buttons without their links and intents, for the
    /// render review and the app's gallery; see `LogButton`.
    public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date, facesOnly: Bool) {
        model = Model(snapshot: snapshot, pending: pending, now: now)
        self.facesOnly = facesOnly
    }

    public var body: some View {
        Group {
            switch model.display {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                let metrics = theme.metrics
                VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                    HStack(alignment: .firstTextBaseline, spacing: metrics.widgetColumnSpacing) {
                        WaterFigure(model: model, freshness: freshness)
                            .frame(width: metrics.widgetLargeLabelColumn, alignment: .leading)
                        CaffeineFigure(model: model, freshness: freshness)
                        Spacer(minLength: 0)
                        StaleAge(freshness)
                    }
                    .modifier(LogReading(model: model))
                    Spacer(minLength: 0)
                    LogButtonRow(facesOnly: facesOnly)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(WidgetLink.journal.url)
    }
}

/// The large Log widget: the day's water over its goal bar, caffeine, moods
/// and meals in a row, and the four buttons.
public struct LogLarge: View {
    private let model: LogMedium.Model
    private let facesOnly: Bool

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date) {
        self.init(snapshot: snapshot, pending: pending, now: now, facesOnly: false)
    }

    /// `facesOnly` draws the buttons without their links and intents, for the
    /// render review and the app's gallery; see `LogButton`.
    public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date, facesOnly: Bool) {
        model = LogMedium.Model(snapshot: snapshot, pending: pending, now: now)
        self.facesOnly = facesOnly
    }

    public var body: some View {
        Group {
            switch model.display {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                let metrics = theme.metrics
                let tally = model.tally
                VStack(alignment: .leading, spacing: metrics.widgetBlockSpacing) {
                    VStack(alignment: .leading, spacing: metrics.widgetBlockSpacing) {
                        VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                            WaterFigure(model: model, freshness: freshness)
                            ThinBar(fraction: model.waterFraction, dimmed: freshness != .fresh, aspect: .mind)
                                .frame(height: metrics.widgetBarHeight)
                        }
                        HStack(alignment: .top, spacing: metrics.widgetColumnSpacing) {
                            CaffeineFigure(model: model, freshness: freshness)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            LogFigure(label: LogText.moodsLabel, text: LogText.count(tally.moods), unit: nil, freshness: freshness)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            LogFigure(label: LogText.mealsLabel, text: LogText.count(tally.meals), unit: nil, freshness: freshness)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .modifier(LogReading(model: model))
                    Spacer(minLength: 0)
                    LogButtonRow(facesOnly: facesOnly)
                    StaleFooter(freshness: freshness)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(WidgetLink.journal.url)
    }
}

/// The lock screen ring: the day's water against its goal, the number inside.
public struct LogCircular: View {
    private let model: LogMedium.Model

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    public init(snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date) {
        model = LogMedium.Model(snapshot: snapshot, pending: pending, now: now)
    }

    public var body: some View {
        Group {
            switch model.display {
            case .empty:
                WidgetEmpty(compact: true)
            case .data(let freshness):
                let ink = WidgetInk(theme: theme, mode: mode)
                let lineWidth = theme.metrics.widgetRingStroke
                let parts = LogText.waterParts(ml: model.tally.waterMl)
                InkRing(fraction: model.waterFraction, lineWidth: lineWidth, dimmed: freshness != .fresh)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(parts.number)
                                .somaFont(theme.typography.widgetGlance)
                                .foregroundStyle(ink.value(freshness))
                            if let unit = parts.unit {
                                Text(unit)
                                    .somaFont(theme.typography.widgetLabel)
                                    .foregroundStyle(ink.secondary)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(lineWidth + theme.metrics.widgetRingTextInset)
                    }
                    .modifier(LogReading(model: model))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetLink.journal.url)
    }
}

#Preview("Log small") {
    LogSmall(snapshot: .placeholder, pending: [], now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 170, height: 170)
}

#Preview("Log medium") {
    LogMedium(snapshot: .placeholder, pending: [], now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 170)
}

#Preview("Log large") {
    LogLarge(snapshot: .placeholder, pending: [], now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 382)
}

#Preview("Log circular") {
    LogCircular(snapshot: .placeholder, pending: [], now: SomaWidgetSnapshot.placeholder.generatedAt)
        .frame(width: 72, height: 72)
}
