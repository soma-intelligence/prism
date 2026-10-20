//
//  SomaMoodFaces.swift
//  SomaUI
//

import SwiftUI

/// How a moment feels, on five faces from rough to great, each a line face
/// drawn on the glyph grid in a calm tone: clay at rough, sand at okay, sage
/// at great. The same five words the evening question uses.
public enum SomaMood: Int, CaseIterable, Sendable, Identifiable {
    case rough, low, okay, good, great

    public var id: Int { rawValue }

    public var title: LocalizedStringResource {
        switch self {
        case .rough: "Rough"
        case .low: "Low"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    /// The face's tone, off the calm ramp.
    public var tone: SomaColorValue {
        SomaEnergyRamp.calm.value(at: Double(rawValue) / Double(Self.allCases.count - 1))
    }
}

/// One mood as a face: a round outline, two eyes, a mouth that turns down at
/// rough and up at great. Drawn in the mood's tone; filled softly when it is
/// the one chosen.
public struct SomaMoodFace: View {
    private let mood: SomaMood
    private let isFilled: Bool
    private let side: CGFloat?

    @Environment(\.somaTheme) private var theme

    /// - Parameter side: the face's size; nil takes the scale's own.
    public init(_ mood: SomaMood, isFilled: Bool = false, side: CGFloat? = nil) {
        self.mood = mood
        self.isFilled = isFilled
        self.side = side
    }

    public var body: some View {
        let metrics = theme.metrics
        let side = side ?? metrics.moodFaceSide
        let tone = mood.tone.color
        let stroke = side * metrics.aspectGlyphStroke / metrics.aspectGlyphGrid * metrics.moodFaceStrokeScale

        ZStack {
            Circle()
                .fill(tone.opacity(isFilled ? metrics.moodFaceFill : 0))
            SomaMoodFaceShape(mood: mood)
                .stroke(tone, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The outline of a mood face on the 24 unit grid.
public struct SomaMoodFaceShape: Shape {
    public let mood: SomaMood

    public init(mood: SomaMood) {
        self.mood = mood
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let placement = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.outline(mood).applying(placement)
    }

    /// How far the mouth bends, on the grid: negative frowns.
    static func curve(_ mood: SomaMood) -> Double {
        [-2.6, -1.2, 0, 1.6, 3.0][mood.rawValue]
    }

    static func outline(_ mood: SomaMood) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 19, height: 19))
        path.addEllipse(in: CGRect(x: 8.1, y: 8.9, width: 1.6, height: 1.6))
        path.addEllipse(in: CGRect(x: 14.3, y: 8.9, width: 1.6, height: 1.6))
        let bend = curve(mood)
        let y = 15.4 - bend / 3
        path.move(to: CGPoint(x: 8.2, y: y))
        path.addQuadCurve(to: CGPoint(x: 15.8, y: y), control: CGPoint(x: 12, y: y + bend))
        return path
    }
}

/// The five faces in a row, each with its word under it: tap one to choose
/// it. The chosen face fills softly, rises a little and darkens its word;
/// the others step back.
public struct SomaMoodFaces: View {
    @Binding private var selection: SomaMood?
    private let action: ((SomaMood) -> Void)?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter action: called after a face is chosen, with it.
    public init(selection: Binding<SomaMood?>, action: ((SomaMood) -> Void)? = nil) {
        self._selection = selection
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: 0) {
            ForEach(SomaMood.allCases) { mood in
                let isChosen = selection == mood
                let isQuiet = selection != nil && !isChosen
                Button {
                    withAnimation(reduceMotion ? nil : theme.motion.selection) { selection = mood }
                    action?(mood)
                } label: {
                    VStack(spacing: metrics.moodFaceLabelGap) {
                        SomaMoodFace(mood, isFilled: isChosen)
                            .scaleEffect(isChosen && !reduceMotion ? metrics.moodFaceChosenScale : 1)
                        Text(mood.title)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(isChosen ? colors.inkPrimary.color : colors.inkSecondary.color)
                    }
                    .opacity(isQuiet ? metrics.moodFaceQuietOpacity : 1)
                    .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPress)
                .accessibilityLabel(Text(mood.title))
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview("Mood faces") {
    @Previewable @State var mood: SomaMood? = .good
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaMoodFaces(selection: $mood)
            SomaMoodFaces(selection: .constant(nil))
            HStack(spacing: 16) {
                ForEach(SomaMood.allCases) { SomaMoodFace($0, isFilled: true, side: 56) }
            }
        }
        .padding()
    }
}
