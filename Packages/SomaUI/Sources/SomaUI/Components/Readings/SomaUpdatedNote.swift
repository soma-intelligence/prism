//
//  SomaUpdatedNote.swift
//  SomaUI
//

import SwiftUI

/// One quiet line saying when the numbers on screen were read: "Updated 3
/// hours ago". A page shows it only while it draws numbers kept from an
/// earlier read that are old enough to matter, and drops it once a fresh
/// read lands.
public struct SomaUpdatedNote: View {
    private let date: Date
    private let now: Date

    @Environment(\.somaTheme) private var theme

    public init(_ date: Date, now: Date = .now) {
        self.date = date
        self.now = now
    }

    public var body: some View {
        let ago = Self.ago(date, now: now)
        HStack(spacing: theme.metrics.trendMarkSpacing) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Updated \(ago)")
        }
        .somaFont(theme.typography.caption)
        .foregroundStyle(theme.colors.inkSecondary.color)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// "3 hours ago", "yesterday": the largest whole unit back from `now`.
    nonisolated static func ago(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

/// The top of a page that may open on kept numbers: the quiet "Updated"
/// line, then the page's first block.
///
/// The line's room is decided once, when the page opens: kept numbers old
/// enough to mention reserve it, and it stays reserved after the fresh read
/// lands and the line fades out. So nothing below moves while the numbers
/// roll to the fresh read. The content draws its own top padding, the
/// theme's ``SomaMetrics/heroTopPadding``; while the line is there, the line
/// takes that padding instead.
public struct SomaUpdatedHeader<Content: View>: View {
    private let updated: Date?
    private let content: Content

    @State private var reserves: Bool
    @State private var shown: Date?
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter updated: when the kept numbers on screen were read, or nil
    ///   once they are fresh (or never were kept).
    public init(_ updated: Date?, @ViewBuilder content: () -> Content) {
        self.updated = updated
        self.content = content()
        _reserves = State(initialValue: updated != nil)
        _shown = State(initialValue: updated)
    }

    public var body: some View {
        let metrics = theme.metrics
        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            if reserves {
                SomaUpdatedNote(updated ?? shown ?? .now)
                    .opacity(updated == nil ? 0 : 1)
                    .accessibilityHidden(updated == nil)
                    .padding(.top, metrics.heroTopPadding)
            }
            content
                .padding(.top, reserves ? -metrics.heroTopPadding : 0)
        }
        .animation(reduceMotion ? nil : theme.motion.updatedNoteFade, value: updated == nil)
        .onChange(of: updated) { _, new in
            guard let new else { return }
            shown = new
            reserves = true
        }
    }
}

#Preview("Updated note") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(alignment: .leading, spacing: 12) {
            SomaUpdatedNote(.now.addingTimeInterval(-3 * 3_600))
            SomaUpdatedNote(.now.addingTimeInterval(-30 * 3_600))
            SomaUpdatedHeader(.now.addingTimeInterval(-3 * 3_600)) {
                SomaStatRow([SomaStat("HRV", value: "58", unit: "ms")])
                    .padding(.top, SomaTheme.standard.metrics.heroTopPadding)
            }
        }
        .padding()
    }
}
