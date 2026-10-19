//
//  TrackEntryPage.swift
//  Prism
//

import SwiftUI
import SomaUI

extension EnvironmentValues {
    /// Whether a Track entry is shown as a sheet, which gives it a Cancel, or
    /// pushed onto a stack, where the back button does that job.
    @Entry var trackInSheet = false
}

/// The frame every Track entry shares: a title, the visual control in the
/// middle, and the one action at the foot. The same view is a sheet (with
/// Cancel) when a chip opens it and a page when a link pushes it.
struct TrackEntryPage<Content: View, Footer: View, Principal: View>: View {
    let title: String
    var scrolls = true
    /// Whether the sheet closes with Done (every change already saved) rather
    /// than Cancel (nothing saved until the action).
    var closesWithDone = false
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @ViewBuilder var principal: Principal

    @Environment(\.somaTheme) private var theme
    @Environment(\.trackInSheet) private var inSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        ScrollView {
            VStack(spacing: metrics.leadSpacing * 0.75) {
                content
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, metrics.cardSpacing)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(!scrolls)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            footer
                .padding(.horizontal, metrics.pagePadding)
                .padding(.top, metrics.cardSpacing)
                .padding(.bottom, metrics.cardSpacing)
                .frame(maxWidth: metrics.pageMaxWidth)
                .frame(maxWidth: .infinity)
                .background(colors.canvas.color.ignoresSafeArea(edges: .bottom))
        }
        .background(colors.canvas.color.ignoresSafeArea())
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet && closesWithDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            } else if inSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            if Principal.self != EmptyView.self {
                ToolbarItem(placement: .principal) { principal }
            }
        }
        .tint(colors.inkPrimary.color)
    }
}

extension TrackEntryPage where Principal == EmptyView {
    init(title: String, scrolls: Bool = true, closesWithDone: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(title: title, scrolls: scrolls, closesWithDone: closesWithDone, content: content, footer: footer, principal: { EmptyView() })
    }
}

extension View {
    /// Presents a Track entry as a sheet, in its own stack so it has a title
    /// bar and a Cancel.
    func trackEntrySheet(item: Binding<TrackRoute?>) -> some View {
        sheet(item: item) { route in
            NavigationStack {
                route.page
                    .journeyDestinations()
            }
            .environment(\.trackInSheet, true)
            .presentationDragIndicator(.visible)
        }
    }
}

/// A line of reason under a control: the first sentence in ink, the rest grey,
/// centred.
struct TrackNote: View {
    let lead: String
    var rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let tail = rest.map { Text(" \($0)").foregroundStyle(colors.inkSecondary.color) } ?? Text("")
        (Text(lead).foregroundStyle(rest == nil ? colors.inkSecondary.color : colors.inkPrimary.color) + tail)
            .somaFont(theme.typography.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// Clock times the way Track writes them: 18:02, Thursday 10:00.
enum TrackClock {
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "Today, 18:02", "Yesterday, 07:30", "Monday, 21:00".
    static func dayAndTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        "\(day(date, now: now, calendar: calendar)), \(time(date))"
    }

    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if abs(date.timeIntervalSince(now)) < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide))
    }

    /// "18:00" for a clock hour with minutes as a fraction.
    static func hour(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
