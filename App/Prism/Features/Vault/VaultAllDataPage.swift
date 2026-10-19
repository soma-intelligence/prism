//
//  VaultAllDataPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Every record of one data type, newest first, grouped by the day it was
/// taken: the value, when, where it came from, and its grade as marks.
///
/// Read a page at a time: a heart rate history runs to hundreds of thousands
/// of records, and the next page is asked for only when the last day comes
/// on screen.
struct VaultAllDataPage: View {
    let type: BodyDataType

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var records: [HealthReading] = []
    @State private var seen: Set<HealthReading> = []
    @State private var isLoading = false
    @State private var isFinished = false
    @State private var selected: VaultRecord?
    @State private var days: [VaultDay] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.metrics.cardSpacing * 1.5) {
                if let unit = type.metric.unit.shortLabel {
                    Text(unit)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .padding(.horizontal, theme.metrics.browseRowPadding)
                }
                // One continuous list, as Apple Health's: no day headers, no
                // boxes per day. The date rides on each row's trailing edge.
                LazyVStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element) { index, reading in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
                                .frame(height: 0.5)
                                .padding(.leading, theme.metrics.browseRowPadding)
                        }
                        Button { selected = VaultRecord(reading: reading) } label: {
                            VaultRecordRow(reading: reading, metric: type.metric)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index == records.count - 1 { Task { await loadMore() } }
                        }
                    }
                }
                .background(
                    theme.colors.surface.color,
                    in: .rect(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                )

                if records.isEmpty && isFinished {
                    Text("No records")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .frame(maxWidth: .infinity)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(theme.metrics.pagePadding)
            .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle("All Recorded Data")
        .task { if records.isEmpty { await loadMore() } }
        .sheet(item: $selected) { record in
            VaultRecordSheet(reading: record.reading, metric: type.metric)
        }
    }

    private func loadMore() async {
        guard !isLoading, !isFinished else { return }
        isLoading = true
        defer { isLoading = false }

        guard let source = await health.prepare([type.metric.identifier]) else {
            isFinished = true
            return
        }
        let cursor = records.last?.end ?? .distantFuture
        let page = (try? await VaultReader(source: source).page(type.metric, before: cursor, seen: seen)) ?? []
        // A page with nothing new is the end: either the store ran out, or
        // every record left shares one end date with ones already shown.
        if page.isEmpty { isFinished = true }
        records.append(contentsOf: page)
        seen.formUnion(page)
        days = VaultBucketing.byDay(records, calendar: .current).map { group in
            VaultDay(day: group.day, records: group.readings.map { VaultRecord(reading: $0) })
        }
    }
}

/// One record as one line, the way Apple Health lists them: the value on the
/// leading edge, the time on the trailing edge, nothing else. The unit is
/// written once above the list; the source, the device and the grade are a tap
/// away on the record's sheet.
struct VaultRecordRow: View {
    let reading: HealthReading
    let metric: HealthMetric

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let formatted = VaultFormat.value(of: reading, metric: metric)

        HStack(spacing: theme.metrics.browseRowSpacing) {
            Text(formatted.value)
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Spacer(minLength: theme.metrics.browseRowSpacing)
            Text(VaultRecordRow.when(reading.start))
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .padding(.horizontal, theme.metrics.browseRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: theme.metrics.browseRowMinHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text([formatted.unit, reading.source].compactMap { $0 }.joined(separator: ", ")))
    }

    /// The time, with the day beside it only when the day is not today:
    /// "10:48", "Yesterday 10:48", "Sep 26 10:48", and the year once it is
    /// not this one.
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday") + " " + time
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
        return day + " " + time
    }

    /// The time it was taken, or the span when it lasted.
    static func time(_ reading: HealthReading) -> String {
        let start = reading.start.formatted(date: .omitted, time: .shortened)
        guard reading.end.timeIntervalSince(reading.start) >= 60 else { return start }
        return start + " to " + reading.end.formatted(date: .omitted, time: .shortened)
    }
}

/// A day's records, keyed by the day.
private struct VaultDay: Identifiable {
    let day: Date
    let records: [VaultRecord]
    var id: Date { day }
}

/// A record with an identity a list and a sheet can hold on to.
struct VaultRecord: Identifiable, Hashable {
    let reading: HealthReading
    var id: HealthReading { reading }
}

#if DEBUG
#Preview("All data") {
    NavigationStack {
        VaultAllDataPage(type: BodyCatalog.categories[4].types[0])
    }
    .environment(HealthDashboard(source: VaultPreviewSource()))
}
#endif
