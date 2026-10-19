//
//  FuelWidget.swift
//  SomaWidgets
//
//  Burned against eaten today, and the net.
//

import SwiftUI
import WidgetKit
import SomaWidgetKit
import SomaWidgetUI

struct FuelWidgetView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                FuelSmall(snapshot: entry.snapshot, now: entry.date)
            default:
                FuelMedium(snapshot: entry.snapshot, now: entry.date)
            }
        }
        .somaWidgetCanvas()
    }
}

struct FuelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.fuel.rawValue, provider: SnapshotProvider()) { entry in
            FuelWidgetView(entry: entry)
        }
        .configurationDisplayName("Fuel")
        .description("Burned and eaten today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
