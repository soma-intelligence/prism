//
//  TodayRoutes.swift
//  Prism
//

import SomaUI

/// Where each entry on Today opens: every aspect, wherever Today names it,
/// opens that aspect's own page (owner, 2026-10-20). The night card is the
/// one exception, by design: it opens last night, and the Sleep page
/// (the score's) links to it and back.
enum TodayRoutes {
    /// A score ring under the orb.
    static func ring(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// The orb, for the aspect it shows: the aspect's page, pushed plainly.
    static func orb(_ aspect: SomaAspect) -> PulseRoute { .orb(aspect) }
    /// An aspect card in Your aspects.
    static func aspectCard(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// A tile in Today's Categories grid.
    static func tile(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// A row of the six aspects in All categories.
    static func allCategories(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// The last night card.
    static let nightCard = ScoreRoute.lastNight
}
