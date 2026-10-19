//
//  StrainWidget.swift
//  SomaWidgets
//
//  Energy now over the curve since bedtime, and stress today. Redrawn every
//  quarter hour so the dot that marks now moves along the curve.
//

import SwiftUI
import WidgetKit
import SomaWidgetKit
import SomaWidgetUI

struct StrainWidgetView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                StrainLarge(snapshot: entry.snapshot, now: entry.date)
            default:
                StrainMedium(snapshot: entry.snapshot, now: entry.date)
            }
        }
        .somaWidgetCanvas()
    }
}

struct StrainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.strain.rawValue, provider: SnapshotProvider(schedule: .strain)) { entry in
            StrainWidgetView(entry: entry)
        }
        .configurationDisplayName("Strain")
        .description("Energy since bedtime and stress today.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
