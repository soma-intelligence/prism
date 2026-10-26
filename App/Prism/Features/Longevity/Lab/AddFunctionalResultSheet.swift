//
//  AddFunctionalResultSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import PhotosUI
import UniformTypeIdentifiers

/// Adding an imaging or functional test result: pick the test, or let the
/// report say which one it is, then a form of that test's values to check or
/// type. A report is read on the device exactly as a blood report is
/// (`BloodReportReader` for the text, `FunctionalReportReader` for the
/// values), and nothing is saved before the person confirms the form.
struct AddFunctionalResultSheet: View {
    /// The test to open on; nil starts from the list or from a report.
    var kind: FunctionalTestKind?

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var reportPhoto: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var isShowingCamera = false
    @State private var isReading = false
    @State private var draft: FunctionalDraft?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    SomaPageHero(
                        eyebrow: kind?.title ?? "Imaging and tests",
                        title: kind.map { "Add a \($0.title.lowercased())" } ?? "Add a result",
                        reason: "Import the report, or type the values. It is read on this phone, and you check every value before it is saved."
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
                        LabEyebrow("From the report")
                        LabRowGroup(rows: reportRows)
                        PhotosPicker(selection: $reportPhoto, matching: .images) {
                            Text("Or choose a photo of the report")
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
                        LabEyebrow("Type it in")
                        LabRowGroup(rows: typeRows)
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
                FunctionalResultForm(draft: draft) { dismiss() }
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
        rows.append(LabRow("Import a PDF", detail: "from the clinic", action: { isImportingPDF = true }))
        return rows
    }

    private var typeRows: [LabRow] {
        let kinds = kind.map { [$0] } ?? FunctionalTestKind.reported
        return kinds.map { kind in
            LabRow(kind.title, detail: "\(kind.fields.count) values", action: { draft = .typed(kind, measures: GlobalSettings.shared.units.measures) })
        }
    }

    private func readReport(_ text: () async -> String) async {
        failure = nil
        isReading = true
        let page = await text()
        isReading = false
        guard let found = kind ?? FunctionalReportReader.guessKind(in: page) else {
            failure = "Soma couldn't tell which test this report is. Pick the test below and type the values."
            return
        }
        draft = .extracted(FunctionalReportReader.detect(in: page, kind: found), kind: found,
                             measures: GlobalSettings.shared.units.measures)
    }
}

// MARK: - The form

/// A result being checked or typed: one line per value of the test, each a
/// number as text with its unit, or present and absent for a yes or no.
struct FunctionalDraft: Identifiable, Hashable {
    struct Line: Identifiable, Hashable {
        var id: String { fieldID }
        var fieldID: String
        var text = ""
        var unit: String
        var fromReport = false

        func field(_ kind: FunctionalTestKind) -> FunctionalField? { FunctionalCatalog.field(fieldID, in: kind) }
    }

    let id = UUID()
    var kind: FunctionalTestKind
    var lines: [Line]
    var date = Date()
    var note = ""
    var fromReport: Bool

    /// A blank form, masses in the person's measures.
    static func typed(_ kind: FunctionalTestKind, measures: MeasureSystem) -> FunctionalDraft {
        FunctionalDraft(kind: kind, lines: kind.fields.map { Line(fieldID: $0.id, unit: defaultUnit($0, measures: measures)) }, fromReport: false)
    }

    /// The report's values on the test's form, the rest left blank to fill.
    static func extracted(_ found: [ExtractedFunctionalValue], kind: FunctionalTestKind,
                          measures: MeasureSystem) -> FunctionalDraft {
        FunctionalDraft(kind: kind, lines: kind.fields.map { field in
            guard let item = found.first(where: { $0.fieldID == field.id }) else {
                return Line(fieldID: field.id, unit: defaultUnit(field, measures: measures))
            }
            let number = LabMath.format(item.value, decimals: max(field.decimals, LabMath.decimals(for: item.value)),
                                        locale: Locale(identifier: "en_US_POSIX")) ?? ""
            let unit = item.unit.isEmpty ? defaultUnit(field, measures: measures) : item.unit
            return Line(fieldID: field.id, text: field.quantity == .yesNo ? (item.value >= 0.5 ? "1" : "0") : number,
                        unit: unit, fromReport: true)
        }, fromReport: true)
    }

    static func defaultUnit(_ field: FunctionalField, measures: MeasureSystem) -> String {
        field.quantity == .mass ? field.displayUnit(measures) : field.unit
    }

    /// A number as typed, a leading minus kept: a T-score is often negative.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let negative = trimmed.hasPrefix("-") || trimmed.hasPrefix("\u{2212}")
        guard let value = BloodReportReader.parseDecimal(trimmed) else { return nil }
        return negative ? -value : value
    }

    func storageValue(_ line: Line) -> Double? {
        guard let field = line.field(kind), let value = Self.number(line.text) else { return nil }
        if field.quantity == .yesNo { return value >= 0.5 ? 1 : 0 }
        return field.toStorage(value, from: line.unit)
    }

    func needsALook(_ line: Line) -> Bool {
        !line.text.isEmpty && storageValue(line) == nil
    }

