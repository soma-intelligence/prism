//
//  AddUrineTestSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import PhotosUI
import UniformTypeIdentifiers

/// Adding a urine test, two ways.
///
/// A lab report: photographed, imported as a PDF, or typed, read on the
/// device exactly as a blood report is, then checked value by value.
///
/// A home strip: ten pads read by the camera against the strip's chart
/// (`UrineDipstickReader`), then checked pad by pad. The result is always
/// marked approximate, and never a diagnosis.
struct AddUrineTestSheet: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = UrinePanelStore.shared
    @State private var reportPhoto: PhotosPickerItem?
    @State private var stripPhoto: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var isShowingReportCamera = false
    @State private var isShowingStripCamera = false
    @State private var isReading = false
    @State private var draft: UrineDraft?
    @State private var stripImage: CGImage?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    SomaPageHero(
                        eyebrow: "Urine test",
                        title: "Add a urine test",
                        reason: "From a lab report, or a ten pad strip read with the camera. Both are read on this phone, and you check every value before it is saved."
                    )
                    if isReading {
                        HStack(spacing: theme.metrics.cardSpacing) {
                            ProgressView()
                            Text("Reading")
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 12)
                    }
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        LabEyebrow("A home strip")
                        SomaCard {
                            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                                DipstickGuideOverlay(showsNames: false)
                                LabLeadText("Dip the strip, wait one to two minutes, and lay it on white paper in daylight. The camera matches each pad to the chart's colours, using the white handle to correct for the light.")
                            }
                        }
                        if LabCamera.isAvailable {
                            LabPrimaryButton(title: "Read a strip") { isShowingStripCamera = true }
                        }
                        PhotosPicker(selection: $stripPhoto, matching: .images) {
                            Text(LabCamera.isAvailable ? "Or a photo cropped to the strip" : "Choose a photo cropped to the strip")
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.accent.color)
                        }
                        if let failure {
                            Text(failure)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(theme.colors.danger.color)
                        }
                    }
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        LabEyebrow("A lab report")
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
                UrinePanelConfirmView(draft: draft, reread: rereadFlipped) { dismiss() }
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
        .onChange(of: stripPhoto) {
            guard let stripPhoto else { return }
            Task {
                let data = try? await stripPhoto.loadTransferable(type: Data.self)
                readStrip(data.flatMap(LabImages.cgImage))
                self.stripPhoto = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingReportCamera) {
            LabCamera { data in
                isShowingReportCamera = false
                guard let data else { return }
                Task { await readReport { await BloodReportReader.text(fromImageData: data) } }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isShowingStripCamera) {
            DipstickCamera { image in
                isShowingStripCamera = false
                if let image { readStrip(image) }
            }
        }
        #endif
    }

    private var reportRows: [LabRow] {
        var rows: [LabRow] = []
        if LabCamera.isAvailable {
            rows.append(LabRow("Photograph the report", action: { isShowingReportCamera = true }))
        }
        rows.append(LabRow("Import a PDF", detail: "from your lab", action: { isImportingPDF = true }))
        rows.append(LabRow("Type it in", detail: "\(UrineDraft.typedMarkers.count) markers", action: { draft = .typed() }))
        return rows
    }

    private var footnote: String {
        guard let last = store.latest else { return "No urine test yet." }
        return "Last test \(last.date.labDay)."
    }

    private func readReport(_ text: () async -> String) async {
        isReading = true
        let found = UrineReportReader.detect(in: await text())
        isReading = false
        draft = .extracted(found)
    }

    private func readStrip(_ image: CGImage?) {
        failure = nil
        guard let image, let readings = UrineDipstickReader.read(image: image) else {
            failure = "Soma couldn't read a strip in that photo. Try again in daylight, the strip filling the slot."
            return
        }
        stripImage = image
        draft = .strip(readings, reversed: false)
    }

    /// The same photo read with the pads the other way round.
    private func rereadFlipped(_ reversed: Bool) -> UrineDraft? {
        guard let stripImage, let readings = UrineDipstickReader.read(image: stripImage, reversed: reversed) else { return nil }
        return .strip(readings, reversed: reversed)
    }
}

/// Image data as a CGImage, on every platform the app builds for.
enum LabImages {
    static func cgImage(_ data: Data) -> CGImage? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // The orientation tag applied, so a phone photo reads upright.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 2400]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        #else
        return nil
        #endif
    }
}

// MARK: - The confirm step

/// A urine test being checked. A pad line holds a chart step, picked from
/// the chart; a lab line holds its value as text and its unit.
struct UrineDraft: Identifiable, Hashable {
    struct Line: Identifiable, Hashable {
        let id = UUID()
        var markerID: String
        var text = ""
        var unit = ""
        /// The chart step, for a pad.
        var step: Int?
        /// How far the camera's colour was from that step.
        var deltaE: Double?
        var refLow: Double?
        var refHigh: Double?
        var source: UrineValue.Source

