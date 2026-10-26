//
//  SomaMark.swift
//  SomaUI
//

import SwiftUI

/// The Soma mark: four rounded arms turning around an open centre, and a dot in
/// it.
///
/// Drawn from a path rather than shipped as an image, so it wears the ink of the
/// theme it sits in and stays sharp at any size on every platform the package
/// builds for. In dark mode that ink is the cream the website draws its own mark
/// in.
public struct SomaMark: View {
    /// Where the mark sits, which decides its size and its ink.
    public enum Role: Sendable {
        /// On its own: the size of a glyph, in the primary ink.
        case standard
        /// Beside a caption, signing what Soma wrote: caption sized, in the
        /// accent, which is the mark's own colour on the website.
        case caption
    }

    private let accessibilityLabel: LocalizedStringResource
    private let role: Role
    private let fixedSide: CGFloat?

    @Environment(\.somaTheme) private var theme

    public init(accessibilityLabel: LocalizedStringResource, role: Role = .standard) {
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.fixedSide = nil
    }

    /// The mark in the primary ink at `side` points, drawn at that size rather
    /// than scaled up from a glyph, so it stays sharp as a hero.
    public init(accessibilityLabel: LocalizedStringResource, side: CGFloat) {
        self.accessibilityLabel = accessibilityLabel
        self.role = .standard
        self.fixedSide = side
    }

    public var body: some View {
        SomaMarkShape()
            .fill(ink, style: FillStyle(eoFill: true))
            .frame(width: side, height: side)
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isImage)
    }

    private var side: CGFloat {
        if let fixedSide { return fixedSide }
        return switch role {
        case .standard: theme.metrics.markSize
        case .caption: theme.metrics.markCaptionSize
        }
    }

    private var ink: Color {
        switch role {
        case .standard: theme.colors.inkPrimary.color
        case .caption: theme.colors.accent.color
        }
    }
}

/// The mark's outline, fitted to the largest square the rect holds and centred
/// in it, so a frame of the wrong proportions never stretches the arms.
struct SomaMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / Self.box
        let placement = CGAffineTransform(
            translationX: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        .scaledBy(x: scale, y: scale)

        return (Self.outline ?? Path()).applying(placement)
    }

    /// Edge of the square the trace is drawn on.
    static let box: CGFloat = 100

    /// Parsed once, the first time a mark is drawn.
    static let outline = path(from: trace)

    /// The website's `MARK_PATH` (`lib/brand.ts` in the landing page), character
    /// for character: the brand file traced into one path on a 100 by 100 box.
    ///
    /// Kept as the string rather than rewritten as Swift calls, so the two
    /// surfaces can be compared by eye and a new trace is one paste on each side.
    static let trace = "M43.17 99.96C43.15 99.94 42.72 99.87 42.21 99.81C37.33 99.19 34.8 96.69 34.14 91.86C34.1 91.56 34.03 87.57 34 82.98C33.93 74.45 33.91 73.81 33.6 72.12C33.3 70.47 32.85 69.19 32.33 68.5C32.02 68.08 31.49 67.52 31.41 67.52C31.37 67.52 31.1 67.4 30.8 67.26C29.81 66.76 28.54 66.44 26.78 66.24C25.11 66.04 24.62 66.03 16.71 66.01C8.62 65.99 8.58 65.99 6.8 65.62C3.79 65 1.67 63.11 0.68 60.16C0.1 58.45 0.08 58.11 0.08 50.23C0.08 43.22 0.09 42.94 0.35 41.16C0.8 38.09 2.99 35.51 5.84 34.66C7.8 34.08 7.7 34.09 16.32 34.06C25.29 34.04 26.46 33.98 28.81 33.45C32.27 32.67 33.18 31.36 33.82 26.25C33.91 25.45 33.95 23.72 33.99 16.98C34.05 8.49 34.06 8.3 34.38 6.81C35.16 3.23 37.62 0.94 41.32 0.35C43.15 0.06 53.71 -0.07 56.7 0.16C61.1 0.5 63.42 1.81 64.86 4.75C65.9 6.89 66.05 8.68 65.98 17.81C65.94 23.36 65.98 25.24 66.16 26.68C66.61 30.23 67.43 31.97 69.02 32.72C69.71 33.04 71.34 33.57 71.68 33.57C71.79 33.57 72.1 33.62 72.35 33.68C73.63 33.98 75.61 34.04 83.46 34.06C90.31 34.08 91.14 34.09 92.06 34.22C96.89 34.9 99.33 37.62 99.84 42.91C99.99 44.46 99.97 56.14 99.82 57.52C99.42 61.18 97.9 63.6 95.19 64.9C94.07 65.44 93.31 65.64 91.36 65.9C90.25 66.05 77.65 66.05 76.4 65.9C72.03 65.39 69.61 63.57 68.51 59.97C68.03 58.39 68.01 58.17 67.95 49.07C67.92 44.17 67.86 40.58 67.81 40.19C67.76 39.82 67.69 39.21 67.65 38.82C67.53 37.75 66.97 35.59 66.78 35.47C66.74 35.45 66.71 35.37 66.71 35.3C66.71 35.09 66.03 34.14 65.68 33.86C64.63 33 62.54 32.42 59.58 32.16C58.18 32.04 41.94 32.04 40.38 32.16C38.73 32.29 37.34 32.52 36.37 32.84C33.84 33.65 33.13 34.55 32.44 37.85C32.35 38.26 32.24 39.25 32.13 40.45C32.02 41.6 32.02 58.13 32.12 59.46C32.4 63.08 33.14 65.36 34.28 66.19C35.45 67.03 37.16 67.53 40.03 67.84C40.51 67.9 43.97 67.95 49.07 67.99C56.93 68.04 57.37 68.05 58.29 68.21C61.26 68.71 63.07 69.74 64.34 71.67C65.38 73.25 65.78 74.87 65.93 78.02C66 79.76 65.98 90.26 65.9 90.89C65.87 91.08 65.82 91.57 65.77 91.98C65.52 94.24 64.71 96.02 63.29 97.43C61.72 98.97 59.91 99.65 56.54 99.92C55.58 100 43.25 100.03 43.17 99.96ZM49.21 52.77C47.32 52.35 46.36 50.56 47.03 48.7C47.95 46.13 51.89 46.27 52.65 48.91C53.08 50.38 52.46 51.96 51.25 52.49C50.4 52.87 49.96 52.93 49.21 52.77Z"

    /// Reads the three commands the trace is written in: `M`, `C` and `Z`, all
    /// absolute.
    ///
    /// Anything else returns `nil` rather than half a mark, so a new trace that
    /// reaches for another command fails a test instead of drawing wrong.
    static func path(from data: String) -> Path? {
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

        func point() -> CGPoint? {
            guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { return nil }
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        while let command = scanner.scanCharacter() {
            switch command {
            case "M":
                guard let start = point() else { return nil }
                path.move(to: start)
            case "C":
                // One C may carry several segments in a row, three points each.
                while let control1 = point() {
                    guard let control2 = point(), let end = point() else { return nil }
                    path.addCurve(to: end, control1: control1, control2: control2)
                }
            case "Z":
                path.closeSubpath()
            default:
                return nil
            }
        }
        return path
    }
}

#Preview("Mark") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            SomaMark(accessibilityLabel: "Soma")
            SomaMark(accessibilityLabel: "Soma", role: .caption)
        }
    }
}
