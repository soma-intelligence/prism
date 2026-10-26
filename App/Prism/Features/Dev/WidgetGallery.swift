//
//  WidgetGallery.swift
//  Prism
//
//  The playground's widget entry: every SomaWidgetUI view at its family size,
//  drawn from the one shared fixture at the fixture's own moment. iOS only,
//  like the widgets.
//

#if os(iOS)
import SwiftUI
import SomaUI
import SomaWidgetKit
import SomaWidgetUI

struct WidgetGallery: View {
    @Environment(\.somaTheme) private var theme

    private let snapshot = SomaWidgetSnapshot.placeholder
    private var now: Date { snapshot.generatedAt }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.widgetBlockSpacing) {
            title("Widgets: Scores")
            HStack(alignment: .top, spacing: theme.metrics.widgetColumnSpacing) {
                tile(.small) { ScoresSmall(snapshot: snapshot, kind: .recovery, now: now) }
                VStack(spacing: theme.metrics.widgetColumnSpacing) {
                    tile(.circular) { ScoresCircular(snapshot: snapshot, now: now) }
                    tile(.rectangular) { ScoresRectangular(snapshot: snapshot, now: now) }
                }
            }
            tile(.medium) { ScoresMedium(snapshot: snapshot, now: now) }

            title("Widgets: Vitals")
            tile(.small) { VitalsSmall(snapshot: snapshot, now: now) }
            tile(.medium) { VitalsMedium(snapshot: snapshot, now: now) }
            tile(.large) { VitalsLarge(snapshot: snapshot, now: now) }
            tile(.rectangular) { VitalsRectangular(snapshot: snapshot, now: now) }
            tile(.inline) { VitalsInline(snapshot: snapshot, now: now) }

            title("Widgets: Strain")
            tile(.medium) { StrainMedium(snapshot: snapshot, now: now) }
            tile(.large) { StrainLarge(snapshot: snapshot, now: now) }

            title("Widgets: Fuel")
            tile(.small) { FuelSmall(snapshot: snapshot, now: now) }
            tile(.medium) { FuelMedium(snapshot: snapshot, now: now) }

            title("Widgets: Log")
            HStack(alignment: .top, spacing: theme.metrics.widgetColumnSpacing) {
                tile(.small) { LogSmall(snapshot: snapshot, pending: [], now: now) }
                tile(.circular) { LogCircular(snapshot: snapshot, pending: [], now: now) }
            }
            tile(.medium) { LogMedium(snapshot: snapshot, pending: [], now: now, facesOnly: true) }
            tile(.large) { LogLarge(snapshot: snapshot, pending: [], now: now, facesOnly: true) }

            title("Widgets: empty")
            tile(.small) { ScoresSmall(snapshot: nil, kind: .recovery, now: now) }
        }
        .padding(.horizontal, 20)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .somaFont(theme.typography.eyebrow)
            .foregroundStyle(theme.colors.inkSecondary.color)
    }

    /// A family's tile: its size, the system's content margin on the home
    /// screen sizes, and the canvas behind it as the extension draws it.
    private func tile(_ family: GalleryFamily, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(family.isAccessory ? 0 : theme.metrics.widgetContentMargin)
            .frame(width: family.size.width, height: family.size.height)
            .background(theme.colors.canvas.color, in: .rect(cornerRadius: theme.metrics.cardCornerRadius))
    }
}

/// WidgetKit's family sizes on a 6.3 inch iPhone, in points. Development
/// only: the extension never sets a size, the system does.
private enum GalleryFamily {
    case small, medium, large, circular, rectangular, inline

    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .circular: CGSize(width: 72, height: 72)
        case .rectangular: CGSize(width: 172, height: 76)
        case .inline: CGSize(width: 240, height: 20)
        }
    }

    var isAccessory: Bool {
        switch self {
        case .circular, .rectangular, .inline: true
        default: false
        }
    }
}
#endif