        var marker: UrineMarker? { UrineCatalog.marker(id: markerID) }

        var isPadLine: Bool { step != nil }

        var storageValue: Double? {
            guard let marker else { return nil }
            if let step, marker.steps.indices.contains(step) { return marker.steps[step].value }
            guard let value = BloodReportReader.parseDecimal(text) else { return nil }
            return marker.toStorage(value, from: unit)
        }

        var isUnsure: Bool { (deltaE ?? 0) > UrinePadReading.unsureDeltaE && source == .camera }

        var needsALook: Bool {
            if isPadLine { return isUnsure }
            guard !text.isEmpty else { return false }
            return storageValue == nil
        }
    }

    let id = UUID()
    var lines: [Line]
    var sampledAt = Date()
    var kind: UrinePanel.Kind
    var fromReport: Bool
    var reversed = false

    static let typedMarkers = ["specificGravity", "ph", "protein", "glucose", "ketones", "blood", "nitrite", "leukocytes", "acr", "creatinine"]

    static func typed() -> UrineDraft {
        UrineDraft(lines: typedMarkers.compactMap { id in UrineCatalog.marker(id: id).map { line(blank: $0) } },
                   kind: .labReport, fromReport: false)
    }

    private static func line(blank marker: UrineMarker) -> Line {
        marker.isPad
            ? Line(markerID: marker.id, unit: marker.unit, step: nil, source: .manual)
            : Line(markerID: marker.id, unit: marker.unit, source: .manual)
    }

    static func extracted(_ found: [ExtractedUrineMarker]) -> UrineDraft {
        UrineDraft(lines: found.map { item in
            let marker = UrineCatalog.marker(id: item.id)
            let unit = marker.flatMap { $0.accepts(item.unit) ? item.unit : nil } ?? marker?.unit ?? item.unit
            // A word on the report ("Negative", "2+") is a step of the chart.
            if let marker, marker.isPad, BloodMarkerCatalog.normalize(unit) == BloodMarkerCatalog.normalize(marker.unit),
               let step = marker.steps.firstIndex(where: { abs($0.value - item.value) < 0.000_1 }) {
                return Line(markerID: item.id, unit: unit, step: step, refLow: item.refLow, refHigh: item.refHigh, source: .extracted)
            }
            let decimals = item.id == "specificGravity" ? 3 : LabMath.decimals(for: item.value)
            let number = LabMath.format(item.value, decimals: decimals, locale: Locale(identifier: "en_US_POSIX")) ?? ""
            return Line(markerID: item.id, text: number, unit: unit, refLow: item.refLow, refHigh: item.refHigh, source: .extracted)
        }, kind: .labReport, fromReport: true)
    }

    static func strip(_ readings: [UrinePadReading], reversed: Bool) -> UrineDraft {
        UrineDraft(lines: readings.map { reading in
            Line(markerID: reading.markerID, unit: UrineCatalog.marker(id: reading.markerID)?.unit ?? "",
                 step: reading.stepIndex, deltaE: reading.deltaE, source: .camera)
        }, kind: .dipstick, fromReport: true, reversed: reversed)
    }

    func panel(now: Date) -> UrinePanel {
        UrinePanel(sampledAt: sampledAt, createdAt: now, kind: kind, values: lines.compactMap { line in
            guard let value = line.storageValue else { return nil }
            return UrineValue(key: line.markerID, value: value, enteredUnit: line.unit, source: line.source,
                              labRefLow: line.refLow, labRefHigh: line.refHigh)
        })
    }

