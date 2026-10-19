import Foundation
import SwiftUI
import Testing
import WidgetKit
import ImageIO
import UniformTypeIdentifiers
import SomaUI
import SomaWidgetKit
@testable import SomaWidgetUI

/// Draws a widget view at its family size in every look it can be shown in,
/// light and dark by full colour, accented and vibrant, and writes each one as
/// a PNG for a person to look at.
///
/// The folder is `$SOMA_WIDGET_REVIEW_DIR`, or `.build/widget-review` inside
/// the package. Nothing here is compared against a reference image: the files
/// are for eyes, the test only checks that every one was drawn.
@MainActor
enum RenderReview {
    static let scale: CGFloat = 3

    static let modes: [(name: String, mode: WidgetRenderingMode)] = [
        ("fullColor", .fullColor),
        ("accented", .accented),
        ("vibrant", .vibrant),
    ]

    static let schemes: [(name: String, scheme: ColorScheme)] = [
        ("light", .light),
        ("dark", .dark),
    ]

    static var folder: URL {
        if let path = ProcessInfo.processInfo.environment["SOMA_WIDGET_REVIEW_DIR"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        // Tests/SomaWidgetUITests/RenderReview.swift, three levels under the package.
        return URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/widget-review", directoryHint: .isDirectory)
    }

    /// The phone's scale, so a review on the Mac reads at the size a widget
    /// does on the home screen rather than at desk density.
    static let theme = SomaTheme(colors: .standard, typography: .touch, metrics: .touch)

    /// Writes `name-<scheme>-<mode>.png` for every scheme and mode.
    @discardableResult
    static func render<V: View>(
        name: String,
        size: CGSize,
        margins: Bool = true,
        @ViewBuilder content: () -> V
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        for scheme in schemes {
            for mode in modes {
                let view = ReviewFrame(size: size, margins: margins, mode: mode.mode) { content() }
                    .environment(\.widgetRenderingMode, mode.mode)
                    .environment(\.colorScheme, scheme.scheme)
                    .somaTheme(theme)
                let image = drawn(view, scheme: scheme.scheme)
                #expect(image != nil, "\(name) \(scheme.name) \(mode.name) did not render")
                guard let image else { continue }
                let url = folder.appending(path: "\(name)-\(scheme.name)-\(mode.name).png")
                try write(image, to: url)
                written.append(url)
            }
        }
        return written
    }

    private static func drawn<V: View>(_ view: V, scheme: ColorScheme) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        var image: CGImage?
#if canImport(AppKit)
        // The theme's colours resolve through the platform colour, which on the
        // Mac reads the drawing appearance rather than the SwiftUI environment.
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        } else {
            image = renderer.cgImage
        }
#else
        image = renderer.cgImage
#endif
        return image
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw ReviewError.cannotWrite(url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ReviewError.cannotWrite(url) }
    }

    enum ReviewError: Error { case cannotWrite(URL) }
}

/// The widget's tile: its family size, the system's content margin, and the
/// canvas the extension sets as its container background.
///
/// Accented and vibrant are drawn by the system over a tinted or blurred
/// ground and flatten the content to light ink, so the review shows them on the
/// dark canvas, where that light ink reads as it will on the device.
private struct ReviewFrame<Content: View>: View {
    let size: CGSize
    let margins: Bool
    let mode: WidgetRenderingMode
    @ViewBuilder let content: Content
    @Environment(\.somaTheme) private var theme

    var body: some View {
        content
            .padding(margins ? theme.metrics.widgetContentMargin : 0)
            .frame(width: size.width, height: size.height)
            .background(ground)
    }

    private var ground: Color {
        mode == .fullColor ? theme.colors.canvas.color : SomaColorValue(theme.colors.canvas.dark).color
    }
}

/// Family sizes in points, from the plan.
enum Family {
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
    static let circular = CGSize(width: 72, height: 72)
    static let rectangular = CGSize(width: 172, height: 76)
    static let inline = CGSize(width: 240, height: 20)
}

private extension SomaWidgetSnapshot {
    /// A copy edit for the edge cases, so every render starts from the one
    /// shared fixture.
    mutating func setScore(_ kind: ScoreKind, _ value: Double?) {
        switch kind {
        case .sleep: sleep.value = value
        case .recovery: recovery.value = value
        case .strain: strain.value = value
        case .stress: stress.value = value
        }
    }
}

