//
//  ScoresWidget.swift
//  SomaWidgets
//
//  Sleep, recovery and strain as rings. The small size shows one score, chosen
//  when the widget is edited; recovery by default.
//

import AppIntents
import SwiftUI
import WidgetKit
import SomaWidgetKit
import SomaWidgetUI

/// The score a small Scores widget shows, as the edit sheet lists it.
enum ScoreKindEntity: String, AppEnum {
    case sleep, recovery, strain, stress

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Score"
    static let caseDisplayRepresentations: [ScoreKindEntity: DisplayRepresentation] = [
        .sleep: "Sleep",
        .recovery: "Recovery",
        .strain: "Strain",
        .stress: "Stress",
    ]

    var kind: ScoreKind {
        switch self {
        case .sleep: .sleep
        case .recovery: .recovery
        case .strain: .strain
        case .stress: .stress
        }
    }
}

struct ScoreKindIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Score"
    static let description = IntentDescription("The score the small widget shows.")

    @Parameter(title: "Score", default: .recovery)
    var kind: ScoreKindEntity

    init() {}
}

struct ScoresEntry: TimelineEntry {
    let date: Date
    let snapshot: SomaWidgetSnapshot?
    let kind: ScoreKind
}

struct ScoresProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScoresEntry {
        ScoresEntry(date: SnapshotEntry.placeholder.date, snapshot: SnapshotEntry.placeholder.snapshot, kind: .recovery)
    }

    func snapshot(for configuration: ScoreKindIntent, in context: Context) async -> ScoresEntry {
        let base: SnapshotEntry = context.isPreview ? .placeholder : .current(now: .now)
        return ScoresEntry(date: base.date, snapshot: base.snapshot, kind: configuration.kind.kind)
    }

    func timeline(for configuration: ScoreKindIntent, in context: Context) async -> Timeline<ScoresEntry> {
        let now = Date.now
        let base = SnapshotEntry.current(now: now)
        let entry = ScoresEntry(date: now, snapshot: base.snapshot, kind: configuration.kind.kind)
        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(SnapshotProvider.refresh)))
    }
}

struct ScoresWidgetView: View {
    let entry: ScoresEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                ScoresSmall(snapshot: entry.snapshot, kind: entry.kind, now: entry.date)
            case .accessoryCircular:
                ScoresCircular(snapshot: entry.snapshot, now: entry.date)
            case .accessoryRectangular:
                ScoresRectangular(snapshot: entry.snapshot, now: entry.date)
            default:
                ScoresMedium(snapshot: entry.snapshot, now: entry.date)
            }
        }
        .somaWidgetCanvas()
    }
}

struct ScoresWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.scores.rawValue, intent: ScoreKindIntent.self, provider: ScoresProvider()) { entry in
            ScoresWidgetView(entry: entry)
        }
        .configurationDisplayName("Scores")
        .description("Sleep, recovery and strain.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
