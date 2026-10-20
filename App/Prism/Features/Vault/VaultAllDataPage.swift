//
//  VaultAllDataPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Every record of one data type, newest first, a day at a time, set like the
/// pages around it: an inline title over a head with the category's glyph,
/// the measure's name and its unit, then each day under a quiet eyebrow with
/// its records as rows on one card (the source's glyph and the time on the
/// leading edge, the value and its unit on the trailing edge). A record opens
/// on its sheet: when, what wrote it, and its grade.
///
/// Read a page at a time: a heart rate history runs to hundreds of thousands
/// of records, and the next page is asked for only when the last row comes
/// on screen. The list stays lazy row by row, so a day of a thousand
/// readings draws only what is on screen: each row draws its own share of
/// the day's card.
struct VaultAllDataPage: View {
    let type: BodyDataType

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var records: [HealthReading] = []
    @State private var seen: Set<HealthReading> = []
    @State private var isLoading = false
    @State private var isFinished = false
    @State private var selected: VaultRecord?

    private var category: BodyCategory? { BodyCategory.containing(type) }
    private var title: String { MetricPageWords.title(identifier: type.metric.identifier, fallback: type.title) }
    private var unit: String? { MetricPageWords.unit(identifier: type.metric.identifier, fallback: type.metric.unit.shortLabel) }

    var body: some View {
        let metrics = theme.metrics
        let lines = VaultRecordLines.make(records, calendar: .current)

        SomaPageScroll {
            LazyVStack(alignment: .leading, spacing: 0) {
                VaultAllDataHead(category: category, title: title, unit: unit)
                    .padding(.bottom, metrics.leadSpacing)

                ForEach(lines) { line in
                    switch line.kind {
                    case .day(let day):
                        Text(VaultWords.day(day))
                            .somaFont(theme.typography.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, line.index == 0 ? 0 : metrics.leadSpacing)
                            .padding(.bottom, metrics.cardSpacing)
                    case .record(let reading, let place):
                        Button { selected = VaultRecord(reading: reading) } label: {
                            VaultRecordRow(reading: reading, metric: type.metric, place: place)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if reading == records.last { Task { await loadMore() } }
                        }
                    }
                }

                if records.isEmpty && isFinished {
                    Text("No readings yet")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .frame(maxWidth: .infinity)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, metrics.leadSpacing)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(category?.aspect)
        .navigationTitle("All readings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
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
    }
}

/// The head of every reading: the category's line glyph on its aspect's
/// tinted square, the measure's name, and the unit its values are in.
private struct VaultAllDataHead: View {
    let category: BodyCategory?
    let title: String
    let unit: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = category?.aspect.map { theme.aspects[$0].identity.color }

        HStack(spacing: metrics.moveRowGap) {
            Image(systemName: category?.lineSymbol ?? "archivebox")
                .font(.system(size: metrics.aspectBadgeGlyph * 0.82, weight: .regular))
                .foregroundStyle(hue ?? colors.inkSecondary.color)
                .frame(width: metrics.aspectBadgeSide, height: metrics.aspectBadgeSide)
                .background(RoundedRectangle(cornerRadius: metrics.aspectBadgeCornerRadius, style: .continuous)
                    .fill(hue.map { $0.opacity(metrics.aspectBadgeTint) } ?? colors.surfaceRecessed.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: metrics.readingRowLineGap) {
                Text(title)
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(unit.map { String(localized: "Newest first, in \($0)") } ?? String(localized: "Newest first"))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .padding(.top, metrics.scoreHeroTopPadding)
        .accessibilityElement(children: .combine)
    }
}

/// The records as the list lays them out: a day's eyebrow, then its records,
/// each knowing where it sits on the day's card so it can draw its share of
/// the card's corners and the hairline above it.
struct VaultRecordLines {
    enum Place: Equatable, Sendable {
        case only, first, middle, last

        var isFirst: Bool { self == .only || self == .first }
        var isLast: Bool { self == .only || self == .last }
    }

    struct Line: Identifiable, Equatable {
        enum Kind: Equatable {
            case day(Date)
            case record(HealthReading, Place)
        }

        let index: Int
        let kind: Kind

        var id: String {
            switch kind {
            case .day(let day): "day-\(day.timeIntervalSinceReferenceDate)"
            case .record(let reading, _):
                "\(reading.start.timeIntervalSinceReferenceDate)-\(reading.end.timeIntervalSinceReferenceDate)-\(reading.value)-\(reading.source ?? "")-\(index)"
            }
        }
    }

    /// Records newest first, split by the day each began.
    static func make(_ records: [HealthReading], calendar: Calendar) -> [Line] {
        var lines: [Line] = []
        var start = 0
        while start < records.count {
            let day = calendar.startOfDay(for: records[start].start)
            var end = start
            while end + 1 < records.count, calendar.isDate(records[end + 1].start, inSameDayAs: day) { end += 1 }
            lines.append(Line(index: lines.count, kind: .day(day)))
            for position in start...end {
                let place: Place = start == end ? .only : position == start ? .first : position == end ? .last : .middle
                lines.append(Line(index: lines.count, kind: .record(records[position], place)))
            }
            start = end + 1
        }
        return lines
    }
}

/// One record as one line: the glyph of what took it and the time on the
/// leading edge, the value and its unit on the trailing edge. It draws its
/// own share of the day's card, so the list can stay lazy row by row.
struct VaultRecordRow: View {
    let reading: HealthReading
    let metric: HealthMetric
    var place: VaultRecordLines.Place = .only

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let formatted = VaultFormat.value(of: reading, metric: metric)
        let radius = metrics.browseGroupCornerRadius
        let top = place.isFirst ? radius : 0
        let bottom = place.isLast ? radius : 0

        HStack(spacing: metrics.browseRowSpacing) {
            Image(systemName: VaultRecordRow.symbol(reading) ?? "circle.dotted")
                .font(.system(size: metrics.browseChevronSize * 1.2, weight: .regular))
                .foregroundStyle(colors.inkSecondary.color)
                .frame(width: metrics.browseGlyphColumn * 0.6)
                .accessibilityHidden(true)
            Text(VaultWords.time(start: reading.start, end: reading.end))
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
            Spacer(minLength: metrics.browseRowSpacing)
            HStack(alignment: .firstTextBaseline, spacing: metrics.metricHeroSpacing) {
                Text(formatted.value)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
                if let unit = formatted.unit {
                    Text(unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: metrics.browseRowMinHeight)
        .overlay(alignment: .top) {
            if !place.isFirst {
                Rectangle()
                    .fill(colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity))
                    .frame(height: 0.5)
                    .padding(.leading, metrics.browseRowPadding + metrics.browseGlyphColumn * 0.6 + metrics.browseRowSpacing)
            }
        }
        .background(
            colors.surface.color,
            in: UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                       bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text([formatted.unit, reading.source].compactMap { $0 }.joined(separator: ", ")))
    }

    /// The glyph of what wrote a record: a watch, a phone, a ring, a hand.
    static func symbol(_ reading: HealthReading) -> String? {
        MetricPageWords.symbol(VaultMasterReader.Origin(
            name: reading.source ?? "", device: reading.device, count: 1, quality: ReadingQuality.grade(reading)
        ))
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
