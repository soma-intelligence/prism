//
//  JourneyDestinations.swift
//  Prism
//

import SwiftUI

extension View {
    /// Registers every page family on the stack this is applied to.
    ///
    /// Each tab's `NavigationStack` applies it once, so a route pushed from any
    /// tab lands on its page, zooming out of the tile that opened it when that
    /// tile was a `TileLink`.
    func journeyDestinations() -> some View {
        self
            .navigationDestination(for: HomeRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: ScoreRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: LabRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: MetricRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: MindRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: TrackRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: GlobalRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: ToolRoute.self) { $0.page.zoomDestination($0) }
            .navigationDestination(for: VaultRoute.self) { $0.page.zoomDestination($0) }
    }
}
