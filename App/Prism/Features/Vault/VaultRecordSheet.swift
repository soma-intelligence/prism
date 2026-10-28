//
//  VaultRecordSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One record, set like a metric page: when it was taken over the value
/// itself, large and light, then its grade as marks with the word for it,
/// when it began and ended, and what wrote it.
struct VaultRecordSheet: View {
    let reading: HealthReading
    let metric: HealthMetric

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    struct Field: Identifiable, Equatable {
        let title: String
        let value: String
        var id: String { title }
    }

    var body: some View {
        let metrics = theme.metrics
        let formatted = VaultFormat.value(of: reading, metric: metric)
        let quality = ReadingQuality.grade(reading)
        let title = MetricPageWords.title(identifier: metric.identifier, fallback: metric.displayName)

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                    SomaMetricHero(
                        caption: Self.caption(reading),
                        value: formatted.value,
                        unit: formatted.unit,
                        meaning: nil
                    )

                    section("Quality") {
                        SomaBrowseGroup([quality.level], hasGlyphs: false) { level in
                            HStack(spacing: metrics.browseRowSpacing) {
                                VStack(alignment: .leading, spacing: metrics.readingRowLineGap) {
                                    Text(MetricPageWords.quality(level) ?? String(localized: "Not known"))
                                        .somaFont(theme.typography.body)
                                        .foregroundStyle(theme.colors.inkPrimary.color)
                                    Text(quality.reason)
                                        .somaFont(theme.typography.caption)
                                        .foregroundStyle(theme.colors.inkSecondary.color)
                                }
                                Spacer(minLength: metrics.browseRowSpacing)
                                SomaQualityMarks(filled: level.marks, of: ReadingQuality.scale)
                            }
                            .padding(.horizontal, metrics.browseRowPadding)
                            .padding(.vertical, metrics.browseRowVerticalPadding)
                            .frame(minHeight: metrics.browseRowMinHeight)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    section("When") {
                        SomaBrowseGroup(Self.when(reading), hasGlyphs: false) { field in
                            SomaBrowseRow(title: field.title, detail: field.value, opensSomething: false)
                        }
                    }

                    section("Source") {
                        SomaBrowseGroup(Self.source(reading), hasGlyphs: false) { field in
                            SomaBrowseRow(title: field.title, detail: field.value, opensSomething: false)
                        }
                    }
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.pagePadding)
            }
            .aspectWash(BodyCategory.containing(BodyDataType(metric))?.aspect)
            .navigationTitle(title)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// "Today at 10:00", "Yesterday at 23:12 to 06:48".
    static func caption(_ reading: HealthReading, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = VaultWords.day(reading.start, now: now, calendar: calendar)
        let time = VaultWords.time(start: reading.start, end: reading.end, calendar: calendar)
        return String(localized: "\(day) at \(time)")
    }

    /// When it began, when it ended and how long it ran; an instant reading
    /// gives one time and no length.
    static func when(_ reading: HealthReading, calendar: Calendar = .current) -> [Field] {
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day().hour().minute().second()
        let seconds = reading.end.timeIntervalSince(reading.start)
        guard seconds > 0 else {
            return [Field(title: String(localized: "Taken"), value: reading.start.formatted(style))]
        }
        return [
            Field(title: String(localized: "Began"), value: reading.start.formatted(style)),
            Field(title: String(localized: "Ended"), value: reading.end.formatted(style)),
            Field(title: String(localized: "Lasted"), value: VaultFormat.duration(seconds)),
        ]
    }

    /// What wrote it and on what; a field Health left empty is left out, and
    /// a record typed in says so. The app is always listed: one Health did
    /// not name reads "Unknown", in words rather than a hyphen.
    static func source(_ reading: HealthReading) -> [Field] {
        var fields: [Field] = [Field(title: String(localized: "App"), value: reading.source ?? String(localized: "Unknown"))]
        if let device = reading.device, !device.isEmpty {
            fields.append(Field(title: String(localized: "Device"), value: device))
        }
        if let model = reading.deviceModel, !model.isEmpty, model != reading.device {
            fields.append(Field(title: String(localized: "Model"), value: model))
        }
        fields.append(Field(title: String(localized: "Entered by hand"),
                            value: reading.wasUserEntered ? String(localized: "Yes") : String(localized: "No")))
        return fields
    }
}

extension ReadingQuality.Level: Identifiable {
    var id: Int { rawValue }
}

#if DEBUG
#Preview("Record") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VaultRecordSheet(
            reading: VaultPreviewSource.sample(minutesAgo: 12),
            metric: BodyCatalog.categories[4].types[0].metric
        )
    }
}
#endif