@Suite(.serialized)
@MainActor
struct ScoresRenderTests {
    static let snapshot = SomaWidgetSnapshot.placeholder
    static let fresh = snapshot.generatedAt
    static let stale = snapshot.generatedAt.addingTimeInterval(14 * 3600)

    @Test func renderScores() throws {
        for kind in ScoreKind.allCases {
            try RenderReview.render(name: "scores-small-\(kind.rawValue)", size: Family.small) {
                ScoresSmall(snapshot: Self.snapshot, kind: kind, now: Self.fresh)
            }
        }
        try RenderReview.render(name: "scores-small", size: Family.small) {
            ScoresSmall(snapshot: Self.snapshot, kind: .recovery, now: Self.fresh)
        }
        try RenderReview.render(name: "scores-medium", size: Family.medium) {
            ScoresMedium(snapshot: Self.snapshot, now: Self.fresh)
        }
        try RenderReview.render(name: "scores-circular", size: Family.circular, margins: false) {
            ScoresCircular(snapshot: Self.snapshot, now: Self.fresh)
        }
        try RenderReview.render(name: "scores-rectangular", size: Family.rectangular, margins: false) {
            ScoresRectangular(snapshot: Self.snapshot, now: Self.fresh)
        }
    }

    @Test func renderScoresWithoutSnapshot() throws {
        try RenderReview.render(name: "scores-small-nil", size: Family.small) {
            ScoresSmall(snapshot: nil, kind: .recovery, now: Self.fresh)
        }
        try RenderReview.render(name: "scores-medium-nil", size: Family.medium) {
            ScoresMedium(snapshot: nil, now: Self.fresh)
        }
        try RenderReview.render(name: "scores-circular-nil", size: Family.circular, margins: false) {
            ScoresCircular(snapshot: nil, now: Self.fresh)
        }
        try RenderReview.render(name: "scores-rectangular-nil", size: Family.rectangular, margins: false) {
            ScoresRectangular(snapshot: nil, now: Self.fresh)
        }
    }

    @Test func renderScoresStale() throws {
        try RenderReview.render(name: "scores-small-stale", size: Family.small) {
            ScoresSmall(snapshot: Self.snapshot, kind: .recovery, now: Self.stale)
        }
        try RenderReview.render(name: "scores-medium-stale", size: Family.medium) {
            ScoresMedium(snapshot: Self.snapshot, now: Self.stale)
        }
        try RenderReview.render(name: "scores-rectangular-stale", size: Family.rectangular, margins: false) {
            ScoresRectangular(snapshot: Self.snapshot, now: Self.stale)
        }
    }

    @Test func renderScoresMissingValues() throws {
        // Fewer than seven nights: the scores are nil, the rings show an empty
        // track and a dash.
        var missing = Self.snapshot
        for kind in ScoreKind.allCases { missing.setScore(kind, nil) }
        try RenderReview.render(name: "scores-medium-missing", size: Family.medium) {
            ScoresMedium(snapshot: missing, now: Self.fresh)
        }
    }

    @Test func renderShapes() throws {
        try RenderReview.render(name: "shapes-trace", size: Family.rectangular, margins: false) {
            HairlineTrace(values: Self.snapshot.hrv.series7)
        }
        try RenderReview.render(name: "shapes-bar", size: Family.inline, margins: false) {
            ThinBar(fraction: ScoreText.fraction(Self.snapshot.recovery.value) ?? 0)
        }
    }
}

@Suite(.serialized)
@MainActor
struct VitalsStrainFuelRenderTests {
    static let snapshot = SomaWidgetSnapshot.placeholder
    static let fresh = snapshot.generatedAt
    static let stale = snapshot.generatedAt.addingTimeInterval(14 * 3600)

