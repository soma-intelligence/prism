import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// How a score reads as text.
public enum ScoreText {
    /// The score rounded to a whole number, or "-" when there is none. A
    /// missing score never reads as zero. Clamped to 0...100 first, so a
    /// corrupt snapshot cannot overflow the conversion.
    public static func value(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "-" }
        return String(Int(min(max(v, 0), 100).rounded()))
    }

    /// What VoiceOver reads for one score: its word and number, and the age
    /// when the snapshot is stale, since the age is drawn inside an element
    /// that hides its children.
    public static func accessibility(_ kind: ScoreKind, _ v: Double?, _ freshness: Freshness) -> String {
        let reading = "\(label(kind)) \(value(v))"
        guard let age = StaleAge.text(freshness) else { return reading }
        return "\(reading), \(age)"
    }

    /// The one word that names a score.
    public static func label(_ kind: ScoreKind) -> String {
        switch kind {
        case .sleep: "Sleep"
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .stress: "Stress"
        }
    }

    /// The share of a ring a 0...100 score fills, or nil for an empty track.
    public static func fraction(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        return min(max(v / 100, 0), 1)
    }
}

public extension SomaWidgetSnapshot {
    /// The score a kind names.
    func score(_ kind: ScoreKind) -> Score {
        switch kind {
        case .sleep: sleep
        case .recovery: recovery
        case .strain: strain
        case .stress: stress
        }
    }
}

/// What a widget shows for a snapshot at a moment: the empty state, or the
/// data and how fresh it is.
enum WidgetDisplay: Equatable {
    case empty
    case data(Freshness)

    init(snapshot: SomaWidgetSnapshot?, now: Date) {
        guard let snapshot, snapshot.hasData else {
            self = .empty
            return
        }
        self = .data(snapshot.freshness(now: now))
    }
}

/// The three inks a widget draws with, for the rendering mode it is shown in.
///
/// Full colour reads the theme's inks as they are. Accented and vibrant
/// flatten colour to the light ink and keep only opacity, so there the
/// secondary ink and the track are the light ink at an opacity: a grey would
/// come out as bright as the primary ink and stale would stop reading as
/// stale.
struct WidgetInk {
    let primary: Color
    let secondary: Color
    let track: Color

    init(theme: SomaTheme, mode: WidgetRenderingMode) {
        let metrics = theme.metrics
        if mode == .fullColor {
            primary = theme.colors.inkPrimary.color
            secondary = theme.colors.inkSecondary.color
            track = theme.colors.inkPrimary.color.opacity(metrics.widgetTrackOpacity)
        } else {
            let light = SomaColorValue(theme.colors.inkPrimary.dark).color
            primary = light
            secondary = light.opacity(metrics.widgetSecondaryOpacity)
            track = light.opacity(metrics.widgetTrackOpacity)
        }
    }

    /// The ink a value is drawn in: secondary once the snapshot is stale.
    func value(_ freshness: Freshness) -> Color {
        freshness == .fresh ? primary : secondary
    }
}

/// The theme a subtree draws with in a flattened rendering mode: the light
/// inks, so a SomaUI component such as the mark stays visible.
struct WidgetModeTheme: ViewModifier {
    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        content.somaTheme(adjusted)
    }

    private var adjusted: SomaTheme {
        guard mode != .fullColor else { return theme }
        var copy = theme
        copy.colors.inkPrimary = SomaColorValue(theme.colors.inkPrimary.dark)
        copy.colors.inkSecondary = SomaColorValue(theme.colors.inkSecondary.dark)
        copy.colors.accent = SomaColorValue(theme.colors.accent.dark)
        return copy
    }
}

/// What a widget shows before the app has written anything: the Soma mark and
/// "Open Soma". Never a placeholder number.
public struct WidgetEmpty: View {
    private let compact: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    public init() {
        compact = false
    }

    /// The mark alone, for the lock screen ring, where two lines do not fit.
    init(compact: Bool) {
        self.compact = compact
    }

    public var body: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        VStack(spacing: theme.metrics.widgetLabelSpacing) {
            SomaMark(accessibilityLabel: "Soma")
            if !compact {
                Text("Open Soma")
                    .somaFont(theme.typography.widgetLabel)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
            }
        }
        .modifier(WidgetModeTheme())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open Soma"))
    }
}

/// How old a stale snapshot is, "6 h ago", or nothing while it is fresh.
public struct StaleAge: View {
    private let freshness: Freshness

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    public init(_ freshness: Freshness) {
        self.freshness = freshness
    }

    /// The age as it reads, or nil while fresh.
    public nonisolated static func text(_ freshness: Freshness) -> String? {
        switch freshness {
        case .fresh: nil
        case .stale(let hours): "\(hours) h ago"
        }
    }

    public var body: some View {
        if let text = Self.text(freshness) {
            Text(text)
                .somaFont(theme.typography.widgetLabel)
                .foregroundStyle(WidgetInk(theme: theme, mode: mode).secondary)
                .lineLimit(1)
        }
    }
}

#Preview("Empty") {
    WidgetEmpty()
        .frame(width: 170, height: 170)
}

#Preview("Stale age") {
    StaleAge(SomaWidgetSnapshot.placeholder.freshness(
        now: SomaWidgetSnapshot.placeholder.generatedAt.addingTimeInterval(14 * 3600)
    ))
}
