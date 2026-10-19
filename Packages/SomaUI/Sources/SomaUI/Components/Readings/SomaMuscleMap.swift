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

    func color(_ colors: SomaColors) -> Color? {
        switch self {
        case .recovered: colors.statusNormal.color
        case .fatigued: colors.statusOut.color
        case .depleted: colors.statusAlert.color
        case .none: nil
        }
    }
}

/// The body front and back, each muscle filled by how rested it is: a graphite
/// figure, the muscles in green, amber
/// or red with a hairline seam between them, and a muscle with no data left a
/// shade lighter than the figure.
///
/// The figure is real anatomical art: the male front and back paths of the MIT
/// licensed MuscleMap SDK by Melih Colpan, vendored in `MuscleArt/` with its
/// licence. Every vendored muscle group belongs to one ``SomaMuscle`` (several
/// can share one, the shins ride with the calves), and the parts that are not
/// muscles (head, hands, knees, feet) are the figure itself.
public struct SomaMuscleMap: View {
    private let states: [SomaMuscle: SomaMuscleState]

    public init(_ states: [SomaMuscle: SomaMuscleState]) {
        self.states = states
    }

    public var body: some View {
        HStack(spacing: 0) {
            Figure(art: .front, states: states)
            Figure(art: .back, states: states)
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

        @Environment(\.somaTheme) private var theme

        var body: some View {
            Canvas { context, size in
                let box = art.bounds
                let scale = min(size.width / box.width, size.height / box.height)
                context.translateBy(
                    x: (size.width - box.width * scale) / 2 - box.minX * scale,
                    y: (size.height - box.height * scale) / 2 - box.minY * scale
                )
                context.scaleBy(x: scale, y: scale)

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
                    if part.muscle == nil {
                        shading = .color(figure)
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
