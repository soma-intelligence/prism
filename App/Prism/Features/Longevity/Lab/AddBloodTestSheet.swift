//
//  AddBloodTestSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import PhotosUI
import UniformTypeIdentifiers

/// Adding a blood test: photograph the report, import the lab's PDF, or type
/// the values in. A photo or a PDF is read on the device (Vision's text
/// recognition and a conservative label matcher, never a server) and every
/// value lands on the confirm screen before anything is saved.
struct AddBloodTestSheet: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = BloodPanelStore.shared
    @State private var photo: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var isShowingCamera = false
    @State private var isReading = false
    @State private var draft: BloodPanelDraft?

    var body: some View {
        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    SomaPageHero(
                        eyebrow: "Blood panel",
                        title: "Add a blood test",
                        reason: "Photograph the report and Soma reads it on this phone. You check every value before it is saved. A panel sharpens biological age more than any other input."
                    )
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        if isReading {
                            HStack(spacing: theme.metrics.cardSpacing) {
                                ProgressView()
                                Text("Reading the report")
                                    .somaFont(theme.typography.body)
                                    .foregroundStyle(theme.colors.inkSecondary.color)
                            }
                            .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 12)
                        } else if LabCamera.isAvailable {
                            LabPrimaryButton(title: "Photograph the report") { isShowingCamera = true }
                        } else {
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text("Choose a photo of the report")
                                    .somaFont(theme.typography.body)
                                    .foregroundStyle(theme.colors.onAccent.color)
                                    .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 12)
                                    .background(Capsule().fill(theme.colors.accent.color))
                            }
                            .buttonStyle(SomaGlassPressStyle())
                        }
                        LabRowGroup(rows: [
                            LabRow("Import a PDF", detail: "from your lab", action: { isImportingPDF = true }),
                            LabRow("Type it in", detail: "\(BloodPanelDraft.typedMarkers.count) markers",
                                   action: { draft = .typed() }),
                        ])
                        if LabCamera.isAvailable {
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text("Or choose a photo")
                                    .somaFont(theme.typography.body)
                                    .foregroundStyle(theme.colors.accent.color)
                            }
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
                BloodPanelConfirmView(draft: draft) { dismiss() }
            }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await read { await BloodReportReader.text(fromPDF: url) } }
        }
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                await read {
                    guard let data = try? await photo.loadTransferable(type: Data.self) else { return "" }
                    return await BloodReportReader.text(fromImageData: data)
                }
                self.photo = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCamera) {
            LabCamera { data in
                isShowingCamera = false
                guard let data else { return }
                Task { await read { await BloodReportReader.text(fromImageData: data) } }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private var footnote: String {
        guard let last = store.latest else { return "No panel yet. The first one starts your biological age from blood." }
        return "Last panel \(last.date.labDay)."
    }

    private func read(_ text: () async -> String) async {
        isReading = true
        let found = BloodReportReader.detect(in: await text())
        isReading = false
        draft = .extracted(found)
    }
}

// MARK: - The confirm step

/// A panel being checked: one line per marker, its value as text so a
/// misread can be corrected, and the unit it was printed in.
struct BloodPanelDraft: Identifiable, Hashable {
    struct Line: Identifiable, Hashable {
        let id = UUID()
        var markerID: String
        var text: String
        var unit: String
        var refLow: Double?
        var refHigh: Double?
        var source: BloodMarkerValue.Source

        var marker: BloodMarker? { BloodMarkerCatalog.marker(id: markerID) }
        var value: Double? { BloodReportReader.parseDecimal(text) }

        /// The value in the marker's storage unit, when the unit is one it accepts.
        var storageValue: Double? {
            guard let value, let marker else { return nil }
            return marker.toStorage(value, from: unit)
        }

        /// Read but doubtful: the unit is unknown, or the value is outside
        /// what a body can plausibly carry.
        var needsALook: Bool {
            guard !text.isEmpty else { return false }
            guard let storage = storageValue else { return true }
            if let key = BloodMarkerKey(rawValue: markerID) { return !key.plausibleRange.contains(storage) }
            return false
        }
    }

    let id = UUID()
    var lines: [Line]
    var sampledAt = Date()
    var fromReport: Bool

    /// The ten markers the typed form starts with.
    static let typedMarkers = ["apoB", "ldl", "hdl", "triglycerides", "hba1c", "glucose", "crp", "vitaminD", "ferritin", "tsh"]

    static func typed() -> BloodPanelDraft {
        BloodPanelDraft(lines: typedMarkers.compactMap { id in
            BloodMarkerCatalog.marker(id: id).map {
                Line(markerID: id, text: "", unit: $0.displayUnit, source: .manual)
            }
        }, fromReport: false)
    }

    static func extracted(_ markers: [ExtractedMarker]) -> BloodPanelDraft {
        BloodPanelDraft(lines: markers.map { found in
            let marker = BloodMarkerCatalog.marker(id: found.id)
            let unit = marker.flatMap { m in m.accepts(found.unit) ? found.unit : nil } ?? marker?.displayUnit ?? found.unit
            let number = LabMath.format(found.value, decimals: LabMath.decimals(for: found.value), locale: Locale(identifier: "en_US_POSIX")) ?? ""
            return Line(markerID: found.id, text: number, unit: unit, refLow: found.refLow, refHigh: found.refHigh, source: .extracted)
        }, fromReport: true)
    }

    /// The panel to save: only lines with a value in a unit their marker accepts.
    func panel(now: Date) -> BloodPanel {
        BloodPanel(sampledAt: sampledAt, createdAt: now, markers: lines.compactMap { line in
            guard let storage = line.storageValue else { return nil }
            return BloodMarkerValue(key: line.markerID, value: storage, enteredUnit: line.unit, source: line.source,
                                    labRefLow: line.refLow, labRefHigh: line.refHigh)
        })
    }

    static func == (a: BloodPanelDraft, b: BloodPanelDraft) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Check the values: each line editable, a mark on the ones that need a
/// look, the date, and the save.
struct BloodPanelConfirmView: View {
    @State var draft: BloodPanelDraft
    let onSaved: () -> Void

    @Environment(\.somaTheme) private var theme
    @State private var store = BloodPanelStore.shared

    var body: some View {
        let filled = draft.lines.filter { !$0.text.isEmpty }
        let doubtful = draft.lines.filter(\.needsALook).count
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                SomaPageHero(
                    eyebrow: "Panel of \(draft.sampledAt.formatted(.dateTime.day().month(.wide).year()))",
                    title: draft.fromReport ? "Check the values" : "Type the values",
                    reason: reason(filled: filled.count, doubtful: doubtful)
                )
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    VStack(spacing: 0) {
                        ForEach($draft.lines) { $line in
                            BloodDraftLineView(line: $line)
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

                    Menu {
                        ForEach(BloodMarkerCatalog.grouped(BloodMarkerCatalog.all.filter { m in !draft.lines.contains { $0.markerID == m.id } })) { group in
                            Section(group.category.displayName) {
                                ForEach(group.items) { marker in
                                    Button(marker.name) {
                                        draft.lines.append(.init(markerID: marker.id, text: "", unit: marker.displayUnit, source: .manual))
                                    }
                                }
                            }
                        }
                    } label: {
                        SomaBrowseRow(title: "Add a marker", opensSomething: true)
                            .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                                .fill(theme.colors.surface.color))
                    }
                    .buttonStyle(.plain)

                    LabDateRow(title: "Blood drawn", date: $draft.sampledAt)
                        .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                            .fill(theme.colors.surface.color))

                    LabPrimaryButton(title: "Save the panel", isEnabled: draft.lines.contains { $0.storageValue != nil }) {
                        store.save(draft.panel(now: .now))
                        onSaved()
                        Confirmations.shared.done("Blood panel saved")
                    }
                    LabFootnote("Kept on this phone.")
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
        // The headset's keyboard floats apart from the window.
        .scrollDismissesKeyboard(.interactively)
#endif
    }

    private func reason(filled: Int, doubtful: Int) -> String {
        if draft.fromReport && draft.lines.isEmpty {
            return "Nothing on the page matched a marker Soma knows. Add the values by hand below."
        }
        let read = draft.fromReport ? "\(filled) values read" : "\(filled) of \(draft.lines.count) filled"
        let look = doubtful == 0 ? "none needs a look" : (doubtful == 1 ? "one needs a look" : "\(doubtful) need a look")
        return "\(read); \(look). Tap any value to correct it, and check the date and the units against the report."
    }
}

/// One marker line: its name, the value as a field, the unit as a menu, and
/// a check or a pencil.
struct BloodDraftLineView: View {
    @Binding var line: BloodPanelDraft.Line

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let name = line.marker?.name ?? line.markerID
        HStack(spacing: theme.metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if line.needsALook {
                    Text(line.storageValue == nil ? "The unit needs a look." : "Unusual for this marker: check the page.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            Spacer(minLength: theme.metrics.browseRowSpacing)
            LabTextField(placeholder: "-", text: $line.text)
                .frame(maxWidth: 72)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel(Text(name))
            LabUnitMenu(units: units, unit: $line.unit)
            Image(systemName: line.needsALook ? "square.and.pencil" : "checkmark")
                .foregroundStyle(line.needsALook ? theme.colors.accent.color : theme.colors.inkSecondary.color)
                .opacity(line.text.isEmpty ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, theme.metrics.browseRowPadding)
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .frame(minHeight: theme.metrics.browseRowMinHeight)
        .background(line.needsALook ? theme.colors.inkPrimary.color.opacity(theme.metrics.browsePressOpacity) : .clear)
    }

    /// The units the marker accepts, written the way a lab prints them.
    private var units: [String] {
        guard let marker = line.marker else { return [line.unit] }
        var seen = Set<String>()
        return ([marker.displayUnit, marker.storageUnit] + marker.acceptedUnits.keys.sorted().map(LabUnits.pretty))
            .filter { !$0.isEmpty && seen.insert(BloodMarkerCatalog.normalize($0)).inserted }
    }
}

enum LabUnits {
    /// "mg/dl" as "mg/dL", "umol/l" as "µmol/L", "10^3/ul" as "10³/µL".
    static func pretty(_ key: String) -> String {
        var s = key
        s = s.replacingOccurrences(of: "10^3", with: "10³").replacingOccurrences(of: "10^9", with: "10⁹")
            .replacingOccurrences(of: "10^6", with: "10⁶").replacingOccurrences(of: "10^12", with: "10¹²")
        s = s.replacingOccurrences(of: "dl", with: "dL").replacingOccurrences(of: "ml", with: "mL")
        if s.hasSuffix("/l") { s = String(s.dropLast()) + "L" }
        s = s.replacingOccurrences(of: "umol", with: "µmol").replacingOccurrences(of: "ug", with: "µg")
            .replacingOccurrences(of: "/ul", with: "/µL").replacingOccurrences(of: "fl", with: "fL")
            .replacingOccurrences(of: "iu", with: "IU").replacingOccurrences(of: "u/l", with: "U/L")
        return s
    }
}
