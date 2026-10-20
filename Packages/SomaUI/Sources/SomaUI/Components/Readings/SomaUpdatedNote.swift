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

#Preview("Updated note") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(alignment: .leading, spacing: 12) {
            SomaUpdatedNote(.now.addingTimeInterval(-3 * 3_600))
            SomaUpdatedNote(.now.addingTimeInterval(-30 * 3_600))
        }
        .padding()
    }
}
