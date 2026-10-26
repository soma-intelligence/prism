//
//  GlobalTodayStrip.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The line under Pulse's headline that opens the day's app wide sheets: your
/// activity status, the calendar, and the Share studio.
///
/// One small strip, so the Pulse page only places it.
struct GlobalTodayStrip: View {
    @Environment(\.somaTheme) private var theme

    @State private var statuses = ActivityStatusStore.shared
    @State private var sheet: GlobalRoute?

    var body: some View {
        let metrics = theme.metrics
        HStack(spacing: metrics.cardSpacing) {
            Button { sheet = .activityStatus } label: {
                HStack(spacing: metrics.spaceXS) {
                    Image(systemName: statuses.current.symbol)
                        .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    Text(statuses.current.title)
                        .somaFont(theme.typography.caption)
                        .lineLimit(1)
                }
                .fixedSize()
                .foregroundStyle(theme.colors.inkPrimary.color)
                .padding(.horizontal, metrics.spaceM)
                .frame(minHeight: metrics.minimumTapTarget * 0.8)
                .background(Capsule().fill(theme.colors.surface.color))
                .frame(minHeight: metrics.minimumTapTarget)
                .contentShape(.capsule)
            }
            .buttonStyle(.somaGlassPress)
            .accessibilityLabel("Activity status")
            .accessibilityValue(Text(statuses.current.title))

            Spacer(minLength: 0)

            SomaIconButton(symbol: "calendar", style: .plain, accessibilityLabel: "Calendar") { sheet = .calendar }
            SomaIconButton(symbol: "square.and.arrow.up", style: .plain, accessibilityLabel: "Share a card") { sheet = .shareStudio }
        }
        .sheet(item: $sheet) { route in
            GlobalSheet { route.page }
        }
    }
}

#Preview("Today strip") {
    GlobalTodayStrip()
        .padding()
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
