//
//  SomaSwitch.swift
//  SomaUI
//

import SwiftUI

/// An on and off switch drawn like ``SomaAnswerSwitch`` with two slots:
/// a cross for off and a check for on, in one recessed track, and one knob
/// that slides between them. On, the knob takes the accent and its check the
/// ink that reads on it; off, it is a raised surface over the cross.
///
/// The system switch tinted with this theme's accent draws a white knob on a
/// white track in dark appearance, since the accent is ink rather than a hue:
/// on and off look alike there. This switch reads in both appearances.
///
/// The whole switch is the button; VoiceOver hears a switch.
public struct SomaSwitch: View {
    private let title: Text
    @Binding private var isOn: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter title: what VoiceOver names the switch; it is not drawn.
    public init(_ title: Text, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    public init(_ title: LocalizedStringResource, isOn: Binding<Bool>) {
        self.init(Text(title), isOn: isOn)
    }

    /// The slot the knob rests on: 0 for off (the cross), 1 for on.
    public static func slot(_ isOn: Bool) -> Int { isOn ? 1 : 0 }

    public var body: some View {
        let metrics = theme.metrics
        let slot = metrics.trackAnswerSlotWidth
        let height = metrics.trackAnswerCellHeight
        let knob = RoundedRectangle(cornerRadius: metrics.trackAnswerCornerRadius - metrics.trackAnswerInset, style: .continuous)
        let offset = CGFloat(Self.slot(isOn)) * slot

        Button {
            if reduceMotion { isOn.toggle() } else { withAnimation(theme.motion.trackAnswer) { isOn.toggle() } }
        } label: {
            ZStack(alignment: .leading) {
                marks(chosen: false)
                knobFill(knob)
                    .frame(width: slot, height: height)
                    .offset(x: offset)
                marks(chosen: true)
                    .mask(alignment: .leading) {
                        knob.frame(width: slot, height: height).offset(x: offset)
                    }
            }
            .frame(width: slot * 2, height: height)
            .padding(metrics.trackAnswerInset)
            .background(
                RoundedRectangle(cornerRadius: metrics.trackAnswerCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceRecessed.color)
            )
            // Taller to a thumb than to the eye.
            .padding(.vertical, metrics.trackAnswerReach)
            .contentShape(.rect)
            .padding(.vertical, -metrics.trackAnswerReach)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { title }
        }
    }

    /// The cross and the check: faint at rest, or in the ink each takes
    /// under the knob.
    private func marks(chosen: Bool) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let stroke = StrokeStyle(lineWidth: metrics.trackAnswerGlyphStroke, lineCap: .round, lineJoin: .round)

        return HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { on in
                let ink: Color = !chosen
                    ? colors.inkSecondary.color.opacity(metrics.trackAnswerIdleOpacity)
                    : (on ? colors.onAccent.color : colors.inkPrimary.color)
                SomaAnswerMarkShape(isYes: on)
                    .stroke(ink, style: stroke)
                    .frame(width: metrics.trackAnswerGlyph, height: metrics.trackAnswerGlyph)
                    .frame(width: metrics.trackAnswerSlotWidth, height: metrics.trackAnswerCellHeight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The knob: the accent when on, else a raised surface (an ink wash over
    /// the track in dark, where the surface is the card's own). One shape
    /// whose colour moves with it.
    private func knobFill(_ knob: RoundedRectangle) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let isDark = scheme == .dark
        let base: Color = isOn ? colors.accent.color : (isDark ? colors.surfaceRecessed.color : colors.surface.color)

        return knob.fill(base)
            .overlay(knob.fill(colors.inkPrimary.color.opacity(isDark && !isOn ? metrics.trackAnswerNoOpacity : 0)))
            .shadow(color: colors.inkPrimary.color.opacity(isDark ? 0 : metrics.journalChoiceShadowOpacity),
                    radius: metrics.journalChoiceShadowRadius, y: 0.5)
            .allowsHitTesting(false)
    }
}

/// A `Toggle` drawn as its label and a ``SomaSwitch`` at the trailing edge,
/// so a settings row keeps the toggle's own label and semantics.
public struct SomaSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 0)
            SomaSwitch(Text(""), isOn: configuration.$isOn)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

public extension ToggleStyle where Self == SomaSwitchToggleStyle {
    /// The Soma switch with a cross and a check under a sliding knob.
    /// ``SomaSwitchStyle`` owns `.soma`.
    static var somaCrossCheck: SomaSwitchToggleStyle { SomaSwitchToggleStyle() }
}

#Preview("Switch") {
    @Previewable @State var on = true
    @Previewable @State var off = false
    VStack(spacing: 24) {
        SomaSwitch("On", isOn: $on)
        SomaSwitch("Off", isOn: $off)
        Toggle("Calendar busy times", isOn: $on)
            .toggleStyle(.soma)
    }
    .padding()
    .somaTheme(.standard)
}
