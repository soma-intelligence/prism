import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// One score in a ring with its number in the middle: the piece the small,
/// medium and lock screen Scores widgets are built from.
struct ScoreRing: View {
    let value: Double?
    let lineWidth: CGFloat
    let number: SomaFontSpec
    let freshness: Freshness
    /// The score's word under the number, inside the ring; nil leaves it out.
    let label: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        let metrics = theme.metrics
        InkRing(fraction: ScoreText.fraction(value), lineWidth: lineWidth, dimmed: freshness != .fresh)
            .overlay {
                VStack(spacing: 0) {
                    Text(ScoreText.value(value))
                        .somaFont(number)
                        .foregroundStyle(ink.value(freshness))
                    if let label {
                        Text(label)
                            .somaFont(theme.typography.widgetLabel)
                            .foregroundStyle(ink.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(lineWidth + metrics.widgetRingTextInset)
            }
    }
}

/// The age of a stale snapshot in the bottom trailing corner, in a row of its
/// own so it never sits on a ring.
struct StaleFooter: View {
    let freshness: Freshness

    var body: some View {
        if freshness != .fresh {
            HStack {
                Spacer(minLength: 0)
                StaleAge(freshness)
            }
        }
    }
}

/// The small Scores widget: one score, chosen in the widget's settings, as one
/// ring with its number centred.
public struct ScoresSmall: View {
    private let snapshot: SomaWidgetSnapshot?
    private let kind: ScoreKind
    private let now: Date

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, kind: ScoreKind, now: Date) {
        self.snapshot = snapshot
        self.kind = kind
        self.now = now
    }

    public var body: some View {
        Group {
            switch WidgetDisplay(snapshot: snapshot, now: now) {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                let value = snapshot?.score(kind).value
                VStack(spacing: theme.metrics.widgetLabelSpacing) {
                    ScoreRing(
                        value: value,
                        lineWidth: theme.metrics.widgetRingStrokeSmall,
                        number: theme.typography.widgetHero,
                        freshness: freshness,
                        label: ScoreText.label(kind)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    StaleFooter(freshness: freshness)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(ScoreText.accessibility(kind, value, freshness)))
            }
        }
        .widgetURL(WidgetLink.score(kind).url)
    }
}

/// The medium Scores widget: sleep, recovery and strain as three rings in a
/// row, each word under its ring.
public struct ScoresMedium: View {
    static let kinds: [ScoreKind] = [.sleep, .recovery, .strain]

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
                let metrics = theme.metrics
                let ink = WidgetInk(theme: theme, mode: mode)
                VStack(spacing: metrics.widgetLabelSpacing) {
                    HStack(spacing: metrics.widgetColumnSpacing) {
                        ForEach(Self.kinds, id: \.self) { kind in
                            let value = snapshot?.score(kind).value
                            VStack(spacing: metrics.widgetLabelSpacing) {
                                ScoreRing(
                                    value: value,
                                    lineWidth: metrics.widgetRingStroke,
                                    number: theme.typography.widgetValue,
                                    freshness: freshness,
                                    label: nil
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text(ScoreText.label(kind))
                                    .somaFont(theme.typography.widgetLabel)
                                    .foregroundStyle(ink.secondary)
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(ScoreText.accessibility(kind, value, .fresh)))
                        }
                    }
                    StaleFooter(freshness: freshness)
                }
            }
        }
        .widgetURL(WidgetLink.score(.recovery).url)
    }
}

/// The lock screen ring: recovery, its number inside.
public struct ScoresCircular: View {
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
                WidgetEmpty(compact: true)
            case .data(let freshness):
                let value = snapshot?.recovery.value
                ScoreRing(
                    value: value,
                    lineWidth: theme.metrics.widgetRingStroke,
                    number: theme.typography.widgetGlance,
                    freshness: freshness,
                    label: nil
                )
                // Redacted on a locked lock screen.
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(ScoreText.accessibility(.recovery, value, freshness)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetLink.score(.recovery).url)
    }
}

/// The lock screen rectangle: sleep, recovery and strain as three thin bars,
/// each with its word before and its number after.
public struct ScoresRectangular: View {
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
                let metrics = theme.metrics
                let ink = WidgetInk(theme: theme, mode: mode)
                VStack(alignment: .leading, spacing: metrics.widgetRowSpacing) {
                    ForEach(ScoresMedium.kinds, id: \.self) { kind in
                        let value = snapshot?.score(kind).value
                        HStack(spacing: metrics.widgetRowGap) {
                            Text(ScoreText.label(kind))
                                .somaFont(theme.typography.widgetLabel)
                                .foregroundStyle(ink.secondary)
                                .frame(width: metrics.widgetRowLabelColumn, alignment: .leading)
                            ThinBar(fraction: ScoreText.fraction(value), dimmed: freshness != .fresh)
                                .privacySensitive()
                            Text(ScoreText.value(value))
                                .somaFont(theme.typography.widgetRowValue)
                                .foregroundStyle(ink.value(freshness))
                                .frame(width: metrics.widgetRowValueColumn, alignment: .trailing)
                                .privacySensitive()
                        }
                        .lineLimit(1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(ScoreText.accessibility(kind, value, .fresh)))
                    }
                    StaleFooter(freshness: freshness)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetURL(WidgetLink.score(.recovery).url)
    }
}

#Preview("Scores small, stale") {
    ScoresSmall(
        snapshot: .placeholder,
        kind: .recovery,
        now: SomaWidgetSnapshot.placeholder.generatedAt.addingTimeInterval(14 * 3600)
    )
    .padding(16)
    .frame(width: 170, height: 170)
}

#Preview("Scores small") {
    ScoresSmall(snapshot: .placeholder, kind: .recovery, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 170, height: 170)
}

#Preview("Scores medium") {
    ScoresMedium(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 170)
}

#Preview("Scores circular") {
    ScoresCircular(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .frame(width: 72, height: 72)
}

#Preview("Scores rectangular") {
    ScoresRectangular(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .frame(width: 172, height: 76)
}
