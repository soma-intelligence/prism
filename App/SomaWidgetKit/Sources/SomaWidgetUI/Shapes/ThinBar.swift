import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// A thin horizontal bar: a faint track the full width and the value in ink
/// from the leading edge. The value stroke alone is accentable.
public struct ThinBar: View {
    private let fraction: Double?
    private let dimmed: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    public init(fraction: Double) {
        self.init(fraction: fraction, dimmed: false)
    }

    /// A nil fraction draws the track alone; `dimmed` draws the value in the
    /// secondary ink, for a stale snapshot.
    init(fraction: Double?, dimmed: Bool) {
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.dimmed = dimmed
    }

    public var body: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        let height = theme.metrics.widgetBarHeight
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.track)
                if let fraction, fraction > 0 {
                    Capsule()
                        .fill(dimmed ? ink.secondary : ink.primary)
                        .frame(width: max(height, proxy.size.width * fraction))
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("Thin bar") {
    VStack {
        ThinBar(fraction: ScoreText.fraction(SomaWidgetSnapshot.placeholder.strain.value) ?? 0)
        // Edge case: an empty bar.
        ThinBar(fraction: 0)
    }
    .frame(width: 160)
    .padding()
}
