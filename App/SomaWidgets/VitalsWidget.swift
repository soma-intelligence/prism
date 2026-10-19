//
//  VitalsWidget.swift
//  SomaWidgets
//
//  Resting heart rate, HRV and sleep, each with its last seven days.
//

import SwiftUI
import WidgetKit
import SomaWidgetKit
import SomaWidgetUI

struct VitalsWidgetView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VitalsSmall(snapshot: entry.snapshot, now: entry.date)
            case .systemLarge:
                VitalsLarge(snapshot: entry.snapshot, now: entry.date)
            case .accessoryRectangular:
                VitalsRectangular(snapshot: entry.snapshot, now: entry.date)
            case .accessoryInline:
                VitalsInline(snapshot: entry.snapshot, now: entry.date)
            default:
                VitalsMedium(snapshot: entry.snapshot, now: entry.date)
            }
        }
        .somaWidgetCanvas()
    }
}

struct VitalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.vitals.rawValue, provider: SnapshotProvider()) { entry in
            VitalsWidgetView(entry: entry)
        }
        .configurationDisplayName("Vitals")
        .description("Resting heart rate, HRV and sleep.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
