//
//  LabRoute.swift
//  Prism
//

import SwiftUI

/// The Body lens's lab pages: biological age, the blood panel, risk, the ledger, measurements, skin and the body readings.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
enum LabRoute: Hashable {
    /// Biological age from the blood panel and Health.
    case biologicalAge
    /// The latest blood panel, marker by marker.
    case bloodPanel
    /// One marker over every panel, by catalog id ("apoB").
    case marker(String)
    /// PREVENT's ten year risk and what it is built from.
    case risk
    /// Minutes earned and spent, day by day.
    case ledger
    /// Tape measurements over time.
    case measurements
    /// The face scan's skin indices.
    case skin
    case weight
    case bloodPressure
    case leanMass
    case glucose

    @ViewBuilder
    var page: some View {
        switch self {
        case .biologicalAge: BiologicalAgePage()
        case .bloodPanel: BloodPanelPage()
        case .marker(let id): BloodMarkerPage(markerID: id)
        case .risk: CardiometabolicRiskPage()
        case .ledger: LongevityLedgerPage()
        case .measurements: BodyMeasurementsPage()
        case .skin: SkinReportPage()
        case .weight: WeightPage()
        case .bloodPressure: BloodPressurePage()
        case .leanMass: LeanMassPage()
        case .glucose: BloodGlucosePage()
        }
    }
}
