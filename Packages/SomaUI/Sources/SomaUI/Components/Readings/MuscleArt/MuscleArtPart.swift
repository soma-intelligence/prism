//
//  MuscleArtPart.swift
//  SomaUI (from MuscleMap)
//
//  Copyright © 2026 Melih Colpan. All rights reserved.
//  Licensed under the MIT License.
//
//  Vendored into SomaUI from MuscleMap (https://github.com/melihcolpan/MuscleMap)
//  under its MIT License, see LICENSE-MuscleMap.txt beside this file.
//  Soma changes: types renamed with a MuscleArt prefix and kept internal; only the male view boxes kept, the provider dropped.
//

import Foundation

/// SVG path data for a single body part, supporting common, left, and right sub-paths.
struct MuscleArtPart {
    let slug: MuscleArtSlug
    let common: [String]
    let left: [String]
    let right: [String]

    init(slug: MuscleArtSlug, common: [String] = [], left: [String] = [], right: [String] = []) {
        self.slug = slug
        self.common = common
        self.left = left
        self.right = right
    }

    /// All SVG path strings combined.
    var allPaths: [String] {
        common + left + right
    }
}

/// ViewBox configuration for body rendering.
struct MuscleArtViewBox {
    let origin: CGPoint
    let size: CGSize

    var rect: CGRect {
        CGRect(origin: origin, size: size)
    }

    static let maleFront = MuscleArtViewBox(
        origin: CGPoint(x: 0, y: 95),
        size: CGSize(width: 727, height: 1280)
    )

    static let maleBack = MuscleArtViewBox(
        origin: CGPoint(x: 718, y: 95),
        size: CGSize(width: 727, height: 1280)
    )
}
