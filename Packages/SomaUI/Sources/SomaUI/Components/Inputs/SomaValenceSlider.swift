//
//  SomaValenceSlider.swift
//  SomaUI
//

import SwiftUI

/// Seven stops from very unpleasant to very pleasant, with a thumb to drag.
///
/// The track carries the whole mood scale as a gradient, cool to warm, and
/// the thumb holds a dot of the colour under it. The thumb follows the finger
/// and settles on the nearest stop when it lifts; the word for the stop it is
/// on sits under the track and changes as it moves. Before a feeling is
/// chosen the track is dimmed and the thumb rests at neutral.
public struct SomaValenceSlider: View {
    @Binding private var value: Int?
    private let stops: Int
    private let low: String
    private let high: String
    private let names: [String]
    private let prompt: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the finger is along the track while it drags, 0 to 1.
    @State private var dragShare: Double?

    /// - Parameters:
    ///   - value: 0...stops minus one, or nil until chosen.
    ///   - names: what each stop is called: the word under the track, and
    ///     what VoiceOver reads.
    ///   - prompt: the line under the track before anything is chosen.
    public init(value: Binding<Int?>, stops: Int = 7, low: String, high: String, names: [String], prompt: String? = nil) {
        self._value = value
        self.stops = max(2, stops)
        self.low = low
        self.high = high
        self.names = names
        self.prompt = prompt
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let middle = (stops - 1) / 2
        let word = value.flatMap { names.indices.contains($0) ? names[$0] : nil }

        VStack(spacing: metrics.cardSpacing) {
            track

            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .somaFont(theme.typography.tabLabel)
            .foregroundStyle(colors.inkSecondary.color)
            .accessibilityHidden(true)

            if let line = word ?? prompt {
                Text(line)
                    .somaFont(theme.typography.field)
                    .foregroundStyle(word == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .animation(reduceMotion ? nil : theme.motion.selection, value: line)
                    .padding(.top, metrics.cardSpacing * 0.5)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(Text("\(low) to \(high)"))
        .accessibilityValue(Text(word ?? "Not set"))
        .accessibilityAdjustableAction { direction in
            let current = value ?? middle
            switch direction {
            case .increment: value = min(current + 1, stops - 1)
            case .decrement: value = max(current - 1, 0)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let middle = (stops - 1) / 2
        let thumb = metrics.valenceThumbDiameter
        let settled = SomaMoodScale.share(value ?? middle, stops: stops)
        let share = dragShare ?? settled
        let aspect = SomaMoodScale.aspect(for: value ?? middle, stops: stops)
        let dot = SomaMoodScale.glow(aspect, theme: theme)
        let isDark = colorScheme == .dark

        return GeometryReader { proxy in
            let width = proxy.size.width
            let inset = thumb / 2
            let run = max(width - inset * 2, 1)
            let y = proxy.size.height / 2

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(LinearGradient(gradient: SomaMoodScale.gradient(theme: theme), startPoint: .leading, endPoint: .trailing))
                    .frame(width: width, height: metrics.valenceTrackHeight)
                    .opacity(value == nil ? metrics.valenceUnsetOpacity : 1)
                    .position(x: width / 2, y: y)

                ForEach(0..<stops, id: \.self) { stop in
                    Circle()
                        .fill(colors.onOrb.color.opacity(0.7))
                        .frame(width: metrics.valenceStopDiameter, height: metrics.valenceStopDiameter)
                        .position(x: inset + run * SomaMoodScale.share(stop, stops: stops), y: y)
                }

                Circle()
                    .fill(colors.onOrb.color)
                    .frame(width: thumb, height: thumb)
                    .overlay {
                        Circle()
                            .fill(dot)
                            .frame(width: metrics.valenceThumbDotDiameter, height: metrics.valenceThumbDotDiameter)
                            .opacity(value == nil ? 0 : 1)
                    }
                    .overlay {
                        Circle().strokeBorder(colors.inkPrimary.color.opacity(isDark ? 0 : metrics.hairlineOpacity), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(isDark ? 0.4 : 0.16), radius: thumb * 0.18, y: thumb * 0.06)
                    .scaleEffect(dragShare == nil ? 1 : 1.08)
                    .position(x: inset + run * share, y: y)
                    .animation(reduceMotion || dragShare != nil ? nil : theme.motion.selection, value: share)
            }
            .contentShape(.rect)
            .somaClaimsSwipe()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = min(max((drag.location.x - inset) / run, 0), 1)
                        dragShare = next
                        value = Int((next * Double(stops - 1)).rounded())
                    }
                    .onEnded { _ in
                        dragShare = nil
                    }
            )
        }
        .frame(height: max(metrics.minimumTapTarget, thumb))
    }
}

#Preview("Valence") {
    @Previewable @State var feeling: Int? = 4
    @Previewable @State var unset: Int?
    let names = ["Very unpleasant", "Unpleasant", "Slightly unpleasant", "Neutral", "Slightly pleasant", "Pleasant", "Very pleasant"]
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 40) {
            SomaValenceSlider(value: $feeling, low: "Very unpleasant", high: "Very pleasant", names: names)
            SomaValenceSlider(value: $unset, low: "Very unpleasant", high: "Very pleasant", names: names, prompt: "Slide to choose")
        }
        .padding()
    }
}
