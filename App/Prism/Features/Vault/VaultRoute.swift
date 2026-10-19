//
//  VaultRoute.swift
//  Prism
//

import SwiftUI

/// The Vault's pages: the browser, a category, one data type over time, and
/// every record it holds.
///
/// The Vault opens from the account sheet, which every tab reaches from its top
/// bar (owner's call, 2026-10-03: it did not belong under Body).
///
/// Registered on every tab's stack by `journeyDestinations()`, so the browser,
/// a category page or a search result can push one with
/// `NavigationLink(value:)`. Each case maps to its page in `page`.
enum VaultRoute: Hashable {
    /// Every category, with the search field.
    case browser
    /// One category's data types.
    case category(BodyCategory)
    /// The latest value, a chart over a chosen period, and the way into the
    /// records.
    case dataType(BodyDataType)
    /// Every record of one type, newest first, grouped by day.
    case allData(BodyDataType)
    /// One of Soma's scores, or what the engine reads off a night, on the
    /// same page as a HealthKit type.
    case score(ScoreMetric)

    @ViewBuilder
    var page: some View {
        switch self {
        case .browser: BodyBrowserView()
        case .category(let category): BodyCategoryPage(category: category)
        case .dataType(let type): VaultDataTypePage(type: type)
        case .allData(let type): VaultAllDataPage(type: type)
        case .score(let score): VaultDataTypePage(subject: .score(score))
        }
    }
}
