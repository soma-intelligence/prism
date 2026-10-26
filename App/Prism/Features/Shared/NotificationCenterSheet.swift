//
//  NotificationCenterSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the bell opens: what Soma sent and what it found, Today and Earlier,
/// newest first. A tap opens where the notification points; a swipe clears
/// it. The next reminder sits on top, so an empty inbox still says something.
struct NotificationCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var notifications = SomaNotifications.shared

    var body: some View {
        NavigationStack {
            List {
                upNext
                let sections = notifications.sections
                if sections.today.isEmpty && sections.earlier.isEmpty {
                    empty
                } else {
                    group("Today", sections.today)
                    group("Earlier", sections.earlier)
                }
            }
            .softScrollEdges()
            .modifier(InboxListStyle())
            .scrollContentBackground(.hidden)
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle("Notifications")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { $0.page }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    NavigationLink(value: SettingsRoute.notifications) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                    .accessibilityLabel("Notification settings")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                    .accessibilityLabel("Close notifications")
                }
            }
            .task {
                await notifications.syncDelivered()
                await notifications.refreshAuthorization()
            }
            .onDisappear { notifications.markAllRead() }
        }
        .presentationBackground(theme.colors.canvas.color)
    }

    /// The next reminder, or why there is none.
    @ViewBuilder
    private var upNext: some View {
        let metrics = theme.metrics
        Group {
            if let next = notifications.next {
                let (item, date) = next
                HStack(spacing: metrics.browseRowSpacing) {
                    SettingsGlyph(symbol: item.kind.symbol)
                    VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                        Text("Up next")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                        Text(item.title)
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                    Spacer(minLength: metrics.browseRowSpacing)
                    Text(Self.when(date))
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .accessibilityElement(children: .combine)
            } else if notifications.authorization == .denied {
                NavigationLink(value: SettingsRoute.notifications) {
                    HStack(spacing: metrics.browseRowSpacing) {
                        SettingsGlyph(symbol: "bell.slash")
                        Text("Notifications are off")
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                }
            }
        }
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .listRowBackground(theme.colors.surface.color)
        .listRowSeparator(.hidden)
    }

    private var empty: some View {
        VStack(spacing: theme.metrics.cardHeaderSpacing) {
            Image(systemName: "bell")
                .font(.system(size: theme.metrics.browseGlyphSize * 2, weight: .light))
                .foregroundStyle(theme.colors.inkSecondary.color)
                .padding(.bottom, theme.metrics.cardSpacing)
            Text("Nothing yet")
                .somaFont(theme.typography.cardTitle)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Text("Reminders and findings land here.")
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.metrics.leadSpacing * 2)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ items: [InboxItem]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Button { open(item) } label: { row(item) }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.colors.surface.color)
                        .listRowSeparatorTint(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { notifications.remove(item.id) } label: {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !item.isRead {
                                Button { notifications.markRead(item.id) } label: {
                                    Label("Read", systemImage: "envelope.open")
                                }
                                .tint(theme.colors.inkSecondary.color)
                            }
                        }
                }
            } header: {
                Text(title)
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .textCase(nil)
            }
        }
    }

    private func row(_ item: InboxItem) -> some View {
        let metrics = theme.metrics
        return HStack(alignment: .top, spacing: metrics.browseRowSpacing) {
            SettingsGlyph(symbol: item.kind.symbol)
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .lineLimit(2)
                    Spacer(minLength: metrics.browseRowSpacing)
                    Text(Self.stamp(item.date))
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                Text(item.body)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Circle()
                .fill(item.isRead ? Color.clear : theme.colors.accent.color)
                .frame(width: metrics.chartDotDiameter, height: metrics.chartDotDiameter)
                .padding(.top, metrics.cardHeaderSpacing)
                .accessibilityHidden(true)
        }
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(item.isRead ? "" : "Unread"))
    }

    private func open(_ item: InboxItem) {
        notifications.markRead(item.id)
        guard let link = item.link, link != .inbox else { return }
        dismiss()
        // After the sheet has gone, so the one the link opens can present.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            SomaDeepLinkRouter.shared.open(link)
        }
    }

    static func stamp(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "07:30" today, "Sun 18:00" further out.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow \(time)") }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

#Preview("Notifications") {
    NotificationCenterSheet()
}

/// The inbox as cards on the canvas, the way the settings groups sit: one
/// rounded group per day, separators only between rows. The Mac has no inset
/// grouped list, so it keeps the inset one.
private struct InboxListStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content.listStyle(.inset)
#else
        content.listStyle(.insetGrouped)
#endif
    }
}
