//
//  DoctorReportPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// "Report for my doctor": the period, the paper, which domains go in, the
/// pages as they will print, and the share sheet.
///
/// Opened from the medical record and from the account sheet, under the
/// record. The PDF is made on this phone and written to its temporary folder
/// with complete protection; it leaves only through the share sheet, when
/// the person sends it. Mood questionnaires, the cycle and the DNA file start
/// switched off.
struct DoctorReportPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var period = DoctorReportPeriod.quarter
    @State private var paper = DoctorReportPaper.forLocale(.current)
    @State private var topics = DoctorReportTopic.standard
    /// What Health gave for the period, and whether the cycle was read.
    @State private var read: (key: ReadKey, health: DoctorReportHealth)?
    @State private var healthMedications: [HealthMedication] = []
    @State private var layout: DoctorReportRenderer.Layout?
    /// The domains with something in them, whatever is switched on.
    @State private var filled: Set<DoctorReportTopic> = []
    @State private var file: URL?
    @State private var previewWidth: CGFloat = 0

    /// What a read of Health depends on.
    struct ReadKey: Hashable {
        var period: DoctorReportPeriod
        var cycle: Bool
    }

    private var readKey: ReadKey { ReadKey(period: period, cycle: topics.contains(.cycle) && cycleAsked) }

    /// The cycle's types are sensitive: they are read only once the cycle
    /// page has asked for them, never from here.
    private var cycleAsked: Bool { health.hasAsked(HomeMetric.menstrualFlow) }

    var body: some View {
        ListScaffold(eyebrow: "For your doctor", title: "Report for my doctor") {
            HomeReason("A PDF of what Soma holds, to bring to a visit. It is made on this phone and leaves it only if you share it.")

            SettingsSection("Period") {
                SomaSegmentedControl(segments: DoctorReportPeriod.allCases.map { SomaSegment(id: $0, title: "\($0.title)") },
                                     selection: $period)
            }

            SettingsSection("Paper") {
                SomaSegmentedControl(segments: DoctorReportPaper.allCases.map { SomaSegment(id: $0, title: "\($0.title)") },
                                     selection: $paper)
            }

            SettingsSection("What goes in") {
                SomaBrowseGroup(DoctorReportTopic.allCases.filter { !$0.isSensitive }, hasGlyphs: false) { topic in
                    SettingsLine(topic.title, detail: filled.contains(topic) || layout == nil ? nil : String(localized: "Nothing recorded yet")) {
                        SettingsSwitch(title: topic.title, isOn: binding(topic))
                    }
                }
            }

            SettingsSection("Sensitive, off unless you choose") {
                SomaBrowseGroup(DoctorReportTopic.allCases.filter(\.isSensitive), hasGlyphs: false) { topic in
                    SettingsLine(topic.title, detail: sensitiveDetail(topic)) {
                        SettingsSwitch(title: topic.title, isOn: binding(topic))
                    }
                }
            }

            SettingsSection("Preview") {
                preview
            }

            if let file {
                ShareLink(item: file, preview: SharePreview(file.deletingPathExtension().lastPathComponent)) {
                    capsule(String(localized: "Share the PDF"), symbol: "square.and.arrow.up")
                }
                .buttonStyle(.somaGlassPress)
            }

            SettingsFootnote("Informational, not a diagnosis. Values are what Soma holds and may be incomplete; your doctor will confirm anything that matters with a clinical test.")
        }
        .task(id: readKey) { await readHealth() }
        .onChange(of: topics) { rebuild() }
        .onChange(of: paper) { rebuild() }
    }

    // MARK: Preview

    /// Every page at the width of the column, as it will print.
    @ViewBuilder
    private var preview: some View {
        VStack(spacing: theme.metrics.cardSpacing) {
            if let layout, previewWidth > 0 {
                let fit = previewWidth / layout.pageSize.width
                ForEach(layout.pages.indices, id: \.self) { index in
                    DoctorReportRenderer.page(layout, index)
                        .environment(\.colorScheme, .light)
                        .scaleEffect(fit, anchor: .topLeading)
                        .frame(width: layout.pageSize.width * fit, height: layout.pageSize.height * fit, alignment: .topLeading)
                        .clipShape(.rect(cornerRadius: theme.metrics.controlCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: theme.metrics.controlCornerRadius)
                                .strokeBorder(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Page \(index + 1) of \(layout.pages.count)"))
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { previewWidth = $0 }
    }

    private func capsule(_ title: String, symbol: String) -> some View {
        HStack(spacing: theme.metrics.spaceS) {
            Image(systemName: symbol)
            Text(title)
        }
        .somaFont(theme.typography.body)
        .foregroundStyle(theme.colors.inkPrimary.color)
        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
        .background(Capsule().strokeBorder(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)))
        .contentShape(.capsule)
    }

    private func sensitiveDetail(_ topic: DoctorReportTopic) -> String {
        switch topic {
        case .mind: String(localized: "PHQ-9, GAD-7 and the other questionnaires you answered")
        case .cycle: cycleAsked ? String(localized: "Periods, cycle length and symptoms from Apple Health")
            : String(localized: "Open the cycle page once to let Soma read it")
        case .genome: GenomeStore.shared.showsAPOE ? String(localized: "The variants Soma reads, APOE included")
            : String(localized: "The variants Soma reads. APOE stays out")
        default: ""
        }
    }

    private func binding(_ topic: DoctorReportTopic) -> Binding<Bool> {
        Binding(
            get: { topics.contains(topic) },
            set: { on in
                if on { topics.insert(topic) } else { topics.remove(topic) }
            }
        )
    }

    // MARK: Reading and building

    private func readHealth() async {
        let key = readKey
        let now = Date()
        let source = await health.prepare(DoctorReportHealth.identifiers + (key.cycle ? DoctorReportHealth.cycleIdentifiers : []))
        var read = DoctorReportHealth()
        if let source {
            read = await DoctorReportHealth.read(
                from: source, period: key.period, includeCycle: key.cycle, scores: health.scores,
                journalDays: journal.loggedDays, lastDentalVisit: OralHealthPage.lastDentalVisit,
                bookedDentalVisit: MedicalRecordStore.shared.record.nextDentalVisit(now: now),
                age: SomaProfileStore.shared.profile.age(on: now), now: now)
        }
        healthMedications = await MedicationHealth.medications(now: now)
        self.read = (key, read)
        rebuild()
    }

    private func rebuild() {
        guard let read else { return }
        let now = Date()
        var input = DoctorReportSources.input(period: read.key.period, topics: topics, health: read.health,
                                              healthMedications: healthMedications, now: now)
        let report = DoctorReportBuilder.build(input)
        input.topics = Set(DoctorReportTopic.allCases)
        filled = Set(DoctorReportBuilder.build(input).sections.compactMap { section in
            if case .topic(let topic) = section.kind { topic } else { nil }
        })
        let layout = DoctorReportRenderer.layout(report, paper: paper, theme: theme)
        self.layout = layout
        file = write(DoctorReportRenderer.pdf(layout, theme: theme), report: report, now: now)
    }

    /// The PDF in the temporary folder, named for the person and the day,
    /// with complete file protection. The one before it goes.
    private func write(_ data: Data, report: DoctorReport, now: Date) -> URL? {
        if let file { try? FileManager.default.removeItem(at: file) }
        let name = report.patientName == "-" ? "" : " \(report.patientName)"
        let day = now.formatted(.iso8601.year().month().day())
        let safe = "Health summary\(name) \(day)".filter { !"/:\\".contains($0) }
        let url = FileManager.default.temporaryDirectory.appending(path: safe + ".pdf")
        do {
            #if os(iOS) || os(visionOS)
            try data.write(to: url, options: SomaFileStorage.protectedAtomicOptions)
            #else
            try data.write(to: url, options: .atomic)
            #endif
            return url
        } catch {
            return nil
        }
    }
}

#Preview("Report for my doctor") {
    NavigationStack { DoctorReportPage() }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
