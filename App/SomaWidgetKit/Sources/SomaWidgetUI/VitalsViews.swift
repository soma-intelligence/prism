import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// How the vitals read as text.
public enum VitalsText {
    public static let restingLabel = "Resting"
    public static let hrvLabel = "HRV"
    public static let sleepLabel = "Sleep"
    public static let bpm = "bpm"
    public static let ms = "ms"

    /// Hours of sleep as "h:mm", 7.2 reads "7:12"; "-" when there is none.
    public static func sleep(hours: Double?) -> String {
        guard let hours, hours.isFinite, hours >= 0 else { return "-" }
        let minutes = Int((min(hours, 48) * 60).rounded())
        let rest = minutes % 60
        return "\(minutes / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// A heart rate or an HRV as a whole number, or "-". Clamped first, so a
    /// corrupt snapshot cannot overflow the conversion.
    public static func whole(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        return String(Int(min(max(value, 0), 9999).rounded()))
    }

    /// The lock screen line: "52 bpm  64 ms  7:12". A missing value is a
    /// dash alone, without its unit.
    public static func inline(_ snapshot: SomaWidgetSnapshot) -> String {
        VitalKind.allCases.map { withUnit($0.text(snapshot), $0.unit) }.joined(separator: "  ")
    }

    /// A value and its unit, or the dash alone.
    static func withUnit(_ text: String, _ unit: String?) -> String {
        guard let unit, text != "-" else { return text }
        return "\(text) \(unit)"
    }

    /// What VoiceOver reads for the whole widget, with the age when stale.
    public static func accessibility(_ snapshot: SomaWidgetSnapshot, _ freshness: Freshness) -> String {
        let reading = VitalKind.allCases
            .map { "\($0.label) \(withUnit($0.text(snapshot), $0.unit))" }
            .joined(separator: ", ")
        guard let age = StaleAge.text(freshness) else { return reading }
        return "\(reading), \(age)"
    }
}

/// The three vitals, in the order every Vitals widget draws them.
enum VitalKind: CaseIterable {
    case resting, hrv, sleep

    var label: String {
        switch self {
        case .resting: VitalsText.restingLabel
        case .hrv: VitalsText.hrvLabel
        case .sleep: VitalsText.sleepLabel
        }
    }

    /// Sleep reads as a clock, so it carries no unit.
    var unit: String? {
        switch self {
        case .resting: VitalsText.bpm
        case .hrv: VitalsText.ms
        case .sleep: nil
        }
    }

    func vital(_ snapshot: SomaWidgetSnapshot) -> SomaWidgetSnapshot.Vital {
        switch self {
        case .resting: snapshot.restingHR
        case .hrv: snapshot.hrv
        case .sleep: snapshot.sleepHours
        }
    }

    func text(_ snapshot: SomaWidgetSnapshot) -> String {
        switch self {
        case .resting, .hrv: VitalsText.whole(vital(snapshot).value)
        case .sleep: VitalsText.sleep(hours: vital(snapshot).value)
        }
    }
}

/// A number with its unit after it on the same baseline.
struct NumberWithUnit: View {
    let text: String
    let unit: String?
    let number: SomaFontSpec
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.widgetUnitSpacing) {
            Text(text)
                .somaFont(number)
                .foregroundStyle(ink.value(freshness))
            // A dash stands alone: "- ms" would read as a value.
            if let unit, text != "-" {
                Text(unit)
                    .somaFont(theme.typography.widgetUnit)
                    .foregroundStyle(ink.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// A value's word, in the secondary ink.
struct ValueLabel: View {
    let text: String

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.widgetLabel)
            .foregroundStyle(WidgetInk(theme: theme, mode: mode).secondary)
            .lineLimit(1)
    }
}

/// The hypnogram's rows and the ink each one carries.
enum Hypnogram {
    static let rows: [Stage.Kind] = [.awake, .rem, .core, .deep]

    static func opacity(_ kind: Stage.Kind, _ metrics: SomaMetrics) -> Double {
        switch kind {
        case .awake: metrics.widgetStageAwakeOpacity
        case .rem: metrics.widgetStageRemOpacity
        case .core: metrics.widgetStageCoreOpacity
        case .deep: metrics.widgetStageDeepOpacity
        }
    }

    static func label(_ kind: Stage.Kind) -> String {
        switch kind {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        }
    }

    /// Each stage of one kind as a share of the night, start and end on 0...1.
    static func spans(_ stages: [Stage], kind: Stage.Kind) -> [ClosedRange<Double>] {
        guard let start = stages.map(\.start).min(), let end = stages.map(\.end).max() else { return [] }
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return [] }
        return stages.filter { $0.kind == kind && $0.end > $0.start }.map { stage in
            let lower = min(max(stage.start.timeIntervalSince(start) / length, 0), 1)
            let upper = min(max(stage.end.timeIntervalSince(start) / length, 0), 1)
            return lower...max(lower, upper)
        }
    }
}

/// One hypnogram row: the stretches of the night spent in one stage.
struct StageRowShape: Shape {
    var spans: [ClosedRange<Double>]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for span in spans {
            path.addRect(CGRect(
                x: rect.minX + rect.width * span.lowerBound,
                y: rect.minY,
                width: rect.width * (span.upperBound - span.lowerBound),
                height: rect.height
            ))
        }
        return path
    }
}

