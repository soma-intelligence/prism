//
//  ToolRoute.swift
//  Prism
//

import SwiftUI

/// The tools: circadian and sleep planners, the sun budget, aging pace, screening and strength load.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
enum ToolRoute: Hashable {
    /// Every tool in one list, grouped: the page Pulse > Explore and Track open.
    case hub
    /// What a tool reads, what it changes, and how to stop it.
    case intro(ToolKind)
    case phaseAlignment
    case caffeineWindow
    case socialJetlag
    case smartAlarm
    case sleepForecast
    case napArchitect
    case eveningClose
    case supplementWindow
    case shiftWork
    case travel
    case sunBudget
    case agingPace
    case screeningLedger
    case skinForecast
    case strengthLoad

    @ViewBuilder
    var page: some View {
        switch self {
        case .hub: ToolsHubPage()
        case .intro(let kind): ToolIntroPage(kind: kind)
        case .phaseAlignment: PhaseAlignmentPage()
        case .caffeineWindow: CaffeineWindowPage()
        case .socialJetlag: SocialJetlagPage()
        case .smartAlarm: SmartAlarmPage()
        case .sleepForecast: SleepForecastPage()
        case .napArchitect: NapArchitectPage()
        case .eveningClose: EveningClosePage()
        case .supplementWindow: SupplementWindowPage()
        case .shiftWork: ShiftWorkPage()
        case .travel: TravelPage()
        case .sunBudget: SunBudgetPage()
        case .agingPace: AgingPacePage()
        case .screeningLedger: ScreeningLedgerPage()
        case .skinForecast: SkinForecastPage()
        case .strengthLoad: StrengthLoadPage()
        }
    }
}
