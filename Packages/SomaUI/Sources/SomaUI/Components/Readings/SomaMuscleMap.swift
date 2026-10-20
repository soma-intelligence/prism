//
//  SomaMuscleMap.swift
//  SomaUI
//

import SwiftUI

/// A muscle the map draws. Each one is drawn on both sides of the body.
public enum SomaMuscle: String, CaseIterable, Sendable, Hashable {
    case traps, shoulders, chest, biceps, triceps, forearms, abs, obliques,
         lats, lowerBack, glutes, quads, adductors, hamstrings, calves
}

/// How rested a muscle is.
public enum SomaMuscleState: Sendable, Hashable, Codable {
    case recovered, fatigued, depleted
    /// Nothing recorded: drawn in the body's own grey.
    case none

    public var title: LocalizedStringResource {
        switch self {
        case .recovered: "Recovered"
        case .fatigued: "Fatigued"
        case .depleted: "Depleted"
        case .none: "No data"
        }
    }

    /// The state's tone: sage when rested, sand when tired, clay when
    /// spent, the calm tones the energy bank reads in. Nil for no data,
    /// which keeps the figure's own grey.
    public var tone: SomaColorValue? {
        switch self {
        case .recovered: SomaEnergyRamp.charge
        case .fatigued: SomaEnergyRamp.tone(at: 0.5)
        case .depleted: SomaEnergyRamp.tone(at: 0)
        case .none: nil
        }
    }

    /// The figure's own tone under its light: a pale stone on the light
    /// card, a lifted graphite on the dark one, so its forms read on both.
    static let figure = SomaColorValue(light: 0xD9DADD, dark: 0x6B6E76)
    /// A muscle with no data: a shade off the figure, so the muscles still
    /// read as muscles before the first session.
    static let idle = SomaColorValue(light: 0xCBCCD0, dark: 0x5E6169)

    /// The chest's tone in this state: the state's own, a step deeper and
    /// richer, so the chest stands out from the core and the shoulders
    /// beside it while still reading as the same state.
    public var chestTone: SomaColorValue? {
        switch self {
        case .recovered: SomaColorValue(light: 0x24745A, dark: 0x6ADDB0)
        case .fatigued: SomaColorValue(light: 0xB97D22, dark: 0xF5C25E)
        case .depleted: SomaColorValue(light: 0xA9472A, dark: 0xF5845C)
        case .none: nil
        }
    }
}

/// The six groups a session is read into, each a set of the muscles the map
/// draws.
public enum SomaMuscleGroup: String, CaseIterable, Sendable, Hashable, Identifiable, Codable {
    case chest, shoulders, arms, core, back, legs

    public var id: String { rawValue }

    public var title: LocalizedStringResource {
        switch self {
        case .chest: "Chest"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .core: "Core"
        case .back: "Back"
        case .legs: "Legs"
        }
    }

    public var muscles: Set<SomaMuscle> {
        switch self {
        case .chest: [.chest]
        case .shoulders: [.shoulders]
        case .arms: [.biceps, .triceps, .forearms]
        case .core: [.abs, .obliques, .lowerBack]
        case .back: [.traps, .lats]
        case .legs: [.glutes, .quads, .adductors, .hamstrings, .calves]
        }
    }

    /// The group a drawn muscle belongs to.
    public static func of(_ muscle: SomaMuscle) -> SomaMuscleGroup {
        allCases.first { $0.muscles.contains(muscle) } ?? .core
    }
}

/// The body front and back, each muscle tinted by how rested it is: a
/// rendered anatomical figure in the card's quiet tone, the muscles in sage,
/// sand or clay under the figure's own light and shade, the chest a step
/// deeper so it stands out, and a muscle with no data a shade off the figure.
///
/// Given a highlight, every other muscle steps back, so one group reads
/// against the rest; given an action, a tap on a muscle names it.
///
/// The figure is rendered from Z-Anatomy, the libre 3D atlas of anatomy
/// (CC BY-SA 4.0), based on BodyParts3D, The Database Center for Life
/// Science (CC BY-SA 2.1 Japan): a grey image of the body's light and shade
/// and one mask per ``SomaMuscle`` and side, in `Resources/MuscleFigure`
/// (see ``SomaMuscleFigureArt``). The view fills the silhouette and each mask
/// with its tone, then multiplies the light and shade over them, so every
/// state keeps the same forms.
public struct SomaMuscleMap: View {
    private let states: [SomaMuscle: SomaMuscleState]
    private let highlight: Set<SomaMuscle>?
    private let onTap: ((SomaMuscle?) -> Void)?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the figure's art is decoded; see ``SomaMuscleFigureArt/prepare()``.
    @State private var isReady = SomaMuscleFigureArt.isReady