    static func == (a: UrineDraft, b: UrineDraft) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct UrinePanelConfirmView: View {
    @State var draft: UrineDraft
    /// Reads the same strip with its pads the other way, for a brand that
    /// runs from the tip.
    let reread: (Bool) -> UrineDraft?
    let onSaved: () -> Void

    @Environment(\.somaTheme) private var theme
    @State private var store = UrinePanelStore.shared

    var body: some View {
        let doubtful = draft.lines.filter(\.needsALook).count
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                SomaPageHero(
                    eyebrow: draft.kind == .dipstick ? "Strip, approximate" : "Test of \(draft.sampledAt.formatted(.dateTime.day().month(.wide).year()))",
                    title: draft.kind == .dipstick ? "Check each pad" : (draft.fromReport ? "Check the values" : "Type the values"),
                    reason: reason(doubtful: doubtful)
                )
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    VStack(spacing: 0) {
                        ForEach($draft.lines) { $line in
                            UrineDraftLineView(line: $line)
                            if line.id != draft.lines.last?.id {
                                Rectangle()
                                    .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
                                    .frame(height: 0.5)
                                    .padding(.leading, theme.metrics.browseRowPadding)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                        .fill(theme.colors.surface.color))
                    .clipShape(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous))

                    if draft.kind == .dipstick {
                        LabRowGroup(rows: [
                            LabRow("Pads run from the tip?", detail: draft.reversed ? "flipped" : "flip", action: {
                                if let flipped = reread(!draft.reversed) { draft = flipped }
                            }),
                        ])
                    } else {
                        Menu {
                            ForEach(UrineCatalog.all.filter { m in !draft.lines.contains { $0.markerID == m.id } }) { marker in
                                Button(marker.name) {
                                    draft.lines.append(.init(markerID: marker.id, unit: marker.unit, source: .manual))
                                }
                            }
                        } label: {
                            SomaBrowseRow(title: "Add a marker", opensSomething: true)
                                .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                                    .fill(theme.colors.surface.color))
                        }
                        .buttonStyle(.plain)
                    }

                    LabDateRow(title: "Sample taken", date: $draft.sampledAt)
                        .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                            .fill(theme.colors.surface.color))

                    LabPrimaryButton(title: "Save the test", isEnabled: draft.lines.contains { $0.storageValue != nil }) {
                        store.save(draft.panel(now: .now))
                        onSaved()
                    }
                    LabFootnote(draft.kind == .dipstick
                                ? "Approximate: a colour match, not a lab result, and never a diagnosis. Kept on this phone."
                                : "Kept on this phone.")
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
        if draft.kind == .dipstick {
            let look = doubtful == 0 ? "Every pad matched a step closely" : (doubtful == 1 ? "One pad was far from every step" : "\(doubtful) pads were far from every step")
            return "\(look). Hold the strip beside the chart on its bottle and tap any pad to set the step you see."
        }
        if draft.fromReport && draft.lines.isEmpty {
            return "Nothing on the page matched a urine marker Soma knows. Add the values by hand below."
        }
        let filled = draft.lines.filter { !$0.text.isEmpty || $0.step != nil }.count
        let read = draft.fromReport ? "\(filled) values read" : "\(filled) of \(draft.lines.count) filled"
        let look = doubtful == 0 ? "none needs a look" : (doubtful == 1 ? "one needs a look" : "\(doubtful) need a look")
        return "\(read); \(look). Tap any value to correct it, and check the date and the units against the report."
    }
}

/// One line of the check: a pad's chart step as a menu with its colour, or
/// a lab value as a field with its unit.
struct UrineDraftLineView: View {
    @Binding var line: UrineDraft.Line

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let marker = line.marker
        let name = marker?.name ?? line.markerID
        HStack(spacing: theme.metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if line.needsALook {
                    Text(line.isPadLine ? "Unsure: compare with the chart." : "The unit needs a look.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            Spacer(minLength: theme.metrics.browseRowSpacing)
            if let marker, marker.isPad, line.source != .extracted || line.isPadLine || line.text.isEmpty {
                Menu {
                    ForEach(marker.steps.indices, id: \.self) { index in
                        Button(marker.steps[index].label) {
                            line.step = index
                            if line.source == .camera { line.deltaE = 0 }
                        }
                    }
                } label: {
                    Text(line.step.map { marker.steps[$0].label } ?? "Pick")
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(line.step == nil ? theme.colors.accent.color : theme.colors.inkPrimary.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(name))
            } else {
                LabTextField(placeholder: "-", text: $line.text)
                    .frame(maxWidth: 72)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel(Text(name))
                if let marker, !marker.acceptedUnits.isEmpty {
                    LabUnitMenu(units: units(marker), unit: $line.unit)
                }
            }
            Image(systemName: line.needsALook ? "square.and.pencil" : "checkmark")
                .foregroundStyle(line.needsALook ? theme.colors.accent.color : theme.colors.inkSecondary.color)
                .opacity(line.text.isEmpty && line.step == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, theme.metrics.browseRowPadding)
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .frame(minHeight: theme.metrics.browseRowMinHeight)
        .background(line.needsALook ? theme.colors.inkPrimary.color.opacity(theme.metrics.browsePressOpacity) : .clear)
    }

    private func units(_ marker: UrineMarker) -> [String] {
        var seen = Set<String>()
        return ([marker.unit] + marker.acceptedUnits.keys.sorted().map { LabUnits.pretty($0) })
            .filter { !$0.isEmpty && seen.insert(BloodMarkerCatalog.normalize($0)).inserted }
    }
}
