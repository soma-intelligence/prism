//
//  MuscleArtGroup.swift
//  SomaUI (from MuscleMap)
//
//  Copyright © 2026 Melih Colpan. All rights reserved.
//  Licensed under the MIT License.
//
//  Vendored into SomaUI from MuscleMap (https://github.com/melihcolpan/MuscleMap)
//  under its MIT License, see LICENSE-MuscleMap.txt beside this file.
//  Soma changes: types renamed with a MuscleArt prefix and kept internal; localized display names dropped.
//

import Foundation

/// Represents all available muscle groups that can be highlighted on the body.
enum MuscleArtGroup: String, CaseIterable, Sendable {
    case abs
    case biceps
    case calves
    case chest
    case deltoids
    case feet
    case forearm
    case gluteal
    case hamstring
    case hands
    case head
    case knees
    case lowerBack = "lower-back"
    case obliques
    case quadriceps
    case tibialis
    case trapezius
    case triceps
    case upperBack = "upper-back"

    // New muscle groups
    case rotatorCuff = "rotator-cuff"
    case serratus
    case rhomboids

    // Sub-groups
    case ankles
    case adductors
    case neck
    case hipFlexors = "hip-flexors"
    case upperChest = "upper-chest"
    case lowerChest = "lower-chest"
    case innerQuad = "inner-quad"
    case outerQuad = "outer-quad"
    case upperAbs = "upper-abs"
    case lowerAbs = "lower-abs"
    case frontDeltoid = "front-deltoid"
    case rearDeltoid = "rear-deltoid"
    case upperTrapezius = "upper-trapezius"
    case lowerTrapezius = "lower-trapezius"

    /// Whether this is a cosmetic part (head/hair) rather than a muscle.
    var isCosmeticPart: Bool {
        self == .head
    }

    /// Sub-groups belonging to this muscle group. Empty if this muscle has no sub-groups.
    var subGroups: [MuscleArtGroup] {
        switch self {
        case .chest: return [.upperChest, .lowerChest]
        case .quadriceps: return [.innerQuad, .outerQuad, .hipFlexors]
        case .abs: return [.upperAbs, .lowerAbs]
        case .deltoids: return [.frontDeltoid, .rearDeltoid]
        case .trapezius: return [.upperTrapezius, .lowerTrapezius]
        case .obliques: return [.serratus]
        case .feet: return [.ankles]
        case .hamstring: return [.adductors]
        case .head: return [.neck]
        default: return []
        }
    }

    /// The parent muscle group, if this muscle is a sub-group.
    var parentGroup: MuscleArtGroup? {
        switch self {
        case .upperChest, .lowerChest: return .chest
        case .innerQuad, .outerQuad, .hipFlexors: return .quadriceps
        case .upperAbs, .lowerAbs: return .abs
        case .frontDeltoid, .rearDeltoid: return .deltoids
        case .upperTrapezius, .lowerTrapezius: return .trapezius
        case .serratus: return .obliques
        case .ankles: return .feet
        case .adductors: return .hamstring
        case .neck: return .head
        default: return nil
        }
    }

    /// Whether this muscle is a sub-group of another muscle.
    var isSubGroup: Bool {
        parentGroup != nil
    }

    /// Whether this sub-group is always rendered even when sub-groups are hidden.
    /// When tapped in default mode, the parent muscle is returned instead.
    var isAlwaysVisibleSubGroup: Bool {
        switch self {
        case .ankles, .adductors, .neck: return true
        default: return false
        }
    }
}

/// Internal-only slug that includes hair for rendering purposes.
enum MuscleArtSlug: String, CaseIterable {
    case abs
    case biceps
    case calves
    case chest
    case deltoids
    case feet
    case forearm
    case gluteal
    case hamstring
    case hands
    case hair
    case head
    case knees
    case lowerBack = "lower-back"
    case obliques
    case quadriceps
    case tibialis
    case trapezius
    case triceps
    case upperBack = "upper-back"

    // New muscle groups
    case rotatorCuff = "rotator-cuff"
    case serratus
    case rhomboids

    // Sub-groups
    case ankles
    case adductors
    case neck
    case hipFlexors = "hip-flexors"
    case upperChest = "upper-chest"
    case lowerChest = "lower-chest"
    case innerQuad = "inner-quad"
    case outerQuad = "outer-quad"
    case upperAbs = "upper-abs"
    case lowerAbs = "lower-abs"
    case frontDeltoid = "front-deltoid"
    case rearDeltoid = "rear-deltoid"
    case upperTrapezius = "upper-trapezius"
    case lowerTrapezius = "lower-trapezius"

    var muscle: MuscleArtGroup? {
        switch self {
        case .hair: return nil
        default: return MuscleArtGroup(rawValue: rawValue)
        }
    }
}
