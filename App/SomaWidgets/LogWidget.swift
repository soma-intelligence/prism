//
//  LogWidget.swift
//  SomaWidgets
//
//  Water and coffee logged with one tap, without opening the app; mood and
//  meal open the app on their own sheet. The provider adds the inbox's
//  pending drinks, so a tap shows in the tally at once.
//

import SwiftUI
import WidgetKit
import SomaWidgetKit
import SomaWidgetUI

struct LogWidgetView: View {
    let entry: SnapshotEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                LogSmall(snapshot: entry.snapshot, pending: entry.pending, now: entry.date)
            case .systemLarge:
                LogLarge(snapshot: entry.snapshot, pending: entry.pending, now: entry.date)
            case .accessoryCircular:
                LogCircular(snapshot: entry.snapshot, pending: entry.pending, now: entry.date)
            default:
                LogMedium(snapshot: entry.snapshot, pending: entry.pending, now: entry.date)
            }
        }
        .somaWidgetCanvas()
    }
}

struct LogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.log.rawValue, provider: SnapshotProvider(readsInbox: true)) { entry in
            LogWidgetView(entry: entry)
        }
        .configurationDisplayName("Log")
        .description("Water and coffee in one tap, mood and meals in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular])
    }
}
