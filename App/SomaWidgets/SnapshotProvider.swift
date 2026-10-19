//
//  SnapshotProvider.swift
//  SomaWidgets
//
//  Reads the snapshot Prism writes to the App Group and hands it to the
//  widgets. The gallery and the placeholder draw the shared fixture at its own
//  date, so its curve and its age read the same everywhere.
//

import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SomaWidgetSnapshot?
    /// Drinks logged from the widget and not yet drained by the app. Only the
    /// Log widget reads them.
    var pending: [LogItem] = []

    /// The gallery and placeholder entry: the fixture, at the fixture's date.
    static let placeholder = SnapshotEntry(
        date: SomaWidgetSnapshot.placeholder.generatedAt,
        snapshot: .placeholder
    )

    /// What the app last wrote, as of `now`. Nil snapshot draws "Open Soma".
    static func current(now: Date, readsInbox: Bool = false) -> SnapshotEntry {
        SnapshotEntry(
            date: now,
            snapshot: SnapshotStore.shared?.read(),
            pending: readsInbox ? (LogInbox.shared?.pending() ?? []) : []
        )
    }
}

/// One timeline for every snapshot widget. Most redraw half hourly; Strain
/// redraws every quarter hour so the dot that marks now moves along the curve.
struct SnapshotProvider: TimelineProvider {
    enum Schedule: Sendable {
        /// One entry now, the next timeline in 30 minutes.
        case halfHourly
        /// `StrainTimeline.entryDates(from:)`, the next timeline after the last.
        case strain
    }

    /// How often the app republishes on its own; the widget asks again then.
    static let refresh: TimeInterval = 30 * 60

    var schedule: Schedule = .halfHourly
    var readsInbox = false

    func placeholder(in context: Context) -> SnapshotEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .current(now: .now, readsInbox: readsInbox))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Self.timeline(now: .now, schedule: schedule, readsInbox: readsInbox))
    }

    static func timeline(now: Date, schedule: Schedule, readsInbox: Bool) -> Timeline<SnapshotEntry> {
        let base = SnapshotEntry.current(now: now, readsInbox: readsInbox)
        switch schedule {
        case .halfHourly:
            return Timeline(entries: [base], policy: .after(now.addingTimeInterval(refresh)))
        case .strain:
            let dates = StrainTimeline.entryDates(from: now)
            let entries = dates.map { SnapshotEntry(date: $0, snapshot: base.snapshot, pending: base.pending) }
            return Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(refresh)))
        }
    }
}

/// The widget's background: the SomaUI canvas (white or near black) on the
/// home screen, nothing on the lock screen, where the system draws its own.
struct SomaWidgetCanvas: ViewModifier {
    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                Color.clear
            default:
                theme.colors.canvas.color
            }
        }
    }
}

extension View {
    func somaWidgetCanvas() -> some View {
        modifier(SomaWidgetCanvas())
    }
}
