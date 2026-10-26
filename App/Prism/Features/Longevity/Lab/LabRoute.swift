//
//  LabRoute.swift
//  Prism
//

import SwiftUI

/// The Body lens's lab pages: biological age, the blood panel, urine, stool, genome and functional tests, risk, the ledger, measurements, skin and the body readings.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
enum LabRoute: Hashable {
    /// Biological age from the blood panel and Health.
    case biologicalAge
    /// The latest blood panel, marker by marker.
    case bloodPanel
    /// The latest urine test: a lab report or a dipstick read by the camera.
    case urine
    /// What a 23andMe or AncestryDNA file says about a few variants.
    case genome
    /// The latest stool test: a lab report or a microbiome kit.
    case stool
    /// Imaging and functional tests: DEXA, a lab VO2 max, carotid
    /// ultrasound, calcium score, spirometry and grip strength.
    case functional
    /// One of those tests over every result.
    case functionalKind(FunctionalTestKind)
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
    /// A continuous glucose monitor's fortnight: time in range, the day,
    /// the hourly profile and the meals. Explains what fills it when no
    /// monitor writes to Health.
    case cgm

    @ViewBuilder
    var page: some View {
        switch self {
        case .biologicalAge: BiologicalAgePage()
        case .bloodPanel: BloodPanelPage()
        case .urine: UrinePanelPage()
        case .genome: GenomePage()
        case .stool: StoolPanelPage()
        case .functional: FunctionalResultsPage()
        case .functionalKind(let kind): FunctionalKindPage(kind: kind)
        case .marker(let id): BloodMarkerPage(markerID: id)
        case .risk: CardiometabolicRiskPage()
        case .ledger: LongevityLedgerPage()
        case .measurements: BodyMeasurementsPage()
        case .skin: SkinReportPage()
        case .weight: WeightPage()
        case .bloodPressure: BloodPressurePage()
        case .leanMass: LeanMassPage()
        case .glucose: BloodGlucosePage()
        case .cgm: BloodGlucosePage(opensMonitor: true)
        }
    }
}
