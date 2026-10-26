//
//  SomaGlyph.swift
//  SomaUI
//

import SwiftUI

/// One of Soma's line glyphs: the eight aspects and the three scores.
///
/// Each aspect glyph is the flat form of its clay object (the moon, the heart,
/// the shoe, the lotus, the dumbbell, the leaf, the bolt, the sun behind its
/// cloud), the way Airbnb draws a category once in 3D and once as a line. One
/// grid, one line weight and one solid detail each: where the eye should land.
///
/// The glyph draws in the foreground style it is given, so it sits in ink in
/// chrome. `tinted` paints an aspect in its category ink, for a list of
/// readings; a score has no category and stays in ink.
public struct SomaGlyph: View {
    /// What the glyph stands for.
    public enum Kind: String, CaseIterable, Sendable {
        case body, mind, sleep, heart, gut, activity, energy, environment
        case recovery, strain, stress

        /// The glyph an aspect wears.
        public init(_ aspect: SomaAspect) {
            switch aspect {
            case .body: self = .body
            case .mind: self = .mind
            case .sleep: self = .sleep
            case .heart: self = .heart
            case .gut: self = .gut
            case .activity: self = .activity
            }
        }

        /// The category ink, for the aspects; nil for a score.
        public var ink: SomaCategoryInk? {
            switch self {
            case .sleep: .sleep
            case .heart: .heart
            case .activity: .activity
            case .mind: .mind
            case .body: .body
            case .gut: .gut
            case .energy: .energy
            case .environment: .environment
            case .recovery, .strain, .stress: nil
            }
        }

        /// What VoiceOver says: the reading, never the drawing.
        public var label: LocalizedStringResource {
            switch self {
            case .body: "Body"
            case .mind: "Mind"
            case .sleep: "Sleep"
            case .heart: "Heart"
            case .gut: "Gut"
            case .activity: "Activity"
            case .energy: "Energy"
            case .environment: "Environment"
            case .recovery: "Recovery"
            case .strain: "Strain"
            case .stress: "Stress"
            }
        }
    }

    /// How large the glyph is set.
    public enum Size: Sendable {
        /// Beside a label, at the height of its line.
        case inline
        /// Leading a row of readings.
        case row
        /// Over a hero value, or in a score row.
        case lead
    }

    private let kind: Kind
    private let size: Size
    private let tinted: Bool

    @Environment(\.somaTheme) private var theme

    public init(_ kind: Kind, size: Size = .inline, tinted: Bool = false) {
        self.kind = kind
        self.size = size
        self.tinted = tinted
    }

    public init(aspect: SomaAspect, size: Size = .inline, tinted: Bool = false) {
        self.init(Kind(aspect), size: size, tinted: tinted)
    }

    public var body: some View {
        let metrics = theme.metrics
        let side = switch size {
        case .inline: metrics.glyphInline
        case .row: metrics.glyphRow
        case .lead: metrics.glyphLead
        }
        let outline = kind.outline
        let grid = metrics.glyphGrid
        let line = metrics.glyphStroke

        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / grid
            context.scaleBy(x: scale, y: scale)
            context.stroke(
                outline.stroke,
                with: .foreground,
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
            context.fill(outline.fill, with: .foreground)
        }
        .frame(width: side, height: side)
        .foregroundStyle(tint)
        .accessibilityElement()
        .accessibilityLabel(Text(kind.label))
    }

    private var tint: AnyShapeStyle {
        if tinted, let ink = kind.ink {
            AnyShapeStyle(ink.color)
        } else {
            AnyShapeStyle(.foreground)
        }
    }
}

#Preview("Glyphs") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                ForEach(SomaGlyph.Kind.allCases, id: \.self) { kind in
                    SomaGlyph(kind, size: .row, tinted: true)
                }
            }
            HStack(spacing: 16) {
                ForEach(SomaGlyph.Kind.allCases, id: \.self) { kind in
                    SomaGlyph(kind, size: .lead)
                }
            }
        }
        .padding()
    }
}
