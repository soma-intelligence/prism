import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// How the day's energy in and out reads as text.
public enum FuelText {
    public static let netLabel = "Net"
    public static let burnedLabel = "Burned"
    public static let eatenLabel = "Eaten"
    public static let kcalUnit = "kcal"

    /// Eaten less burned, rounded to 10: "+120", "-330", "0", or "-" when
    /// either side is missing.
    public static func net(burned: Double?, eaten: Double?) -> String {
        guard let burned, let eaten, burned.isFinite, eaten.isFinite else { return "-" }
        let difference = min(max(eaten - burned, -100_000), 100_000)
        let rounded = Int((difference / 10).rounded()) * 10
        if rounded > 0 { return "+\(rounded)" }
        return String(rounded)
    }

    /// A day's kilocalories as a whole number, or "-".
    public static func kcal(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        return String(Int(min(max(value, 0), 100_000).rounded()))
    }

    /// How far each bar fills: both scaled to the larger of the two. A
    /// missing side stays nil, so its bar draws the track alone.
    public static func fractions(burned: Double?, eaten: Double?) -> (burned: Double?, eaten: Double?) {
        let clean: (Double?) -> Double? = { value in
            guard let value, value.isFinite else { return nil }
            return max(value, 0)
        }
        let b = clean(burned)
        let e = clean(eaten)
        let larger = max(b ?? 0, e ?? 0)
        let share: (Double?) -> Double? = { value in
            guard let value else { return nil }
            return larger > 0 ? value / larger : 0
        }
        return (share(b), share(e))
    }

    /// The snapshot as Fuel reads it at `now`: burned and eaten are the
    /// totals of the snapshot's own day (its tally's), so after midnight they
    /// read "-" until the app writes today's.
    public static func today(_ snapshot: SomaWidgetSnapshot, now: Date, calendar: Calendar = .current) -> SomaWidgetSnapshot {
        guard snapshot.tally.day != SomaWidgetSnapshot.Tally.dayString(now, calendar: calendar) else { return snapshot }
        var result = snapshot
        result.burnedKcal = nil
        result.eatenKcal = nil
        return result
    }

    /// What VoiceOver reads for the Fuel widget, with the age when stale.
    public static func accessibility(_ snapshot: SomaWidgetSnapshot, _ freshness: Freshness) -> String {
        let net = net(burned: snapshot.burnedKcal, eaten: snapshot.eatenKcal)
        let reading = "\(netLabel) \(net) \(kcalUnit), \(burnedLabel) \(kcal(snapshot.burnedKcal)), \(eatenLabel) \(kcal(snapshot.eatenKcal))"
        guard let age = StaleAge.text(freshness) else { return reading }
        return "\(reading), \(age)"
    }
}

/// The net figure: its word over the number and unit.
private struct NetFigure: View {
    let snapshot: SomaWidgetSnapshot
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ValueLabel(FuelText.netLabel)
            NumberWithUnit(
                text: FuelText.net(burned: snapshot.burnedKcal, eaten: snapshot.eatenKcal),
                unit: FuelText.kcalUnit,
                number: theme.typography.widgetHero,
                freshness: freshness
            )
        }
    }
}

/// One side of the day: its word and number on one line, the bar under it.
private struct FuelBar: View {
    let label: String
    let value: Double?
    let fraction: Double?
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.widgetRowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                ValueLabel(label)
                Spacer(minLength: 0)
                Text(FuelText.kcal(value))
                    .somaFont(theme.typography.widgetRowValue)
                    .foregroundStyle(WidgetInk(theme: theme, mode: mode).value(freshness))
                    .lineLimit(1)
            }
            ThinBar(fraction: fraction, dimmed: freshness != .fresh)
                .frame(height: theme.metrics.widgetBarHeight)
        }
    }
}

/// The two bars, burned over eaten.
private struct FuelBars: View {
    let snapshot: SomaWidgetSnapshot
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let shares = FuelText.fractions(burned: snapshot.burnedKcal, eaten: snapshot.eatenKcal)
        VStack(alignment: .leading, spacing: theme.metrics.widgetLabelSpacing) {
            FuelBar(label: FuelText.burnedLabel, value: snapshot.burnedKcal, fraction: shares.burned, freshness: freshness)
            FuelBar(label: FuelText.eatenLabel, value: snapshot.eatenKcal, fraction: shares.eaten, freshness: freshness)
        }
    }
}

/// The small Fuel widget: the net figure, then burned and eaten as two bars.
public struct FuelSmall: View {
    private let snapshot: SomaWidgetSnapshot?
    private let now: Date

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        Group {
            switch WidgetDisplay(snapshot: snapshot, now: now) {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                if let snapshot = snapshot.map({ FuelText.today($0, now: now) }) {
                    VStack(alignment: .leading, spacing: theme.metrics.widgetLabelSpacing) {
                        NetFigure(snapshot: snapshot, freshness: freshness)
                        Spacer(minLength: 0)
                        FuelBars(snapshot: snapshot, freshness: freshness)
                        StaleFooter(freshness: freshness)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(FuelText.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.fuel.url)
    }
}

/// The medium Fuel widget: the net figure on the leading side, the two bars
/// beside it.
public struct FuelMedium: View {
    private let snapshot: SomaWidgetSnapshot?
    private let now: Date

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        Group {
            switch WidgetDisplay(snapshot: snapshot, now: now) {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                if let snapshot = snapshot.map({ FuelText.today($0, now: now) }) {
                    let metrics = theme.metrics
                    VStack(spacing: metrics.widgetLabelSpacing) {
                        HStack(alignment: .center, spacing: metrics.widgetColumnSpacing) {
                            NetFigure(snapshot: snapshot, freshness: freshness)
                                .frame(width: metrics.widgetLargeLabelColumn, alignment: .leading)
                            FuelBars(snapshot: snapshot, freshness: freshness)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                        StaleFooter(freshness: freshness)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(FuelText.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.fuel.url)
    }
}

#Preview("Fuel small") {
    FuelSmall(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 170, height: 170)
}

#Preview("Fuel medium") {
    FuelMedium(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 170)
}
