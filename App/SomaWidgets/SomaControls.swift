//
//  SomaControls.swift
//  SomaWidgets
//
//  Control Center buttons. Water and coffee log through the same intent as
//  the Log widget. The capture button exists in Debug builds only, like the
//  capture surface it opens.
//

import AppIntents
import SwiftUI
import WidgetKit
import SomaWidgetKit

struct LogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.logWater.rawValue) {
            ControlWidgetButton(action: LogDrinkIntent(kind: .water, ml: LogInbox.defaultMl)) {
                Label("Log water", systemImage: "drop")
            }
        }
        .displayName("Log water")
        .description("Adds a glass of water to today.")
    }
}

struct LogCoffeeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.logCoffee.rawValue) {
            ControlWidgetButton(action: LogDrinkIntent(kind: .coffee, ml: LogInbox.defaultMl)) {
                Label("Log coffee", systemImage: "cup.and.saucer")
            }
        }
        .displayName("Log coffee")
        .description("Adds a cup of coffee to today.")
    }
}


/// Pulls the widget package's intents into the extension's App Intents
/// metadata, so the drink buttons run here as well as in the app.
struct SomaWidgetsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SomaWidgetIntents.self]
    }
}
