//
//  SomaRitual.swift
//  SomaUI
//

import SwiftUI

// MARK: - Step

/// One step of a ritual: a square to tick, the step's line glyph and its
/// name. The whole row is the button. Ticked, the square fills with the
/// ritual's tone and its check draws itself, and the name softens; under
/// Reduce Motion it simply changes. A step Apple Health ticked carries a
/// small heart after its name, so the person knows they did not have to.
public struct SomaRitualStep<Trailing: View>: View {
    private let title: String
    private let glyph: SomaTrackGlyph.Kind
    private let tone: SomaTrackTone
    private let isDone: Bool
    private let isFromHealth: Bool
    private let toggle: () -> Void
    private let trailing: Trailing

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - isFromHealth: whether Apple Health ticked it rather than the
    ///     person.
    ///   - trailing: an optional control after the name, such as a button
    ///     that starts the step.
    public init(_ title: String, glyph: SomaTrackGlyph.Kind, tone: SomaTrackTone, isDone: Bool,
                isFromHealth: Bool = false,
                toggle: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.glyph = glyph
        self.tone = tone
        self.isDone = isDone
        self.isFromHealth = isFromHealth
        self.toggle = toggle
        self.trailing = trailing()
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.browseRowSpacing) {
            Button(action: toggle) {
                HStack(spacing: metrics.browseRowSpacing) {
                    SomaRitualCheck(isDone: isDone, tone: tone)
                    SomaTrackGlyph(glyph, tone: tone, style: .inline)
                        .opacity(isDone ? 0.55 : 1)
                    Text(title)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(isDone ? colors.inkSecondary.color : colors.inkPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if isFromHealth && isDone {
                        Image(systemName: "heart.fill")
                            .font(.system(size: metrics.ritualSourceGlyph, weight: .semibold))
                            .foregroundStyle(tone.color)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: metrics.ritualStepMinHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.somaGlassPressDim)
            .sensoryFeedback(.selection, trigger: isDone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(isDone ? (isFromHealth ? "Done, from Apple Health" : "Done") : "Not done"))
            .accessibilityAddTraits(isDone ? .isSelected : [])
            trailing
        }
        .animation(reduceMotion ? nil : theme.motion.trackAnswer, value: isDone)
    }
}

public extension SomaRitualStep where Trailing == EmptyView {
    init(_ title: String, glyph: SomaTrackGlyph.Kind, tone: SomaTrackTone, isDone: Bool, toggle: @escaping () -> Void) {
        self.init(title, glyph: glyph, tone: tone, isDone: isDone, toggle: toggle) { EmptyView() }
    }
}

/// The square a step is ticked in: an outline when open, filled in the tone
/// with a check drawn in when done.
public struct SomaRitualCheck: View {
    private let isDone: Bool
    private let tone: SomaTrackTone

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isDone: Bool, tone: SomaTrackTone) {
        self.isDone = isDone
        self.tone = tone
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let shape = RoundedRectangle(cornerRadius: metrics.ritualCheckCornerRadius, style: .continuous)

        ZStack {
            shape.strokeBorder(colors.inkSecondary.color.opacity(metrics.journalMarkIdleOpacity), lineWidth: 1.5)
                .opacity(isDone ? 0 : 1)
            shape.fill(tone.color)
                .scaleEffect(isDone || reduceMotion ? 1 : theme.motion.trackAnswerFrom)
                .opacity(isDone ? 1 : 0)
            // The check draws itself in once, then fades out whole when the
            // tick is taken back: trimming it back leaves a stub of line on
            // the way.
            if isDone {
                SomaDrawnCheck(ink: colors.surface.color)
                    .frame(width: metrics.journalMarkGlyph, height: metrics.journalMarkGlyph)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.ritualCheckSide, height: metrics.ritualCheckSide)
        .accessibilityHidden(true)
    }
}

/// A check that draws itself in when it appears, on the theme's
/// ``SomaMotion/trackMarkDraw``; already drawn under Reduce Motion.
struct SomaDrawnCheck: View {
    let ink: Color

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        SomaAnswerMarkShape(isYes: true)
            .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
            .stroke(ink, style: StrokeStyle(lineWidth: theme.metrics.trackAnswerGlyphStroke, lineCap: .round, lineJoin: .round))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(theme.motion.trackMarkDraw) { drawn = true }
            }
    }
}

// MARK: - Days

/// A routine's last days as a row of small squares, oldest first: each
/// filled in its tone by the share of steps done that day, an empty day a
/// faint wash, today ringed. Consistency at a glance, no numbers needed.
public struct SomaRitualDays: View {
    private let shares: [Double?]
    private let tone: SomaTrackTone

    @Environment(\.somaTheme) private var theme

    /// - Parameter shares: one per day, oldest first, the last being today:
    ///   0...1 of the steps done, nil for a day before the routine existed.
    public init(shares: [Double?], tone: SomaTrackTone) {
        self.shares = shares
        self.tone = tone
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.ritualDaySpacing) {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                let shape = RoundedRectangle(cornerRadius: metrics.ritualDayCornerRadius, style: .continuous)
                shape
                    .fill(colors.inkPrimary.color.opacity(share == nil ? metrics.ritualDayIdleOpacity * 0.5 : metrics.ritualDayIdleOpacity))
                    .overlay {
                        if let share, share > 0 {
                            shape.fill(tone.color.opacity(0.25 + 0.75 * share))
                        }
                    }
                    .overlay {
                        if index == shares.count - 1 {
                            shape.inset(by: -2.5)
                                .strokeBorder(colors.inkPrimary.color.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.ritualDayHeight)
            }
        }
        .padding(.horizontal, 2.5)
        .accessibilityElement()
        .accessibilityLabel(Text("\(shares.filter { ($0 ?? 0) >= 1 }.count) of the last \(shares.count) days kept"))
    }
}

#Preview("Ritual parts") {
    // Sample steps and days live in SomaPreviewSamples (ritualSteps,
    // ritualDays); this preview shows the parts at rest.
    ZStack {
        SomaPreviewBackdrop()
        VStack(alignment: .leading, spacing: 16) {
            SomaRitualCheck(isDone: false, tone: .sand)
            SomaRitualCheck(isDone: true, tone: .sand)
        }
        .padding()
    }
}
