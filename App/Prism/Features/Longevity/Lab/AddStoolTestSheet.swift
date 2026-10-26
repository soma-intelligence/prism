//
//  AddStoolTestSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import PhotosUI
import UniformTypeIdentifiers

/// Adding a stool test: a lab report or a microbiome kit's report,
/// photographed, imported as a PDF, or typed, read on the device exactly as a
/// blood report is, then checked value by value. Nothing is saved before the
/// person confirms, and a value the reader could not find stays blank.
struct AddStoolTestSheet: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = StoolPanelStore.shared
    @State private var reportPhoto: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var isShowingCamera = false
    @State private var isReading = false
    @State private var draft: StoolDraft?

    var body: some View {
        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    SomaPageHero(
                        eyebrow: "Stool test",
                        title: "Add a stool test",
                        reason: "From a lab report or a microbiome kit's results. Read on this phone, and you check every value before it is saved."
                    )
                    if isReading {
                        HStack(spacing: theme.metrics.cardSpacing) {
                            ProgressView()
                            Text("Reading")
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                    }
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        LabEyebrow("The report")
                        LabRowGroup(rows: reportRows)
                        PhotosPicker(selection: $reportPhoto, matching: .images) {
                            Text("Or choose a photo of the report")
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.accent.color)
                        }
                        LabFootnote(footnote)
                    }
                }
                .padding(.horizontal, theme.metrics.pagePadding)
                .padding(.bottom, theme.metrics.pagePadding)
                .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .softScrollEdges()
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $draft) { draft in
                StoolPanelConfirmView(draft: draft) { dismiss() }
            }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await readReport { await BloodReportReader.text(fromPDF: url) } }
        }
        .onChange(of: reportPhoto) {
            guard let reportPhoto else { return }
            Task {
                await readReport {
                    guard let data = try? await reportPhoto.loadTransferable(type: Data.self) else { return "" }
                    return await BloodReportReader.text(fromImageData: data)
                }
                self.reportPhoto = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCamera) {
            LabCamera { data in
                isShowingCamera = false
                guard let data else { return }
                Task { await readReport { await BloodReportReader.text(fromImageData: data) } }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private var reportRows: [LabRow] {
        var rows: [LabRow] = []
        if LabCamera.isAvailable {
            rows.append(LabRow("Photograph the report", action: { isShowingCamera = true }))
        }
        rows.append(LabRow("Import a PDF", detail: "from the lab or the kit", action: { isImportingPDF = true }))
        rows.append(LabRow("Type it in", detail: "\(StoolCatalog.all.count) markers", action: { draft = .typed() }))
        return rows
    }

    private var footnote: String {
        guard let last = store.latest else { return "No stool test yet." }
        return "Last test \(last.date.labDay)."
    }

    private func readReport(_ text: () async -> String) async {
        isReading = true
        let found = StoolReportReader.detect(in: await text())
        isReading = false
        draft = .extracted(found)
    }
}

// MARK: - The confirm step

/// A stool test being checked. A qualitative line holds negative (0) or
/// positive (1); a number line holds its value as text and its unit.
struct StoolDraft: Identifiable, Hashable {
    struct Line: Identifiable, Hashable {
        let id = UUID()
        var markerID: String
        var text = ""
        var unit = ""
        var source: StoolValue.Source

        var marker: StoolMarker? { StoolCatalog.marker(id: markerID) }

        var storageValue: Double? {
            guard let marker, let value = BloodReportReader.parseDecimal(text) else { return nil }
            if marker.isQualitative { return value >= 0.5 ? 1 : 0 }
            return marker.toStorage(value, from: unit)
        }

        var needsALook: Bool { !text.isEmpty && storageValue == nil }
    }

    let id = UUID()
    var lines: [Line]
    var sampledAt = Date()
    var fromReport: Bool

    static func typed() -> StoolDraft {
        StoolDraft(lines: StoolCatalog.all.map { Line(markerID: $0.id, unit: $0.unit, source: .manual) }, fromReport: false)
    }

    /// What the reader found, and only that: a half read report saves its
    /// half and nothing is calculated on the rest.
    static func extracted(_ found: [ExtractedStoolMarker]) -> StoolDraft {
        StoolDraft(lines: found.map { item in
            let marker = StoolCatalog.marker(id: item.id)
            let unit = marker.flatMap { $0.accepts(item.unit) ? (item.unit.isEmpty ? $0.unit : item.unit) : nil } ?? marker?.unit ?? item.unit
            let text = marker?.isQualitative == true
                ? (item.value >= 0.5 ? "1" : "0")
                : (LabMath.format(item.value, decimals: LabMath.decimals(for: item.value), locale: Locale(identifier: "en_US_POSIX")) ?? "")
            return Line(markerID: item.id, text: text, unit: unit, source: .extracted)
        }, fromReport: true)
    }

    func panel(now: Date) -> StoolPanel {
        let values = lines.compactMap { line -> StoolValue? in
            guard let value = line.storageValue else { return nil }
            return StoolValue(key: line.markerID, value: value, enteredUnit: line.unit, source: line.source)
        }
        return StoolPanel(sampledAt: sampledAt, createdAt: now, kind: StoolPanel.kind(for: values), values: values)
    }

    static func == (a: StoolDraft, b: StoolDraft) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct StoolPanelConfirmView: View {
    @State var draft: StoolDraft
    let onSaved: () -> Void

    @Environment(\.somaTheme) private var theme
    @State private var store = StoolPanelStore.shared
    @State private var isAddingMarker = false

    /// The row under the values.
    private enum Extra: String, CaseIterable, Identifiable {
        case date
        var id: String { rawValue }
    }

    var body: some View {
        let doubtful = draft.lines.filter(\.needsALook).count
        let missing = StoolCatalog.all.filter { marker in !draft.lines.contains { $0.markerID == marker.id } }
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                SomaPageHero(
                    eyebrow: "Test of \(draft.sampledAt.formatted(.dateTime.day().month(.wide).year()))",
                    title: draft.fromReport ? "Check the values" : "Type the values",
                    reason: reason(doubtful: doubtful)
                )
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    if !draft.lines.isEmpty {
                        SomaBrowseGroup(draft.lines, hasGlyphs: false) { line in
                            if let index = draft.lines.firstIndex(where: { $0.id == line.id }) {
                                StoolDraftLineView(line: $draft.lines[index])
                            }
                        }
                    }
                    if !missing.isEmpty {
                        LabRowGroup(heading: isAddingMarker ? "Add a marker" : nil, rows: isAddingMarker
                            ? missing.map { marker in
                                LabRow(marker.name, action: {
                                    draft.lines.append(.init(markerID: marker.id, unit: marker.unit, source: .manual))
                                    isAddingMarker = false
                                })
                            }
                            : [LabRow("Add a marker", detail: "\(missing.count) more", action: { isAddingMarker = true })])
                    }
                    SomaBrowseGroup(Extra.allCases, hasGlyphs: false) { _ in
                        LabDateRow(title: "Sample taken", date: $draft.sampledAt)
                    }
                    LabPrimaryButton(title: "Save the test", isEnabled: draft.lines.contains { $0.storageValue != nil } && doubtful == 0) {
                        store.save(draft.panel(now: .now))
                        onSaved()
                    }
                    LabFootnote("Kept on this phone. Informational, never a diagnosis.")
                }
            }
            .padding(.horizontal, theme.metrics.pagePadding)
            .padding(.bottom, theme.metrics.pagePadding)
            .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
        .background(theme.colors.canvas.color.ignoresSafeArea())
#if !os(visionOS)
        .scrollDismissesKeyboard(.interactively)
#endif
    }

    private func reason(doubtful: Int) -> String {
        if draft.fromReport && draft.lines.isEmpty {
            return "Nothing on the page matched a stool marker Soma knows. Add the values by hand below."
        }
        let filled = draft.lines.filter { !$0.text.isEmpty }.count
        let read = draft.fromReport ? "\(filled) values read" : "\(filled) of \(draft.lines.count) filled"
        let look = doubtful == 0 ? "none needs a look" : (doubtful == 1 ? "one needs a look" : "\(doubtful) need a look")
        return "\(read); \(look). A value left blank stays blank: nothing is guessed. Check the date and the units against the report."
    }
}

/// One line of the check: negative or positive as two chips, or a number
/// with its unit.
struct StoolDraftLineView: View {
    @Binding var line: StoolDraft.Line

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let marker = line.marker
        let name = marker?.name ?? line.markerID
        HStack(spacing: theme.metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(name)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if line.needsALook {
                    Text("The value or the unit needs a look.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            Spacer(minLength: theme.metrics.browseRowSpacing)
            if marker?.isQualitative == true {
                HStack(spacing: theme.metrics.spaceXS) {
                    SomaChoiceChip("Negative", isOn: line.text == "0", style: .outline) { line.text = "0" }
                    SomaChoiceChip("Positive", isOn: line.text == "1", style: .outline) { line.text = "1" }
                }
            } else {
                LabTextField(placeholder: "-", text: $line.text)
                    .frame(minWidth: theme.metrics.minimumTapTarget)
                    .fixedSize(horizontal: true, vertical: false)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel(Text(name))
                if let unit = marker?.unit, !unit.isEmpty {
                    Text(unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .padding(.horizontal, theme.metrics.browseRowPadding)
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .frame(minHeight: theme.metrics.browseRowMinHeight)
        .background(line.needsALook ? theme.colors.inkPrimary.color.opacity(theme.metrics.browsePressOpacity) : .clear)
    }
}
