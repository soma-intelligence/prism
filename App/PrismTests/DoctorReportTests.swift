//
//  DoctorReportTests.swift
//  PrismTests
//

import Foundation
import PDFKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import SomaUI
import Testing
import HealthExportCore
@testable import Prism

/// The report for the doctor: a domain with nothing in it leaves no empty
/// title behind, what is outside its range comes first, the PDF carries real
/// text a reader can search, the period chosen bounds the results, and the
/// sensitive domains (mind, cycle, DNA) stay out until the person ticks them.
@Suite("Doctor report")
@MainActor
struct DoctorReportTests {

    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    var now: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 10))! }

    func daysAgo(_ days: Int) -> Date { utc.date(byAdding: .day, value: -days, to: now)! }

    func input(_ period: DoctorReportPeriod = .quarter, topics: Set<DoctorReportTopic> = DoctorReportTopic.standard) -> DoctorReportInput {
        var input = DoctorReportInput(now: now, period: period, topics: topics)
        input.calendar = utc
        input.patient = DoctorReportPatient(name: "Ada Lovelace", birthday: utc.date(from: DateComponents(year: 1980, month: 3, day: 2)), sex: .female)
        return input
    }

    func blood(_ daysAgo: Int, _ markers: [(String, Double)]) -> BloodPanel {
        BloodPanel(sampledAt: self.daysAgo(daysAgo), createdAt: self.daysAgo(daysAgo), markers: markers.map {
            BloodMarkerValue(key: $0.0, value: $0.1, enteredUnit: BloodMarkerCatalog.marker(id: $0.0)?.storageUnit ?? "", source: .manual)
        })
    }

    /// A reading a day for `days` days, ending today.
    func daily(_ identifier: String, _ value: Double, days: Int, unit: HealthUnit = .countPerMinute) -> [HealthReading] {
        (0..<days).map { day in
            let start = daysAgo(day)
            return HealthReading(metric: identifier, value: value, unit: unit, start: start, end: start)
        }
    }

    static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"

    // MARK: Empty domains

    /// No stool test, no glucose, no brushing: none of them gets a title,
    /// and every section that is there has something under it.
    @Test func missingDomainIsOmittedNotEmpty() {
        var input = input()
        input.bloodPanels = [blood(10, [("albumin", 45)])]
        let report = DoctorReportBuilder.build(input)

        #expect(report.section(.labs) != nil)
        #expect(report.section(.glucose) == nil)
        #expect(report.section(.oral) == nil)
        #expect(report.section(.vitals) == nil)
        #expect(!report.plainText.contains("Stool"))
        #expect(!report.plainText.contains("Urine"))
        for section in report.sections {
            #expect(!section.blocks.isEmpty, "\(section.title) has nothing under it")
            for block in section.blocks {
                if case .table(let table) = block {
                    #expect(!table.rows.isEmpty, "\(section.title) has an empty table")
                }
            }
        }
    }

    /// An empty record still makes a report: the patient and the period,
    /// nothing else.
    @Test func emptyInputKeepsOnlyIdentity() {
        let report = DoctorReportBuilder.build(input())
        #expect(report.sections.map(\.kind) == [.identity])
    }

    // MARK: Flags

    /// A fasting glucose above its range opens the report, right after the
    /// patient, and leads the blood table.
    @Test func flaggedValuesFirst() throws {
        var input = input()
        input.bloodPanels = [blood(5, [("albumin", 45), ("mcv", 90), ("glucose", 7.2)])]
        input.vitals[Self.restingHeartRate] = daily(Self.restingHeartRate, 62, days: 90)
        let report = DoctorReportBuilder.build(input)

        #expect(report.sections.map(\.kind).prefix(2) == [.identity, .flagged])
        let flagged = try #require(report.section(.flagged))
        #expect(flagged.text.contains("Fasting glucose"))
        #expect(!flagged.text.contains("Albumin"))

        let labs = try #require(report.section(.labs))
        let table = try #require(labs.tables.first)
        #expect(table.rows.first?.cells.first == "Fasting glucose")
        #expect(table.rows.first?.flag == .high)
        #expect(table.rows.dropFirst().allSatisfy { $0.flag == .none })
    }

    // MARK: PDF

    /// PDFKit reads the patient's name and a vital back out of the file: the
    /// text is text, not a picture of it. A4 and Letter keep their sizes.
    @Test func pdfHasTextLayer() throws {
        var input = input()
        input.vitals[Self.restingHeartRate] = daily(Self.restingHeartRate, 58, days: 120)
        input.bloodPanels = [blood(5, [("glucose", 7.2)])]
        let report = DoctorReportBuilder.build(input)

        for paper in DoctorReportPaper.allCases {
            let data = DoctorReportRenderer.pdf(report, paper: paper, theme: .standard)
            let document = try #require(PDFDocument(data: data))
            #expect(document.pageCount >= 1)
            let text = document.string ?? ""
            #expect(text.contains("Ada Lovelace"))
            #expect(text.contains("Resting heart rate"))
            #expect(text.contains("Page 1 of \(document.pageCount)"))
            let bounds = try #require(document.page(at: 0)).bounds(for: .mediaBox)
            #expect(abs(bounds.width - paper.size.width) < 1)
            #expect(abs(bounds.height - paper.size.height) < 1)
        }
    }

    /// A long report runs over several pages, each numbered.
    @Test func longReportPaginates() throws {
        var input = input(topics: Set(DoctorReportTopic.allCases))
        input.record.vaccinations = (0..<80).map { Vaccination(name: "Vaccine \($0)", date: daysAgo($0 * 3)) }
        let report = DoctorReportBuilder.build(input)
        let data = DoctorReportRenderer.pdf(report, paper: .a4, theme: .standard)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2)
        let last = try #require(document.page(at: document.pageCount - 1)?.string)
        #expect(last.contains("Page \(document.pageCount) of \(document.pageCount)"))
        #expect(document.string?.contains("Vaccine 79") == true)
    }

    /// Letter for the United States and Canada, A4 elsewhere.
    @Test func paperFollowsRegion() {
        #expect(DoctorReportPaper.forLocale(Locale(identifier: "en_US")) == .letter)
        #expect(DoctorReportPaper.forLocale(Locale(identifier: "en_CA")) == .letter)
        #expect(DoctorReportPaper.forLocale(Locale(identifier: "fr_FR")) == .a4)
        #expect(DoctorReportPaper.forLocale(Locale(identifier: "en_GB")) == .a4)
    }

    // MARK: Period

    /// A panel drawn 200 days ago is in a twelve month report and out of a
    /// ninety day one; so is a questionnaire.
    @Test func periodFiltersValues() {
        var quarter = input(.quarter, topics: DoctorReportTopic.standard.union([.mind]))
        quarter.bloodPanels = [blood(200, [("glucose", 7.2)])]
        quarter.assessments = [MindAssessment(instrument: .gad7, date: daysAgo(200), answers: [1, 1, 1, 1, 1, 1, 1])]
        #expect(DoctorReportBuilder.build(quarter).section(.labs) == nil)
        #expect(DoctorReportBuilder.build(quarter).section(.mind) == nil)

        var year = quarter
        year.period = .year
        #expect(DoctorReportBuilder.build(year).section(.labs) != nil)
        #expect(DoctorReportBuilder.build(year).section(.mind) != nil)
    }

    /// The vitals average only the days inside the period, and the period
    /// before it is the comparison.
    @Test func vitalsAverageThePeriod() throws {
        var input = input(.month)
        input.vitals[Self.restingHeartRate] = daily(Self.restingHeartRate, 60, days: 30)
            + daily(Self.restingHeartRate, 70, days: 60).filter { $0.start < daysAgo(29) }
        let vitals = try #require(DoctorReportBuilder.build(input).section(.vitals))
        let row = try #require(vitals.tables.first?.rows.first { $0.cells.first == "Resting heart rate" })
        #expect(row.cells[1] == "60 bpm")
        #expect(row.cells[3] == "70 bpm")
    }

    // MARK: Sensitive domains

    /// Mind, cycle and DNA stay out, flags included, until their box is
    /// ticked; a positive ninth PHQ-9 item then leads the flags.
    @Test func noSensitiveWithoutConsent() throws {
        var input = input()
        input.assessments = [MindAssessment(instrument: .phq9, date: daysAgo(3), answers: [1, 1, 1, 1, 1, 1, 1, 1, 1])]
        input.cycle = DoctorReportCycle(flowDays: [daysAgo(40), daysAgo(39), daysAgo(12), daysAgo(11)], symptomDays: [.cramps: [daysAgo(12)]], stage: nil)
        input.genome = LabFixtures.genome
        input.bloodPanels = [blood(5, [("glucose", 7.2)])]

        let closed = DoctorReportBuilder.build(input)
        #expect(closed.section(.mind) == nil)
        #expect(closed.section(.cycle) == nil)
        #expect(closed.section(.genome) == nil)
        #expect(!closed.plainText.contains("PHQ"))
        #expect(!closed.plainText.contains("Cramps"))
        #expect(!closed.plainText.contains("23andMe"))

        input.topics.formUnion([.mind, .cycle, .genome])
        let open = DoctorReportBuilder.build(input)
        #expect(open.section(.mind) != nil)
        #expect(open.section(.cycle) != nil)
        #expect(open.section(.genome) != nil)
        let flagged = try #require(open.section(.flagged))
        let first = try #require(flagged.tables.first?.rows.first)
        #expect(first.cells.first == "PHQ-9")
        #expect(first.flag == .attention)
    }

    /// APOE reaches the report only when the person already chose to see it.
    @Test func apoeOnlyWhenRevealed() {
        var input = input(topics: DoctorReportTopic.standard.union([.genome]))
        input.genome = LabFixtures.genome
        input.showsAPOE = false
        #expect(!DoctorReportBuilder.build(input).plainText.contains("APOE"))
        input.showsAPOE = true
        #expect(DoctorReportBuilder.build(input).plainText.contains("APOE"))
    }

    // MARK: Sample

    /// Writes the report the fixtures make to the path in
    /// `DOCTOR_REPORT_SAMPLE`, for a person to read. Off unless the variable
    /// is set (`TEST_RUNNER_DOCTOR_REPORT_SAMPLE` on the xcodebuild line).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOCTOR_REPORT_SAMPLE"] != nil))
    func writesFixtureSample() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["DOCTOR_REPORT_SAMPLE"])
        let now = Date()
        let source = FixtureHealthSource(now: now)
        var input = DoctorReportInput(now: now, period: .quarter, topics: DoctorReportTopic.standard)
        input.patient = DoctorReportPatient(name: "Maya Laurent", birthday: Calendar.current.date(byAdding: .year, value: -41, to: now), sex: .female)
        input.record = MedicalRecordFixtures.record()
        input.bloodPanels = LabFixtures.bloodPanels
        input.urinePanels = LabFixtures.urinePanels
        input.stoolPanels = LabFixtures.stoolPanels
        input.functionalResults = LabFixtures.functionalResults
        input.supplements = [TrackSupplement(name: "Vitamin D3", amount: 2000, unit: .units, minute: 8 * 60, startedOn: now),
                             TrackSupplement(name: "Biotin", amount: 5, unit: .milligrams, minute: 8 * 60, startedOn: now)]
        input.medications = MedicationList.merged(supplements: input.supplements, health: [])
        input.interactionNotes = MedicationInteractions.notes(
            for: input.supplements, markers: LabFixtures.bloodPanels.flatMap(\.markers).map(BloodMarkerCatalog.definition(for:)))
        var profile = SomaProfile()
        profile.birthday = input.patient.birthday
        profile.sex = .female
        let ledger = SomaTools.ScreeningLedger().withFamilyHistory(input.record.screeningRisks)
            .withResults(input.functionalResults.compactMap(\.screeningRecord))
        input.screenings = SomaTools.ScreeningSchedule.due(for: profile, ledger: ledger, now: now)
        input.health = await DoctorReportHealth.read(from: source, period: .quarter, includeCycle: false, now: now)
        let report = DoctorReportBuilder.build(input)
        let data = DoctorReportRenderer.pdf(report, paper: .a4, theme: .standard)
        try data.write(to: URL(fileURLWithPath: path))
        #expect(PDFDocument(data: data)?.string?.contains("Maya Laurent") == true)
    }

    #if canImport(UIKit)
    /// Hosts the page in a window over the lab and record fixtures and the
    /// Health fixture, and writes what it draws, preview included, to the
    /// path in `DOCTOR_REPORT_SCREENSHOT`. Run alone: the fixtures switch the
    /// shared stores, which must not have been read yet.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOCTOR_REPORT_SCREENSHOT"] != nil))
    func capturesPreviewScreenshot() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["DOCTOR_REPORT_SCREENSHOT"])
        UserDefaults.standard.set(true, forKey: LabFixtures.launchKey)
        UserDefaults.standard.set(true, forKey: MedicalRecordFixtures.launchKey)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 3400)
        window.rootViewController = UIHostingController(rootView: NavigationStack { DoctorReportPage() }
            .environment(HealthDashboard(source: FixtureHealthSource()))
            .environment(JournalStore(url: nil)))
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(6))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image {
            window.layer.render(in: $0.cgContext)
        }
        try #require(image.pngData()).write(to: URL(fileURLWithPath: path))
        window.isHidden = true
    }
    #endif
}
