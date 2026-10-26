//
//  MuscleArtFigure.swift
//  SomaUI
//

import SwiftUI

/// One side of the vendored figure, parsed once: each part's path in the
/// art's own coordinates, and the muscle it reads (nil for the figure itself).
struct MuscleArtFigure: Sendable {
    struct Part: Sendable {
        let muscle: SomaMuscle?
        let path: Path
    }

    let parts: [Part]
    /// The drawn extent, so the two sides sit close as they do in the reference design.
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
