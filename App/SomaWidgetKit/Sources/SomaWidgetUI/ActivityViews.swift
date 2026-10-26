import SwiftUI
import SomaUI
import SomaWidgetKit

// The pieces of a Soma Live Activity. The extension assembles them into the
// lock screen banner and the Dynamic Island's regions; they draw from the
// content alone, and the clock runs on its own through the system's timer
// text, so an activity stays live between updates.

public extension SomaActivityKind {
    /// The aspect whose hue the activity wears.
    var aspect: SomaAspect {
        switch self {
        case .windDown, .nap: .sleep
        case .cardioTest: .activity
        case .meeting: .mind
        }
    }
}

/// The activity's glyph in its hue.
public struct SomaActivityGlyph: View {
    private let kind: SomaActivityKind
    private let alert: Bool

    @Environment(\.somaTheme) private var theme

    public init(_ kind: SomaActivityKind, alert: Bool = false) {
        self.kind = kind
        self.alert = alert
    }

    public var body: some View {
        Image(systemName: alert ? "exclamationmark.triangle.fill" : kind.symbol)
            .foregroundStyle(alert ? theme.colors.statusAlert.color : theme.aspects[kind.aspect].identity.color)
            .accessibilityHidden(true)
    }
}

/// The running clock: down to the end, or up from the start.
public struct SomaActivityClock: View {
    private let content: SomaActivityContent
    private let role: KeyPath<SomaTypography, SomaFontSpec>

    @Environment(\.somaTheme) private var theme

    /// - Parameter role: the type role the digits take, `metric` on the lock
    ///   screen, smaller in the island's compact slot.
    public init(_ content: SomaActivityContent, role: KeyPath<SomaTypography, SomaFontSpec> = \.metric) {
        self.content = content
        self.role = role
    }

    public var body: some View {
        Group {
            if let stopped = content.stoppedAt {
                Text(verbatim: SomaActivityContent.clock(stopped))
            } else if let end = content.end, end > content.start {
                Text(timerInterval: content.start...end, countsDown: true)
            } else {
                Text(timerInterval: content.start...Date.distantFuture, countsDown: false)
            }
        }
        .somaFont(theme.typography[keyPath: role])
        .foregroundStyle(theme.colors.inkPrimary.color)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
    }
}

/// A countdown's progress as a thin bar in the activity's hue, moving on its
/// own between updates.
public struct SomaActivityProgress: View {
    private let kind: SomaActivityKind
    private let content: SomaActivityContent

    @Environment(\.somaTheme) private var theme

    public init(_ kind: SomaActivityKind, _ content: SomaActivityContent) {
        self.kind = kind
        self.content = content
    }

    public var body: some View {
        if content.stoppedAt == nil, let end = content.end, end > content.start {
            ProgressView(timerInterval: content.start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(theme.aspects[kind.aspect].identity.color)
            .accessibilityHidden(true)
        }
    }
}

/// The title and its line.
public struct SomaActivityTitle: View {
    private let content: SomaActivityContent

    @Environment(\.somaTheme) private var theme

    public init(_ content: SomaActivityContent) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.widgetRowSpacing) {
            Text(content.title)
                .somaFont(theme.typography.cardTitle)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .lineLimit(1)
            if let detail = content.detail {
                Text(detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .lineLimit(1)
            }
        }
    }
}

/// The reading beside the clock, with its label and a second reading.
public struct SomaActivityReading: View {
    private let content: SomaActivityContent

    @Environment(\.somaTheme) private var theme

    public init(_ content: SomaActivityContent) {
        self.content = content
    }

    public var body: some View {
        if content.value != nil || content.secondary != nil {
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.widgetRowGap) {
                if let label = content.valueLabel {
                    Text(label)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                if let value = content.value {
                    Text(value)
                        .somaFont(theme.typography.widgetRowValue)
                        .foregroundStyle(content.alert ? theme.colors.statusAlert.color : theme.colors.inkPrimary.color)
                }
                Spacer(minLength: 0)
                if let secondary = content.secondary {
                    Text(secondary)
                        .somaFont(theme.typography.widgetRowValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            .lineLimit(1)
        }
    }
}

/// The lock screen banner: glyph, title and line on the leading side, the
/// clock large on the trailing side, then the reading and the countdown's
/// bar.
public struct SomaActivityBanner: View {
    private let kind: SomaActivityKind
    private let content: SomaActivityContent

    @Environment(\.somaTheme) private var theme

    public init(kind: SomaActivityKind, content: SomaActivityContent) {
        self.kind = kind
        self.content = content
    }

    public var body: some View {
        let metrics = theme.metrics
        VStack(alignment: .leading, spacing: metrics.widgetRowGap) {
            HStack(alignment: .center, spacing: metrics.widgetRowGap) {
                SomaActivityGlyph(kind, alert: content.alert)
                    .somaFont(theme.typography.headline)
                SomaActivityTitle(content)
                Spacer(minLength: metrics.widgetRowGap)
                SomaActivityClock(content)
                    .frame(maxWidth: metrics.widgetLargeLabelColumn, alignment: .trailing)
            }
            SomaActivityReading(content)
            SomaActivityProgress(kind, content)
        }
        .padding(metrics.widgetContentMargin)
        .accessibilityElement(children: .combine)
    }
}
