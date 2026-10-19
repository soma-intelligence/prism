//
//  ToolsSmartAlarmPriority.swift
//  Prism
//
//  What the user asks the alarm to optimise. A GOAL, not a mode: the seven
//  steps of SmartWakeEngine all run, in the same order, whatever the value.
//  The goal only reweights the three levers the engine already has (the
//  extension budget, the tolerance around the anchor, the authority of the
//  circadian floor). A goal that skipped a step would repeat the mistake the
//  old window/optimised mode pair made.
//
//  `balanced` is the default and is EXACTLY the behaviour from before the
//  setting existed, weight for weight.
//
//  No goal can touch the hard bound: `SmartWakeEngine.plan(_:).ring` NEVER
//  passes `inputs.latest`, because step 7 clamps after everything else.
//
//  The raw value is persisted inside the settings JSON, so renaming a case
//  makes a stored setting read back as absent.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmPriority: String, Codable, CaseIterable, Sendable {
        /// The historical setting: debt, autonomic state, load and habit each
        /// weigh their share.
        case balanced
        /// Catch up on missed sleep: debt drives the extension budget and the
        /// habit pulls less hard so it can show.
        case clearDebt
        /// Re-sync on location: the circadian floor leads, the habitual wake
        /// time (from the home time zone) no longer does.
        case travel
        /// Ring at the same time: the anchor and regularity lead, debt barely
        /// weighs.
        case regularity
    }
}
