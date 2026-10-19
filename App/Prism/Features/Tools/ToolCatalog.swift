//
//  ToolCatalog.swift
//  Prism
//

import SomaUI

/// Every tool, what it is called, which aspect it wears and where it sits in
/// the hub.
///
/// The list is the set drawn for Soma; others (Peak Window, the aroma kit, the
/// programs) are not here yet.
enum ToolKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case phaseAlignment, sleepForecast, smartAlarm, socialJetlag, napArchitect
    case caffeineWindow, supplementWindow
    case eveningClose, travel, shiftWork
    case sunBudget, skinForecast
    case agingPace, strengthLoad, screeningLedger

    var id: String { rawValue }

    /// The hub's groups, in order.
    enum Group: String, CaseIterable, Identifiable {
        case sleep = "Sleep and body clock"
        case food = "Food and energy"
        case evenings = "Evenings and travel"
        case skin = "Skin and sun"
        case longRun = "The long run"

        var id: String { rawValue }

        var tools: [ToolKind] { ToolKind.allCases.filter { $0.group == self } }
    }

    var title: String {
        switch self {
        case .phaseAlignment: "Phase Alignment"
        case .sleepForecast: "Sleep Forecast"
        case .smartAlarm: "Smart Alarm"
        case .socialJetlag: "Social Jetlag"
        case .napArchitect: "Nap Architect"
        case .caffeineWindow: "Caffeine Window"
        case .supplementWindow: "Supplement Window"
        case .eveningClose: "Evening Close"
        case .travel: "Travel"
        case .shiftWork: "Shift Work Reset"
        case .sunBudget: "Sun Budget"
        case .skinForecast: "Skin Forecast"
        case .agingPace: "Aging Pace"
        case .strengthLoad: "Strength Load"
        case .screeningLedger: "Screening Ledger"
        }
    }

    var group: Group {
        switch self {
        case .phaseAlignment, .sleepForecast, .smartAlarm, .socialJetlag, .napArchitect: .sleep
        case .caffeineWindow, .supplementWindow: .food
        case .eveningClose, .travel, .shiftWork: .evenings
        case .sunBudget, .skinForecast: .skin
        case .agingPace, .strengthLoad, .screeningLedger: .longRun
        }
    }

    var aspect: SomaAspect {
        switch self {
        case .phaseAlignment, .sleepForecast, .smartAlarm, .socialJetlag, .napArchitect, .travel, .shiftWork: .sleep
        case .caffeineWindow, .supplementWindow: .gut
        case .eveningClose: .mind
        case .sunBudget, .skinForecast, .agingPace: .body
        case .strengthLoad: .activity
        case .screeningLedger: .heart
        }
    }

    /// The page the tool opens on.
    var route: ToolRoute {
        switch self {
        case .phaseAlignment: .phaseAlignment
        case .sleepForecast: .sleepForecast
        case .smartAlarm: .smartAlarm
        case .socialJetlag: .socialJetlag
        case .napArchitect: .napArchitect
        case .caffeineWindow: .caffeineWindow
        case .supplementWindow: .supplementWindow
        case .eveningClose: .eveningClose
        case .travel: .travel
        case .shiftWork: .shiftWork
        case .sunBudget: .sunBudget
        case .skinForecast: .skinForecast
        case .agingPace: .agingPace
        case .strengthLoad: .strengthLoad
        case .screeningLedger: .screeningLedger
        }
    }

    // MARK: - The intro page

    /// What a tool reads, and where from.
    var reads: [(name: String, source: String)] {
        switch self {
        case .phaseAlignment: [("Bed and wake times", "Health"), ("Daylight outside", "Watch"), ("Caffeine", "Health")]
        case .sleepForecast: [("Your recent nights", "Health"), ("Caffeine", "Health"), ("Heart and breathing", "Watch")]
        case .smartAlarm: [("Your recent nights", "Health"), ("Sleep stages", "Watch")]
        case .socialJetlag: [("Bed and wake times", "Health")]
        case .napArchitect: [("Your recent nights", "Health"), ("Energy and stress", "Soma")]
        case .caffeineWindow: [("Caffeine logged", "Health"), ("Cups logged here", "Soma"), ("Your bedtime", "Health")]
        case .supplementWindow: [("Your supplements", "Soma"), ("Your wake time", "Health")]
        case .eveningClose: [("Your sleep window", "Health"), ("Stress peaks", "Watch")]
        case .travel: [("Your trip", "Soma"), ("Your sleep window", "Health")]
        case .shiftWork: [("Your shift", "Soma"), ("Your wake time", "Health")]
        case .sunBudget: [("UV where you are", "Weather"), ("Time in daylight", "Watch"), ("Your skin type", "Soma")]
        case .skinForecast: [("Weather and air", "Weather")]
        case .agingPace: [("VO₂ max and resting heart", "Health"), ("Date of birth", "Health")]
        case .strengthLoad: [("Strength sessions", "Health"), ("Sets logged here", "Soma")]
        case .screeningLedger: [("Your age", "Health"), ("What you record", "Soma")]
        }
    }

    /// The first sentence of what it changes, in ink, then the rest.
    var changes: (lead: String, rest: String) {
        switch self {
        case .smartAlarm:
            ("It sets an alarm.", "It rings once, inside the window you choose, and never later than your wake by time.")
        case .eveningClose:
            ("Nothing on its own yet.", "It keeps your closing time and counts the evenings you kept it; closing apps needs Screen Time access Soma does not have yet.")
        default:
            ("Nothing on its own.", "It reads, works the numbers out and suggests. Anything that buzzes is something you switched on.")
        }
    }

    /// How it starts and stops, the first sentence in ink.
    var startStop: (lead: String, rest: String) {
        switch self {
        case .phaseAlignment, .socialJetlag:
            ("It scores after seven nights of sleep timing.", "Switch it off here. Nothing is deleted from Health.")
        case .sleepForecast, .napArchitect, .smartAlarm:
            ("It needs seven recorded nights to know your usual.", "Switch it off here. Nothing is deleted from Health.")
        case .sunBudget, .skinForecast:
            ("It needs the weather where you are.", "Until Soma has a weather source, the numbers wait as dashes.")
        default:
            ("It starts from what you give it.", "Switch it off here; what you entered stays on this phone.")
        }
    }

    var science: (text: String, citation: String) {
        switch self {
        case .phaseAlignment:
            ("Circadian alignment is how closely your days track your internal clock. Wider gaps between work-day and free-day sleep timing go with poorer metabolic and mood outcomes.",
             "Roenneberg et al., 2003, Journal of Biological Rhythms")
        case .socialJetlag:
            ("Social jetlag is the gap between mid-sleep on work nights and on free nights. Each hour of it goes with a higher risk of being overweight.",
             "Roenneberg et al., 2012, Current Biology")
        case .caffeineWindow:
            ("Caffeine halves in about five hours. A dose six hours before bed still cut sleep by more than an hour in the lab.",
             "Drake et al., 2013, Journal of Clinical Sleep Medicine")
        case .sleepForecast:
            ("Tonight's sleep follows the last few nights, the caffeine still on board and how late the day ran.",
             "Gardiner et al., 2023, Sleep Medicine Reviews")
        case .napArchitect:
            ("A short nap in the early afternoon dip restores alertness without reaching deep sleep.",
             "Brooks and Lack, 2006, Sleep")
        case .smartAlarm:
            ("Waking from light sleep leaves less grogginess than waking from deep sleep.",
             "Tassi and Muzet, 2000, Sleep Medicine Reviews")
        case .supplementWindow:
            ("Fat-soluble vitamins absorb better with a meal; magnesium is often taken in the evening.",
             "Dawson-Hughes et al., 2015, Journal of the Academy of Nutrition and Dietetics")
        case .eveningClose:
            ("Screens and work late in the evening delay sleep and shorten it.",
             "Chang et al., 2015, PNAS")
        case .travel:
            ("Shifting sleep toward the destination before flying, and timing light after it, shortens jet lag.",
             "Eastman and Burgess, 2009, Sleep Medicine Clinics")
        case .shiftWork:
            ("An anchor sleep that stays put, a nap before a first night and light timed on the way home ease night work.",
             "Smith and Eastman, 2012, Nature and Science of Sleep")
        case .sunBudget:
            ("The time to redden depends on the UV index and your skin type; SPF multiplies it when applied properly.",
             "Fitzpatrick, 1988, Archives of Dermatology")
        case .skinForecast:
            ("Dry air, UV and pollution each strain the skin barrier.",
             "Krutmann et al., 2017, Journal of Dermatological Science")
        case .agingPace:
            ("Fitness and heart signals read against your calendar age give a pace of aging.",
             "Nes et al., 2013, Medicine and Science in Sports and Exercise")
        case .strengthLoad:
            ("Strength builds when load rises gradually, inside a band that avoids sudden spikes.",
             "Schoenfeld et al., 2017, Journal of Sports Sciences")
        case .screeningLedger:
            ("Cadences follow the United States Preventive Services Task Force.",
             "USPSTF recommendations, 2024")
        }
    }
}