    /// - Parameters:
    ///   - highlight: the muscles to bring forward; nil draws all alike.
    ///   - onTap: called with the muscle under a tap, nil off the muscles.
    public init(
        _ states: [SomaMuscle: SomaMuscleState],
        highlight: Set<SomaMuscle>? = nil,
        onTap: ((SomaMuscle?) -> Void)? = nil
    ) {
        self.states = states
        self.highlight = highlight
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: theme.metrics.muscleMapFigureGap) {
            ForEach(SomaMuscleFigureArt.Side.allCases, id: \.self) { side in
                Figure(art: isReady ? .of(side) : nil, states: states, highlight: highlight, onTap: onTap)
                    .aspectRatio(SomaMuscleFigureArt.aspect, contentMode: .fit)
            }
        }
        .frame(maxHeight: theme.metrics.muscleMapHeight)
        // The art is a few megabytes once decoded: read off the main thread,
        // then drawn, faded in unless Reduce Motion is on.
        .task {
            guard !isReady else { return }
            await SomaMuscleFigureArt.prepare()
            withAnimation(reduceMotion ? nil : .easeOut(duration: theme.motion.pressDuration * 2)) { isReady = true }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Muscle map"))
        .accessibilityValue(Text(summary))
    }

    private var summary: String {
        SomaMuscle.allCases.compactMap { muscle in
            guard let state = states[muscle], state != .none else { return nil }
            return "\(muscle.rawValue) \(String(localized: state.title))"
        }.joined(separator: ", ")
    }

    private struct Figure: View {
        let art: SomaMuscleFigureArt?
        let states: [SomaMuscle: SomaMuscleState]
        let highlight: Set<SomaMuscle>?
        let onTap: ((SomaMuscle?) -> Void)?

        @Environment(\.somaTheme) private var theme

        var body: some View {
            let canvas = Canvas { context, size in
                guard let art else { return }
                let rect = art.fit(in: size)
                let pixel = rect.width / art.size.width
                let figure = SomaMuscleState.figure.color
                let idle = SomaMuscleState.idle.color

                context.drawLayer { layer in
                    // The silhouette in the figure's own tone: the head,
                    // hands, feet, the bones that show and the muscles the
                    // map does not read.
                    var silhouette = layer.resolve(Image(decorative: art.image, scale: 1).renderingMode(.template))
                    silhouette.shading = .color(figure)
                    layer.draw(silhouette, in: rect)

                    // Each muscle in its state's tone.
                    for mask in art.masks {
                        var tinted = layer.resolve(Image(decorative: mask.image, scale: 1).renderingMode(.template))
                        tinted.shading = .color(tone(of: mask.muscle, idle: idle))
                        layer.draw(tinted, in: CGRect(
                            x: rect.minX + mask.frame.minX * pixel,
                            y: rect.minY + mask.frame.minY * pixel,
                            width: mask.frame.width * pixel,
                            height: mask.frame.height * pixel
                        ))
                    }

                    // The render's light and shade over every tone, so a
                    // muscle keeps its form whatever its state.
                    layer.blendMode = .multiply
                    layer.draw(layer.resolve(Image(decorative: art.image, scale: 1)), in: rect)
                }
            }

            if let onTap, let art {
                GeometryReader { proxy in
                    canvas
                        .contentShape(.rect)
                        .onTapGesture(coordinateSpace: .local) { location in
                            onTap(art.muscle(at: location, in: proxy.size))
                        }
                }
            } else {
                canvas
            }
        }

        /// The tone a muscle is filled with: its state's, the chest a step
        /// deeper and richer so it stands out from the core under it, and a
        /// muscle outside the group being read stepping back toward the
        /// figure with a trace of its tone.
        private func tone(of muscle: SomaMuscle, idle: Color) -> Color {
            let state = states[muscle] ?? .none
            var tone = state.tone?.color ?? idle
            if muscle == .chest, let lead = state.chestTone?.color {
                tone = lead
            }
            let isBack = highlight.map { !$0.contains(muscle) } ?? false
            return isBack ? idle.mix(with: tone, by: theme.metrics.muscleMapBackTone) : tone
        }
    }
}

#Preview("Muscle map") {
    ZStack {
        SomaPreviewBackdrop()
        SomaMuscleMap([
            .chest: .recovered, .shoulders: .recovered, .abs: .recovered, .lats: .recovered,
            .biceps: .recovered, .triceps: .recovered,
            .quads: .fatigued, .hamstrings: .fatigued, .calves: .fatigued, .glutes: .depleted,
        ])
        .padding(24)
    }
}