    /// The confirmed result: only the values that were read or typed, so a
    /// half read report saves its half and nothing is guessed.
    func result() -> FunctionalResult {
        var values: [String: Double] = [:]
        for line in lines { values[line.fieldID] = storageValue(line) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return FunctionalResult(kind: kind, date: date, values: values, note: trimmed.isEmpty ? nil : trimmed)
    }

    static func == (a: FunctionalDraft, b: FunctionalDraft) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct FunctionalResultForm: View {
    /// The two rows under the values.
    private enum FormExtra: String, CaseIterable, Identifiable {
        case date, note
        var id: String { rawValue }
    }

    @State var draft: FunctionalDraft
    let onSaved: () -> Void

    @Environment(\.somaTheme) private var theme
    @State private var store = FunctionalResultStore.shared

    var body: some View {
        let filled = draft.lines.filter { draft.storageValue($0) != nil }.count
        let doubtful = draft.lines.filter { draft.needsALook($0) }.count
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                SomaPageHero(
                    eyebrow: draft.kind.title,
                    title: draft.fromReport ? "Check the values" : "Type the values",
                    reason: reason(filled: filled, doubtful: doubtful)
                )
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    SomaBrowseGroup(draft.lines, hasGlyphs: false) { line in
                        if let index = draft.lines.firstIndex(where: { $0.id == line.id }) {
                            FunctionalDraftLineView(line: $draft.lines[index], kind: draft.kind, needsALook: draft.needsALook(line))
                        }
                    }

                    SomaBrowseGroup(FormExtra.allCases, hasGlyphs: false) { extra in
                        switch extra {
                        case .date:
                            LabDateRow(title: "Test date", date: $draft.date)
                        case .note:
                            LabTextField(placeholder: "A note, such as the clinic or the hand", text: $draft.note, role: .note)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                                .padding(.horizontal, theme.metrics.browseRowPadding)
                                .frame(minHeight: theme.metrics.browseRowMinHeight)
                        }
                    }

                    LabPrimaryButton(title: "Save the result", isEnabled: filled > 0 && doubtful == 0) {
                        store.save(draft.result())
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

    private func reason(filled: Int, doubtful: Int) -> String {
        if draft.fromReport && filled == 0 {
            return "Nothing on the page matched a value of this test. Type the values from the report below."
        }
        let read = draft.fromReport ? "\(filled) of \(draft.lines.count) values read" : "\(filled) of \(draft.lines.count) filled"
        let look = doubtful == 0 ? "none needs a look" : (doubtful == 1 ? "one needs a look" : "\(doubtful) need a look")
        return "\(read); \(look). A value left blank stays blank: nothing is guessed. Check the date and the units against the report."
    }
}

/// One value of the form: its name, the number, and the unit, which a tap
/// moves to the next unit the test accepts. A yes or no value is two chips.
struct FunctionalDraftLineView: View {
    @Binding var line: FunctionalDraft.Line
    let kind: FunctionalTestKind
    let needsALook: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let field = line.field(kind)
        let name = field?.name ?? line.fieldID
        HStack(spacing: theme.metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(name)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if needsALook {
                    Text("The value or the unit needs a look.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            Spacer(minLength: theme.metrics.browseRowSpacing)
            if field?.quantity == .yesNo {
                HStack(spacing: theme.metrics.spaceXS) {
                    SomaChoiceChip("None", isOn: line.text == "0", style: .outline) { line.text = "0" }
                    SomaChoiceChip("Present", isOn: line.text == "1", style: .outline) { line.text = "1" }
                }
            } else {
                LabTextField(placeholder: "-", text: $line.text)
                    .frame(minWidth: theme.metrics.minimumTapTarget)
                    .fixedSize(horizontal: true, vertical: false)
                    #if os(iOS)
                    .keyboardType(line.fieldID == "tScore" ? .numbersAndPunctuation : .decimalPad)
                    #endif
                    .accessibilityLabel(Text(name))
                let units = Self.units(field)
                if units.count > 1 {
                    Button {
                        let index = units.firstIndex { BloodMarkerCatalog.normalize($0) == BloodMarkerCatalog.normalize(line.unit) } ?? -1
                        line.unit = units[(index + 1) % units.count]
                    } label: {
                        Text(line.unit)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.accent.color)
                            .frame(minWidth: theme.metrics.minimumTapTarget, minHeight: theme.metrics.minimumTapTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Unit, \(line.unit)"))
                    .accessibilityHint(Text("Changes the unit"))
                } else if let unit = units.first, !unit.isEmpty {
                    Text(unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .padding(.horizontal, theme.metrics.browseRowPadding)
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .frame(minHeight: theme.metrics.browseRowMinHeight)
        .background(needsALook ? theme.colors.inkPrimary.color.opacity(theme.metrics.browsePressOpacity) : .clear)
    }

    /// The storage unit first, then the others the test accepts.
    static func units(_ field: FunctionalField?) -> [String] {
        guard let field else { return [] }
        var seen = Set<String>()
        let ordered: [String] = field.quantity == .mass
            ? ["kg", "lb", "g"].filter { field.acceptedUnits[$0] != nil }
            : [field.unit] + field.acceptedUnits.keys.sorted().map { LabUnits.pretty($0) }
        return ordered.filter { !$0.isEmpty && seen.insert(BloodMarkerCatalog.normalize($0)).inserted }
    }
}