/// Last night as four rows, awake at the top, deep at the bottom, each in its
/// own ink.
struct HypnogramStrip: View {
    let stages: [Stage]
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let metrics = theme.metrics
        let ink = WidgetInk(theme: theme, mode: mode).value(freshness)
        VStack(spacing: metrics.widgetStageRowGap) {
            ForEach(Hypnogram.rows, id: \.self) { kind in
                HStack(spacing: metrics.widgetRowGap) {
                    ValueLabel(Hypnogram.label(kind))
                        .frame(width: metrics.widgetStageLabelColumn, alignment: .leading)
                    ZStack {
                        Rectangle().fill(WidgetInk(theme: theme, mode: mode).track)
                        StageRowShape(spans: Hypnogram.spans(stages, kind: kind))
                            .fill(ink.opacity(Hypnogram.opacity(kind, metrics)))
                            .widgetAccentable()
                    }
                    .frame(height: metrics.widgetStageRowHeight)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One vital as its word, its number and unit, and its week as a trace.
private struct VitalColumn: View {
    let kind: VitalKind
    let snapshot: SomaWidgetSnapshot
    let number: SomaFontSpec
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.widgetRowSpacing) {
            ValueLabel(kind.label)
            NumberWithUnit(text: kind.text(snapshot), unit: kind.unit, number: number, freshness: freshness)
            Spacer(minLength: 0)
            HairlineTrace(values: kind.vital(snapshot).series7, showsNowDot: true, dimmed: freshness != .fresh)
                .frame(height: theme.metrics.widgetTraceHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One vital as a row: word and number on the leading side, the week's trace
/// across the rest.
private struct VitalRow: View {
    let kind: VitalKind
    let snapshot: SomaWidgetSnapshot
    let number: SomaFontSpec
    let labelWidth: CGFloat
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(spacing: theme.metrics.widgetColumnSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                ValueLabel(kind.label)
                NumberWithUnit(text: kind.text(snapshot), unit: kind.unit, number: number, freshness: freshness)
            }
            .frame(width: labelWidth, alignment: .leading)
            HairlineTrace(values: kind.vital(snapshot).series7, showsNowDot: true, dimmed: freshness != .fresh)
        }
    }
}

/// The small Vitals widget: resting heart rate, HRV and sleep stacked, each
/// with its week as a trace.
public struct VitalsSmall: View {
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
                if let snapshot {
                    let metrics = theme.metrics
                    VStack(alignment: .leading, spacing: metrics.widgetRowSpacing) {
                        ForEach(VitalKind.allCases, id: \.self) { kind in
                            VitalRow(
                                kind: kind,
                                snapshot: snapshot,
                                number: theme.typography.widgetFigure,
                                labelWidth: metrics.widgetRowLabelColumn,
                                freshness: freshness
                            )
                            .frame(maxHeight: .infinity)
                        }
                        StaleFooter(freshness: freshness)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(VitalsText.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.vitals.url)
    }
}

/// The medium Vitals widget: three columns, each a big number over its week.
public struct VitalsMedium: View {
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
                if let snapshot {
                    VStack(spacing: theme.metrics.widgetLabelSpacing) {
                        HStack(spacing: theme.metrics.widgetColumnSpacing) {
                            ForEach(VitalKind.allCases, id: \.self) { kind in
                                VitalColumn(
                                    kind: kind,
                                    snapshot: snapshot,
                                    number: theme.typography.widgetValue,
                                    freshness: freshness
                                )
                            }
                        }
                        StaleFooter(freshness: freshness)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(VitalsText.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.vitals.url)
    }
}

/// The large Vitals widget: three rows of a big number beside its week, then
/// last night's hypnogram.
public struct VitalsLarge: View {
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
                if let snapshot {
                    let metrics = theme.metrics
                    VStack(alignment: .leading, spacing: metrics.widgetBlockSpacing) {
                        ForEach(VitalKind.allCases, id: \.self) { kind in
                            VitalRow(
                                kind: kind,
                                snapshot: snapshot,
                                number: theme.typography.widgetHero,
                                labelWidth: metrics.widgetLargeLabelColumn,
                                freshness: freshness
                            )
                            .frame(maxHeight: .infinity)
                        }
                        if let stages = snapshot.hypnogram, !stages.isEmpty {
                            HypnogramStrip(stages: stages, freshness: freshness)
                        }
                        StaleFooter(freshness: freshness)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(VitalsText.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.vitals.url)
    }
}

/// The lock screen rectangle: three rows of word, week and number.
public struct VitalsRectangular: View {
    private let snapshot: SomaWidgetSnapshot?
    private let now: Date

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

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
                if let snapshot {
                    let metrics = theme.metrics
                    let ink = WidgetInk(theme: theme, mode: mode)
                    VStack(alignment: .leading, spacing: metrics.widgetRowSpacing) {
                        ForEach(VitalKind.allCases, id: \.self) { kind in
                            HStack(spacing: metrics.widgetRowGap) {
                                ValueLabel(kind.label)
                                    .frame(width: metrics.widgetRowLabelColumn, alignment: .leading)
                                HairlineTrace(
                                    values: kind.vital(snapshot).series7,
                                    showsNowDot: true,
                                    dimmed: freshness != .fresh
                                )
                                .privacySensitive()
                                Text(kind.text(snapshot))
                                    .somaFont(theme.typography.widgetRowValue)
                                    .foregroundStyle(ink.value(freshness))
                                    .lineLimit(1)
                                    .frame(width: metrics.widgetVitalsValueColumn, alignment: .trailing)
                                    .privacySensitive()
                            }
                            .frame(maxHeight: .infinity)
                        }
                        StaleFooter(freshness: freshness)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(VitalsText.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.vitals.url)
    }
}

/// The lock screen line above the clock: "52 bpm  64 ms  7:12", and the age
/// after it when stale and there is room.
public struct VitalsInline: View {
    private let snapshot: SomaWidgetSnapshot?
    private let now: Date

    public init(snapshot: SomaWidgetSnapshot?, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        Group {
            switch WidgetDisplay(snapshot: snapshot, now: now) {
            case .empty:
                Text("Open Soma")
            case .data(let freshness):
                if let snapshot {
                    let line = VitalsText.inline(snapshot)
                    Group {
                        if let age = StaleAge.text(freshness) {
                            ViewThatFits {
                                Text("\(line)  \(age)")
                                Text(line)
                            }
                        } else {
                            Text(line)
                        }
                    }
                    // Redacted on a locked lock screen.
                    .privacySensitive()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(VitalsText.accessibility(snapshot, freshness)))
                }
            }
        }
        .lineLimit(1)
        .widgetURL(WidgetLink.vitals.url)
    }
}

#Preview("Vitals small") {
    VitalsSmall(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 170, height: 170)
}

#Preview("Vitals medium") {
    VitalsMedium(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 170)
}

#Preview("Vitals large") {
    VitalsLarge(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 382)
}

#Preview("Vitals large, stale") {
    VitalsLarge(
        snapshot: .placeholder,
        now: SomaWidgetSnapshot.placeholder.generatedAt.addingTimeInterval(14 * 3600)
    )
    .padding(16)
    .frame(width: 364, height: 382)
}

#Preview("Vitals rectangular") {
    VitalsRectangular(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .frame(width: 172, height: 76)
}

#Preview("Vitals inline") {
    VitalsInline(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .frame(width: 240, height: 20)
}
