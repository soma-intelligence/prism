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
public enum SomaMuscleState: Sendable, Hashable {
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

    func color(_ colors: SomaColors) -> Color? {
        tone?.color
    }
}

/// The six groups a session is read into, each a set of the muscles the map
/// draws.
public enum SomaMuscleGroup: String, CaseIterable, Sendable, Hashable, Identifiable {
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

/// The body front and back, each muscle filled by how rested it is: a quiet
/// figure, the muscles in sage, sand or clay with a hairline seam between
/// them, and a muscle with no data left a shade lighter than the figure.
///
/// Given a highlight, every other muscle steps back, so one group reads
/// against the rest; given an action, a tap on a muscle names it.
///
/// The figure is real anatomical art: the male front and back paths of the MIT
/// licensed MuscleMap SDK by Melih Colpan, vendored in `MuscleArt/` with its
/// licence. Every vendored muscle group belongs to one ``SomaMuscle`` (several
/// can share one, the shins ride with the calves), and the parts that are not
/// muscles (head, hands, knees, feet) are the figure itself.
public struct SomaMuscleMap: View {
    private let states: [SomaMuscle: SomaMuscleState]
    private let highlight: Set<SomaMuscle>?
    private let onTap: ((SomaMuscle?) -> Void)?

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
        HStack(spacing: 0) {
            Figure(art: .front, states: states, highlight: highlight, onTap: onTap)
            Figure(art: .back, states: states, highlight: highlight, onTap: onTap)
        }
        .aspectRatio(MuscleArtFigure.front.bounds.width * 2 / MuscleArtFigure.front.bounds.height, contentMode: .fit)
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
        let art: MuscleArtFigure
        let states: [SomaMuscle: SomaMuscleState]
        let highlight: Set<SomaMuscle>?
        let onTap: ((SomaMuscle?) -> Void)?

        @Environment(\.somaTheme) private var theme

        var body: some View {
            let canvas = Canvas { context, size in
                let fit = art.fit(in: size)
                context.translateBy(x: fit.offset.x, y: fit.offset.y)
                context.scaleBy(x: fit.scale, y: fit.scale)
                let scale = fit.scale

                let colors = theme.colors
                let surface = colors.surface.color
                let ink = colors.inkSecondary.color
                // Opaque tones, so a part that overlaps its neighbour never
                // reads darker where they meet.
                let figure = surface.mix(with: ink, by: 0.26)
                let idle = surface.mix(with: ink, by: 0.36)
                // The art leaves a wide gap round every part. Each part swells
                // by this much on screen, which closes the gap down to a thin
                // seam of the card's own surface between neighbours.
                let swell = StrokeStyle(lineWidth: 0.7 / scale, lineJoin: .round)

                for part in art.parts {
                    let shading: GraphicsContext.Shading
                    let isBack = part.muscle.map { muscle in highlight.map { !$0.contains(muscle) } ?? false } ?? false
                    if part.muscle == nil {
                        shading = .color(figure)
                    } else if isBack {
                        // Not the group being read: it steps back toward
                        // the figure, keeping a trace of its tone.
                        let tone = state(part).color(colors) ?? idle
                        shading = .color(idle.mix(with: tone, by: theme.metrics.muscleMapBackTone))
                    } else if let color = state(part).color(colors) {
                        // Top lit, so each muscle reads as a form.
                        let rect = part.path.boundingRect
                        shading = .linearGradient(
                            Gradient(colors: [color, color.mix(with: surface, by: 0.16)]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    } else {
                        shading = .color(idle)
                    }
                    context.fill(part.path, with: shading)
                    context.stroke(part.path, with: shading, style: swell)
                }
                // A hairline seam on every edge, so parts that meet still read
                // as separate muscles.
                for part in art.parts {
                    context.stroke(part.path, with: .color(surface), lineWidth: 0.45 / scale)
                }
            }
            // The back sits a step behind the front.
            .opacity(art.isBack ? 0.86 : 1)

            if let onTap {
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

        private func state(_ part: MuscleArtFigure.Part) -> SomaMuscleState {
            part.muscle.flatMap { states[$0] } ?? .none
        }
    }
}

// MARK: - The art

/// One side of the vendored figure, parsed once: each part's path in the
/// art's own coordinates, and the muscle it reads (nil for the figure itself).
struct MuscleArtFigure: Sendable {
    struct Part: Sendable {
        let muscle: SomaMuscle?
        let path: Path
    }

    let parts: [Part]
    /// The drawn extent, so the two sides sit close together.
    let bounds: CGRect
    let isBack: Bool

    static let front = MuscleArtFigure(MuscleArtMaleFront.paths, isBack: false)
    static let back = MuscleArtFigure(MuscleArtMaleBack.paths, isBack: true)

    private init(_ source: [MuscleArtPart], isBack: Bool) {
        var parts: [Part] = []
        for part in source {
            // The art layers finer sub groups over their parents; the map reads
            // whole groups, so it draws the parents and the sub groups the
            // art always shows (adductors, neck, ankles).
            if let group = part.slug.muscle, group.isSubGroup, !group.isAlwaysVisibleSubGroup { continue }
            let muscle = Self.muscle(for: part.slug)
            for string in part.allPaths {
                let path = MuscleArtPathBuilder.buildPath(from: string, scale: 1, offsetX: 0, offsetY: 0)
                parts.append(Part(muscle: muscle, path: path))
            }
        }
        // The figure first, the muscles over it.
        parts.sort { ($0.muscle == nil ? 0 : 1) < ($1.muscle == nil ? 0 : 1) }
        self.parts = parts
        let union = parts.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
        self.bounds = union.insetBy(dx: -4, dy: -4)
        self.isBack = isBack
    }

    /// Where the art sits in a frame of `size`: scaled to fit and centred.
    func fit(in size: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        return (scale, CGPoint(
            x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
            y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale
        ))
    }

    /// The muscle under a point of a frame of `size`, the topmost part
    /// first; nil on the figure or off it.
    func muscle(at point: CGPoint, in size: CGSize) -> SomaMuscle? {
        let fit = fit(in: size)
        guard fit.scale > 0 else { return nil }
        let local = CGPoint(x: (point.x - fit.offset.x) / fit.scale, y: (point.y - fit.offset.y) / fit.scale)
        for part in parts.reversed() where part.path.contains(local) {
            return part.muscle
        }
        return nil
    }

    /// Which ``SomaMuscle`` a vendored group reads. Nil is the figure itself.
    static func muscle(for slug: MuscleArtSlug) -> SomaMuscle? {
        switch slug {
        case .trapezius, .upperTrapezius, .lowerTrapezius: .traps
        case .deltoids, .frontDeltoid, .rearDeltoid, .rotatorCuff: .shoulders
        case .chest, .upperChest, .lowerChest: .chest
        case .biceps: .biceps
        case .triceps: .triceps
        case .forearm: .forearms
        case .abs, .upperAbs, .lowerAbs: .abs
        case .obliques, .serratus: .obliques
        case .upperBack, .rhomboids: .lats
        case .lowerBack: .lowerBack
        case .gluteal: .glutes
        case .quadriceps, .innerQuad, .outerQuad, .hipFlexors: .quads
        case .adductors: .adductors
        case .hamstring: .hamstrings
        case .calves, .tibialis: .calves
        case .head, .hair, .neck, .hands, .knees, .feet, .ankles: nil
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
