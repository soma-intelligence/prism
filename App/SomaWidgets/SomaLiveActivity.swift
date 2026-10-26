//
//  SomaLiveActivity.swift
//  SomaWidgets
//
//  Every Soma Live Activity: wind down, nap, cardio test, meeting. One
//  attributes type, laid out by kind on the lock screen and in the Dynamic
//  Island.
//

import ActivityKit
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit
import SomaWidgetUI

struct SomaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SomaActivityAttributes.self) { context in
            SomaActivityBanner(kind: context.attributes.kind, content: context.state)
                .activityBackgroundTint(SomaColorValue(SomaTheme.standard.colors.surface.dark).color)
                .activitySystemActionForegroundColor(SomaColorValue(SomaTheme.standard.colors.inkPrimary.dark).color)
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            let state = context.state
            let metrics = SomaTheme.standard.metrics
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SomaActivityGlyph(kind, alert: state.alert)
                        .somaFont(SomaTheme.standard.typography.headline)
                        .padding(.leading, metrics.widgetRowSpacing)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // A timer text is as wide as its longest reading, which
                    // truncates in the island's trailing slot: a set width.
                    SomaActivityClock(state, role: \.title)
                        .minimumScaleFactor(0.6)
                        .frame(width: metrics.widgetSideColumn, alignment: .trailing)
                        .padding(.trailing, metrics.widgetRowSpacing)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.center) {
                    SomaActivityTitle(state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: metrics.widgetRowGap) {
                        SomaActivityReading(state)
                        SomaActivityProgress(kind, state)
                    }
                    .padding(.horizontal, metrics.widgetRowSpacing)
                    .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                SomaActivityGlyph(kind, alert: state.alert)
                    .environment(\.colorScheme, .dark)
            } compactTrailing: {
                SomaActivityClock(state, role: \.captionValue)
                    .frame(maxWidth: metrics.widgetRowLabelColumn)
                    .environment(\.colorScheme, .dark)
            } minimal: {
                SomaActivityGlyph(kind, alert: state.alert)
                    .environment(\.colorScheme, .dark)
            }
            .keylineTint(SomaTheme.standard.aspects[kind.aspect].identity.color)
            .widgetURL(link(kind))
        }
    }

    /// Where a tap on the activity lands.
    private func link(_ kind: SomaActivityKind) -> URL? {
        switch kind {
        case .windDown, .nap: URL(string: "soma://sleep")
        case .meeting: URL(string: "soma://meetings")
        case .cardioTest: nil
        }
    }
}
