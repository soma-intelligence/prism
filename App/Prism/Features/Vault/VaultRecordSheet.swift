//
//  VaultRecordSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One record, field by field: the value, when it began and ended, how long it
/// ran, what wrote it and on what, whether it was typed in, and its grade.
struct VaultRecordSheet: View {
    let reading: HealthReading
    let metric: HealthMetric

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private struct Field: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    private var fields: [Field] {
        let formatted = VaultFormat.value(of: reading, metric: metric)
        let seconds = reading.end.timeIntervalSince(reading.start)
        return [
            Field(title: "Value", value: formatted.value),
            Field(title: "Unit", value: formatted.unit ?? "-"),
            Field(title: "Start", value: reading.start.formatted(date: .abbreviated, time: .standard)),
            Field(title: "End", value: reading.end.formatted(date: .abbreviated, time: .standard)),
            Field(title: "Duration", value: seconds > 0 ? VaultFormat.duration(seconds) : "Instant"),
            Field(title: "Source", value: reading.source ?? "-"),
            Field(title: "Device", value: reading.device ?? "-"),
            Field(title: "Model", value: reading.deviceModel ?? "-"),
            Field(title: "Entered by hand", value: reading.wasUserEntered ? "Yes" : "No"),
        ]
    }

    var body: some View {
        let quality = ReadingQuality.grade(reading)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.browseSectionSpacing) {
                    VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
                        SomaBrowseGroup([quality.level], hasGlyphs: false) { level in
                            SomaBrowseRow(title: "Quality", detail: level.title, opensSomething: false) {
                                SomaQualityMarks(filled: level.marks, of: ReadingQuality.scale)
                            }
                        }

                        Text(quality.reason)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .padding(.horizontal, theme.metrics.browseRowPadding)
                    }

                    SomaBrowseGroup(fields, hasGlyphs: false) { field in
                        SomaBrowseRow(title: field.title, detail: field.value, opensSomething: false)
                    }
                }
                .padding(theme.metrics.pagePadding)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle(metric.displayName)
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