    /// Every view at its family size for one snapshot and moment.
    private func renderAll(suffix: String, snapshot: SomaWidgetSnapshot?, now: Date) throws {
        try RenderReview.render(name: "vitals-small\(suffix)", size: Family.small) {
            VitalsSmall(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "vitals-medium\(suffix)", size: Family.medium) {
            VitalsMedium(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "vitals-large\(suffix)", size: Family.large) {
            VitalsLarge(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "vitals-rectangular\(suffix)", size: Family.rectangular, margins: false) {
            VitalsRectangular(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "vitals-inline\(suffix)", size: Family.inline, margins: false) {
            VitalsInline(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "strain-medium\(suffix)", size: Family.medium) {
            StrainMedium(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "strain-large\(suffix)", size: Family.large) {
            StrainLarge(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "fuel-small\(suffix)", size: Family.small) {
            FuelSmall(snapshot: snapshot, now: now)
        }
        try RenderReview.render(name: "fuel-medium\(suffix)", size: Family.medium) {
            FuelMedium(snapshot: snapshot, now: now)
        }
    }

    @Test func renderVitalsStrainFuel() throws {
        try renderAll(suffix: "", snapshot: Self.snapshot, now: Self.fresh)
    }

    @Test func renderVitalsStrainFuelWithoutSnapshot() throws {
        try renderAll(suffix: "-nil", snapshot: nil, now: Self.fresh)
    }

    @Test func renderVitalsStrainFuelStale() throws {
        try renderAll(suffix: "-stale", snapshot: Self.snapshot, now: Self.stale)
    }

    @Test func renderVitalsStrainFuelMissingValues() throws {
        // A copy of the fixture with one value of each widget gone and no
        // hypnogram: every gap reads as a dash, never as zero.
        var missing = Self.snapshot
        missing.hrv = SomaWidgetSnapshot.Vital()
        missing.hypnogram = nil
        missing.energyNow = nil
        missing.energyCurve = []
        missing.stress.value = nil
        missing.eatenKcal = nil
        try renderAll(suffix: "-missing", snapshot: missing, now: Self.fresh)
    }

    @Test func renderStrainLaterInTheTimeline() throws {
        // Two hours on, same snapshot: the now dot has moved past the curve.
        let later = Self.fresh.addingTimeInterval(2 * 3600)
        try RenderReview.render(name: "strain-medium-later", size: Family.medium) {
            StrainMedium(snapshot: Self.snapshot, now: later)
        }
        try RenderReview.render(name: "strain-large-later", size: Family.large) {
            StrainLarge(snapshot: Self.snapshot, now: later)
        }
    }
}

@Suite(.serialized)
@MainActor
struct LogRenderTests {
    static let snapshot = SomaWidgetSnapshot.placeholder
    static let fresh = snapshot.generatedAt
    static let stale = snapshot.generatedAt.addingTimeInterval(14 * 3600)

    /// Every Log view at its family size. `ImageRenderer` cannot draw a
    /// `Link`, so the mood and meal buttons are drawn as their faces alone.
    private func renderAll(suffix: String, snapshot: SomaWidgetSnapshot?, pending: [LogItem], now: Date) throws {
        try RenderReview.render(name: "log-small\(suffix)", size: Family.small) {
            LogSmall(snapshot: snapshot, pending: pending, now: now)
        }
        try RenderReview.render(name: "log-medium\(suffix)", size: Family.medium) {
            LogMedium(snapshot: snapshot, pending: pending, now: now, facesOnly: true)
        }
        try RenderReview.render(name: "log-large\(suffix)", size: Family.large) {
            LogLarge(snapshot: snapshot, pending: pending, now: now, facesOnly: true)
        }
        try RenderReview.render(name: "log-circular\(suffix)", size: Family.circular, margins: false) {
            LogCircular(snapshot: snapshot, pending: pending, now: now)
        }
    }

    @Test func renderLog() throws {
        try renderAll(suffix: "", snapshot: Self.snapshot, pending: [], now: Self.fresh)
    }

    @Test func renderLogWithoutSnapshot() throws {
        try renderAll(suffix: "-nil", snapshot: nil, pending: [], now: Self.fresh)
    }

    @Test func renderLogStale() throws {
        try renderAll(suffix: "-stale", snapshot: Self.snapshot, pending: [], now: Self.stale)
    }

    @Test func renderLogWithPending() throws {
        // Two taps not yet drained: one water, one coffee.
        let pending = [
            LogItem(kind: .water, ml: LogInbox.defaultMl, date: Self.fresh),
            LogItem(kind: .coffee, ml: LogInbox.defaultMl, date: Self.fresh),
        ]
        try renderAll(suffix: "-pending", snapshot: Self.snapshot, pending: pending, now: Self.fresh)
    }

    @Test func renderLogBeforeFirstScores() throws {
        // No Health data yet: the buttons show, with the day's real tally.
        var blank = Self.snapshot
        blank.hasData = false
        try renderAll(suffix: "-nodata", snapshot: blank, pending: [], now: Self.fresh)
    }

    @Test func renderLogEmptyDay() throws {
        // Nothing logged yet today: a real zero, not a dash.
        var empty = Self.snapshot
        empty.tally = .empty(day: Self.snapshot.tally.day)
        try renderAll(suffix: "-zero", snapshot: empty, pending: [], now: Self.fresh)
    }
}
