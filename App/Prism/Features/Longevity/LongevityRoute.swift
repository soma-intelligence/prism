//
//  LongevityRoute.swift
//  Prism
//

import Foundation

/// Where a row on the Longevity tab's Body page leads.
///
/// The page pushes these with `NavigationLink(value:)` and the Longevity
/// container, which owns the stack, maps each one to its page:
/// ``BodyCardioPage``, ``BodyStrengthPage``, ``BodyBrowserView`` and
/// ``BodyCategoryPage``.
enum LongevityRoute: Hashable {
    /// VO2 max, resting heart rate, recovery, zones and the latest run.
    case cardio
    /// Lean mass, strength sessions and the next session.
    case strength
}
