//
//  WidgetIntents.swift
//  Prism
//
//  Pulls the widget package's intents into the app's App Intents metadata,
//  so a widget's drink button can run in the app's process as well as in the
//  extension's. iOS only, like the widgets.
//

#if os(iOS)
import AppIntents
import SomaWidgetKit

struct PrismWidgetIntents: AppIntentsPackage {
    nonisolated static var includedPackages: [any AppIntentsPackage.Type] {
        [SomaWidgetIntents.self]
    }
}
#endif
