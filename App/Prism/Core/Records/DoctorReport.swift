//
//  DoctorReport.swift
//  Prism
//
//  The report a person takes to their doctor: who they are, the period it
//  covers, what is outside its range first, then each domain Soma holds, as
//  tables with units and reference ranges. Pure: `DoctorReportInput` is plain
//  values gathered by the page, `DoctorReportBuilder` turns them into a
//  `DoctorReport`, and `DoctorReportRenderer` lays that out as a PDF.
//
//  Nothing here sends anything. The PDF is written on the phone and leaves it
//  only through the share sheet, when the person chooses to.
//
//  A domain with nothing in the period is left out, never shown as an empty
//  title. Mood questionnaires, the cycle and the DNA file are sensitive: they
//  are left out, flags included, unless the person ticks them. APOE is left
//  out unless the person already chose to see it on the DNA page. Every line
//  is informational; none of it is a diagnosis.
//

import Foundation
import HealthExportCore

// MARK: - Choices

/// How far back the report reads.
nonisolated enum DoctorReportPeriod: Int, CaseIterable, Identifiable, Sendable {
    case month = 30
    case quarter = 90
    case year = 365

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "12 months"
        }
    }
}

/// A domain the person can put in or leave out.
nonisolated enum DoctorReportTopic: String, CaseIterable, Identifiable, Sendable, Codable {
    case conditions, allergies, medications, vitals, labs, tests, glucose, rhythm, sleepActivity
    case mind, cycle, oral, screenings, vaccinations, familyHistory, genome, careTeam, appointments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conditions: "Conditions"
        case .allergies: "Allergies"
        case .medications: "Medications and supplements"
        case .vitals: "Vital signs"
        case .labs: "Lab results"
        case .tests: "Tests and scans"
        case .glucose: "Glucose"
        case .rhythm: "Heart rhythm and mobility"
        case .sleepActivity: "Sleep and activity"
        case .mind: "Mood and anxiety questionnaires"
        case .cycle: "Menstrual cycle"
        case .oral: "Mouth and teeth"
        case .screenings: "Screenings"
        case .vaccinations: "Vaccinations"
        case .familyHistory: "Family history"
        case .genome: "DNA file"
        case .careTeam: "Care team"
        case .appointments: "Upcoming appointments"
        }
    }

    /// Left out unless the person ticks it: mental health, reproductive
    /// health and genetics.
    var isSensitive: Bool { self == .mind || self == .cycle || self == .genome }

    /// What a new report holds: everything but the sensitive domains.
    static var standard: Set<DoctorReportTopic> { Set(allCases.filter { !$0.isSensitive }) }
}

// MARK: - Input

nonisolated struct DoctorReportPatient: Equatable, Sendable {
    var name: String?
    var birthday: Date?
    var sex: BiologicalSex?
}

/// The cycle as Apple Health holds it: the days with flow and the days each
/// symptom was logged, with the transition stage the signs point to.
nonisolated struct DoctorReportCycle: Equatable, Sendable {
    var flowDays: [Date]
    var symptomDays: [CycleSymptom: [Date]]
    var stage: PerimenopauseStage?
}

/// What Apple Health gives the report, read by ``read(from:period:includeCycle:now:)``.
struct DoctorReportHealth: Sendable {
    /// Samples by HealthKit identifier, from the start of the period before
    /// the chosen one, so each vital has its comparison.
    var vitals: [String: [HealthReading]] = [:]
    var glucose: [HealthReading] = []
    var rhythm = RhythmMobilityReadings()
    var scores: SomaScores?
    var oral: OralSummary?
    var cycle: DoctorReportCycle?
}

/// Everything the report is made from, as plain values.
struct DoctorReportInput: Sendable {
    var now: Date
    var period: DoctorReportPeriod
    var topics: Set<DoctorReportTopic>
    var calendar = Calendar.current
    var patient = DoctorReportPatient()
    var record = MedicalRecord()
    /// The medical card's free text list of medications, which stays with
    /// the card rather than moving into the record.
    var cardMedications = ""
    var bloodPanels: [BloodPanel] = []
    var urinePanels: [UrinePanel] = []
    var stoolPanels: [StoolPanel] = []
    var functionalResults: [FunctionalResult] = []
    /// The merged list: the plan's supplements and Health's medications.
    var medications: [MedicationEntry] = []
    var supplements: [TrackSupplement] = []
    var interactionNotes: [InteractionNote] = []
    var screenings: [SomaTools.ScreeningDue] = []
    var assessments: [MindAssessment] = []
    var genome: GenomeResult?
    /// The person chose to see APOE on the DNA page.
    var showsAPOE = false
    var units = UnitPreferences()
    var health = DoctorReportHealth()

    init(now: Date, period: DoctorReportPeriod, topics: Set<DoctorReportTopic>) {
        self.now = now
        self.period = period
        self.topics = topics
    }

    var vitals: [String: [HealthReading]] {
        get { health.vitals }
        set { health.vitals = newValue }
    }

    var cycle: DoctorReportCycle? {
        get { health.cycle }
        set { health.cycle = newValue }
    }

    /// The period: the last `period.days` days, today whole included.
    var interval: DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return DateInterval(start: start, end: end)
    }

    /// The same length just before it, for "previous period".
    var previousInterval: DateInterval {
        let start = calendar.date(byAdding: .day, value: -period.days, to: interval.start) ?? interval.start
        return DateInterval(start: start, end: interval.start)
    }

    func includes(_ date: Date) -> Bool { date >= interval.start && date <= now }
}

// MARK: - The report

/// How a value sits against its range.
nonisolated enum DoctorReportFlag: String, Sendable {
    case none, low, high
    /// Outside what is usual in a way that is not a number above or below:
    /// a positive item, a fall, an irregular rhythm.
    case attention

    var word: String {
        switch self {
        case .none: ""
        case .low: "Low"
        case .high: "High"
        case .attention: "Check"
        }
    }

    /// Attention first, then high and low together.
    var rank: Int {
        switch self {
        case .attention: 0
        case .high, .low: 1
        case .none: 2
        }
    }
}

nonisolated struct DoctorReportColumn: Equatable, Sendable {
    var title: String
    /// The share of the table's width, before the flag and trend columns.
    var share: Double
    var isNumber = false
}

nonisolated struct DoctorReportRow: Equatable, Sendable {
    var cells: [String]
    var flag: DoctorReportFlag = .none
    /// One value a day, oldest first, for a small line beside the row.
    var trend: [Double?] = []
    /// A line under the row: advice, the item a questionnaire flagged.
    var note: String?
}

nonisolated struct DoctorReportTable: Equatable, Sendable {
    var caption: String?
    var columns: [DoctorReportColumn]
    var rows: [DoctorReportRow]
    /// A column for High, Low and Check.
    var showsFlags = false
    /// A column for each row's line.
    var showsTrend = false
}

nonisolated struct DoctorReportFact: Equatable, Sendable {
    var label: String
    var value: String
    var flag: DoctorReportFlag = .none
}

nonisolated enum DoctorReportBlock: Equatable, Sendable {
    case facts([DoctorReportFact])
    case table(DoctorReportTable)
    case lines([String])
}

nonisolated struct DoctorReportSection: Equatable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case identity
        case flagged
        case topic(DoctorReportTopic)
    }

    var kind: Kind
    var title: String
    /// One sentence under the title: where the numbers come from.
    var note: String?
    var blocks: [DoctorReportBlock]

    var id: Kind { kind }

    var tables: [DoctorReportTable] {
        blocks.compactMap { if case .table(let table) = $0 { table } else { nil } }
    }

    /// Every word of the section, for a search.
    var text: String {
        var parts = [title, note ?? ""]
        for block in blocks {
            switch block {
            case .facts(let facts): parts += facts.flatMap { [$0.label, $0.value] }
            case .lines(let lines): parts += lines
            case .table(let table):
                parts.append(table.caption ?? "")
                parts += table.columns.map(\.title)
                parts += table.rows.flatMap { $0.cells + [$0.note ?? "", $0.flag.word] }
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

nonisolated struct DoctorReport: Equatable, Sendable {
    var title: String
    /// The name on every page's header, a dash without one.
    var patientName: String
    /// "Born 2 Mar 1980" on the header, when known.
    var patientLine: String?
    /// "25 Oct 2026, 10:00".
    var generated: String
    var sections: [DoctorReportSection]
    var disclaimer: String

    func section(_ kind: DoctorReportSection.Kind) -> DoctorReportSection? {
        sections.first { $0.kind == kind }
    }

    func section(_ topic: DoctorReportTopic) -> DoctorReportSection? { section(.topic(topic)) }

    var plainText: String {
        ([title, patientName, patientLine ?? "", generated] + sections.map(\.text) + [disclaimer]).joined(separator: "\n")
    }

    static let disclaimer = "Prepared by the patient with Soma, from their own entries, Apple Health and the lab reports they added. For information only: it is not a diagnosis, values may be incomplete or typed by hand, and ranges are indicative adult ranges unless the lab printed its own. Please confirm anything important with a clinical test."
}

// MARK: - Builder

/// On the main actor, as the questionnaire and mouth readings it formats are.
enum DoctorReportBuilder {
    static func build(_ input: DoctorReportInput) -> DoctorReport {
        var flagged: [(rank: Int, order: Int, row: DoctorReportRow)] = []
        var topics: [DoctorReportSection] = []

        for topic in DoctorReportTopic.allCases where input.topics.contains(topic) {
            guard let built = section(topic, input) else { continue }
            for row in built.flagged {
                flagged.append((row.flag.rank, flagged.count, row))
            }
            topics.append(built.section)
        }

        var sections = [identity(input)]
        if !flagged.isEmpty {
            let rows = flagged.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }.map(\.row)
            sections.append(DoctorReportSection(
                kind: .flagged, title: "Flagged values",
                note: "Outside the reference range, or worth a look, across everything below.",
                blocks: [.table(DoctorReportTable(
                    columns: [col("Item", 0.26), col("Result", 0.22), col("Reference", 0.2), col("Date", 0.14), col("Section", 0.18)],
                    rows: rows, showsFlags: true))]))
        }
        sections += topics

        let format = Format(input)
        return DoctorReport(
            title: "Health summary",
            patientName: input.patient.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "-",
            patientLine: input.patient.birthday.map { "Born \(format.day($0))" },
            generated: "\(format.day(input.now)), \(ScoreMath.clock(input.now, calendar: input.calendar))",
            sections: sections,
            disclaimer: DoctorReport.disclaimer
        )
    }

    /// A built section and the rows it adds to the flagged table.
    struct Built {
        var section: DoctorReportSection
        var flagged: [DoctorReportRow] = []
    }

    static func section(_ topic: DoctorReportTopic, _ input: DoctorReportInput) -> Built? {
        let format = Format(input)
        switch topic {
        case .conditions: return conditions(input, format)
        case .allergies: return allergies(input)
        case .medications: return medications(input, format)
        case .vitals: return vitals(input, format)
        case .labs: return labs(input, format)
        case .tests: return tests(input, format)
        case .glucose: return glucose(input, format)
        case .rhythm: return rhythm(input, format)
        case .sleepActivity: return sleepActivity(input, format)
        case .mind: return mind(input, format)
        case .cycle: return cycle(input, format)
        case .oral: return oral(input, format)
        case .screenings: return screenings(input, format)
        case .vaccinations: return vaccinations(input, format)
        case .familyHistory: return familyHistory(input)
        case .genome: return genome(input, format)
        case .careTeam: return careTeam(input)
        case .appointments: return appointments(input, format)
        }
    }

    static func col(_ title: String, _ share: Double, number: Bool = false) -> DoctorReportColumn {
        DoctorReportColumn(title: title, share: share, isNumber: number)
    }

    private static func make(_ topic: DoctorReportTopic, note: String? = nil, _ blocks: [DoctorReportBlock],
                             flagged: [DoctorReportRow] = []) -> Built? {
        let kept = blocks.filter { block in
            switch block {
            case .facts(let facts): !facts.isEmpty
            case .lines(let lines): !lines.isEmpty
            case .table(let table): !table.rows.isEmpty
            }
        }
        guard !kept.isEmpty else { return nil }
        return Built(section: DoctorReportSection(kind: .topic(topic), title: topic.title, note: note, blocks: kept),
                     flagged: flagged)
    }

    /// A row of the flagged table.
    private static func flag(_ item: String, result: String, reference: String?, date: Date?,
                             _ topic: DoctorReportTopic, _ flag: DoctorReportFlag, _ format: Format,
                             when: String? = nil) -> DoctorReportRow {
        DoctorReportRow(cells: [item, result, reference ?? "-", when ?? date.map(format.day) ?? "-", topic.title], flag: flag)
    }

    // MARK: Identity

    static func identity(_ input: DoctorReportInput) -> DoctorReportSection {
        let format = Format(input)
        let patient = input.patient
        var facts = [DoctorReportFact(label: "Name", value: patient.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Not given")]
        if let birthday = patient.birthday {
            let age = input.calendar.dateComponents([.year], from: birthday, to: input.now).year
            facts.append(DoctorReportFact(label: "Date of birth", value: format.day(birthday) + (age.map { ", \($0) years" } ?? "")))
        }
        if let sex = patient.sex {
            facts.append(DoctorReportFact(label: "Sex", value: sex.title))
        }
        let interval = input.interval
        facts.append(DoctorReportFact(label: "Period", value: "\(format.day(interval.start)) to \(format.day(input.now)), \(input.period.title)"))
        facts.append(DoctorReportFact(label: "Prepared", value: "\(format.day(input.now)) at \(ScoreMath.clock(input.now, calendar: input.calendar)), on the patient's phone"))
        return DoctorReportSection(kind: .identity, title: "Patient", note: nil, blocks: [.facts(facts)])
    }

    // MARK: Record

    static func conditions(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let rows = input.record.conditions.map {
            DoctorReportRow(cells: [$0.name, $0.since.map(format.monthYear) ?? "-", $0.notes?.nonEmpty ?? "-"])
        }
        return make(.conditions, note: "As the patient lists them.",
                    [.table(DoctorReportTable(columns: [col("Condition", 0.4), col("Since", 0.2), col("Notes", 0.4)], rows: rows))])
    }

    static func allergies(_ input: DoctorReportInput) -> Built? {
        let order: [Allergy.Severity?] = [.severe, .moderate, .mild, nil]
        let rows = input.record.allergies
            .sorted { (order.firstIndex(of: $0.severity) ?? 3) < (order.firstIndex(of: $1.severity) ?? 3) }
            .map { DoctorReportRow(cells: [$0.substance, $0.reaction?.nonEmpty ?? "-", $0.severity?.title ?? "-"]) }
        return make(.allergies, [.table(DoctorReportTable(columns: [col("Substance", 0.4), col("Reaction", 0.4), col("Severity", 0.2)], rows: rows))])
    }

    static func vaccinations(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let rows = input.record.vaccinations.sorted { $0.date > $1.date }.map {
            DoctorReportRow(cells: [$0.name, $0.dose?.nonEmpty ?? "-", format.day($0.date)])
        }
        return make(.vaccinations, [.table(DoctorReportTable(columns: [col("Vaccine", 0.45), col("Dose", 0.35), col("Date", 0.2)], rows: rows))])
    }

    static func familyHistory(_ input: DoctorReportInput) -> Built? {
        let rows = input.record.familyHistory.map { entry in
            let condition = entry.condition == .other ? (entry.note?.nonEmpty ?? entry.condition.title) : entry.condition.title
            return DoctorReportRow(cells: [entry.relative.title, condition, entry.ageAtOnset.map { "\($0)" } ?? "-"])
        }
        return make(.familyHistory, [.table(DoctorReportTable(columns: [col("Relative", 0.3), col("Condition", 0.5), col("Age at onset", 0.2, number: true)], rows: rows))])
    }

    static func careTeam(_ input: DoctorReportInput) -> Built? {
        let rows = input.record.careTeam.map {
            DoctorReportRow(cells: [$0.name, $0.role.title, $0.phone?.nonEmpty ?? "-", $0.email?.nonEmpty ?? "-"])
        }
        return make(.careTeam, [.table(DoctorReportTable(columns: [col("Name", 0.3), col("Role", 0.2), col("Phone", 0.22), col("Email", 0.28)], rows: rows))])
    }

    static func appointments(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let record = input.record
        let rows = record.upcoming(now: input.now).map { appointment in
            let who = appointment.with.nonEmpty ?? record.member(appointment.careTeamID)?.name ?? "-"
            return DoctorReportRow(cells: [format.day(appointment.date), ScoreMath.clock(appointment.date, calendar: input.calendar),
                                           who, appointment.reason.title])
        }
        return make(.appointments, [.table(DoctorReportTable(columns: [col("Date", 0.2), col("Time", 0.12), col("With", 0.4), col("For", 0.28)], rows: rows))])
    }

    // MARK: Medications

    static func medications(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let rows = input.medications.map { entry -> DoctorReportRow in
            let supplement = input.supplements.first { $0.id == entry.supplementID }
            let dose = supplement.map { s in
                let decimals = s.amount.rounded() == s.amount ? 0 : LabMath.decimals(for: s.amount)
                return "\(LabMath.format(s.amount, decimals: decimals) ?? "-") \(s.unit.symbol)"
            } ?? "-"
            let schedule = supplement.map { cadence($0.cadence, calendar: input.calendar) + " at " + ScoreMath.clock(Double($0.minute) / 60) } ?? "-"
            let from: String = switch (entry.supplementID != nil, entry.healthID != nil) {
            case (true, true): "Soma plan and Apple Health"
            case (false, true): "Apple Health"
            default: "Soma plan"
            }
            return DoctorReportRow(cells: [entry.name, dose, schedule, from])
        }
        var lines: [String] = []
        if let card = input.cardMedications.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            lines.append("On the medical card: \(card)")
        }
        for note in MedicationInteractions.folded(input.interactionNotes) {
            lines.append("\(note.supplement) and \(note.subject): \(note.text) Source: \(note.source).")
        }
        return make(.medications, note: "What the patient lists; doses and schedules as they entered them.", [
            .table(DoctorReportTable(columns: [col("Name", 0.34), col("Dose", 0.16, number: true), col("Schedule", 0.26), col("From", 0.24)], rows: rows)),
            .lines(lines),
        ])
    }

    static func cadence(_ cadence: TrackCadence, calendar: Calendar) -> String {
        switch cadence.kind {
        case .daily:
            return "Daily"
        case .weekly:
            let symbols = calendar.weekdaySymbols
            guard let weekday = cadence.weekday, symbols.indices.contains(weekday - 1) else { return "Weekly" }
            return "Weekly, \(symbols[weekday - 1])"
        case .everyNDays:
            return cadence.intervalDays.map { "Every \($0) days" } ?? "Every few days"
        case .cycleOnOff:
            guard let on = cadence.onDays, let off = cadence.offDays else { return "In cycles" }
            return "\(on) days on, \(off) off"
        }
    }

    // MARK: Vitals

    static func vitals(_ input: DoctorReportInput, _ format: Format) -> Built? {
        var rows: [DoctorReportRow] = []
        var flagged: [DoctorReportRow] = []
        for vital in DoctorReportVital.allCases {
            guard let row = vitalRow(vital, input) else { continue }
            rows.append(row)
            if row.flag != .none {
                flagged.append(flag(vital.title, result: row.cells[1], reference: row.cells[4], date: nil, .vitals, row.flag, format,
                                    when: "\(input.period.title) average"))
            }
        }
        return make(.vitals, note: "Daily values from Apple Health, averaged over the period. Previous is the same length just before it.",
                    [.table(DoctorReportTable(
                        columns: [col("Measure", 0.27), col("Average", 0.17, number: true), col("Range", 0.2, number: true),
                                  col("Previous", 0.17, number: true), col("Reference", 0.19)],
                        rows: rows, showsFlags: true, showsTrend: true))],
                    flagged: flagged)
    }

    static func vitalRow(_ vital: DoctorReportVital, _ input: DoctorReportInput) -> DoctorReportRow? {
        let measures = input.units.measures
        func series(_ id: String, _ interval: DateInterval) -> [Double?] {
            daily(input.vitals[id] ?? [], in: interval, total: vital.isDailyTotal, calendar: input.calendar)
                .map { $0.map { vital.shown($0, measures: measures) } }
        }
        let unit = vital.unit(measures)
        let current = series(vital.identifier, input.interval)
        guard let average = mean(current) else { return nil }
        let previous = mean(series(vital.identifier, input.previousInterval))
        let present = current.compactMap { $0 }

        if vital == .bloodPressure {
            let lower = series(DoctorReportVital.diastolicID, input.interval)
            let lowerAverage = mean(lower)
            let lowerPrevious = mean(series(DoctorReportVital.diastolicID, input.previousInterval))
            let lowerPresent = lower.compactMap { $0 }
            func pair(_ a: Double?, _ b: Double?) -> String? {
                guard let a else { return nil }
                return "\(vital.number(a))/\(b.map(vital.number) ?? "-") \(unit)"
            }
            // AHA 2017: under 120/80 is normal; 130/80 and up is the first
            // stage of high blood pressure.
            let high = average >= 130 || (lowerAverage ?? 0) >= 80
            let range = (present.min(), present.max(), lowerPresent.min(), lowerPresent.max())
            let rangeText = range.0.map { low in
                "\(vital.number(low))/\(range.2.map(vital.number) ?? "-") to \(vital.number(range.1 ?? low))/\(range.3.map(vital.number) ?? "-")"
            } ?? "-"
            return DoctorReportRow(cells: [vital.title, pair(average, lowerAverage) ?? "-", rangeText,
                                           pair(previous, lowerPrevious) ?? "-", vital.reference ?? "-"],
                                   flag: high ? .high : .none, trend: current)
        }

        var flag = DoctorReportFlag.none
        if let band = vital.band {
            if average < band.lowerBound { flag = .low } else if average > band.upperBound { flag = .high }
        }
        let range = present.count > 1 ? "\(vital.number(present.min() ?? average)) to \(vital.number(present.max() ?? average))" : "-"
        let space = unit == "%" ? "" : " "
        return DoctorReportRow(cells: [vital.title, vital.number(average) + space + unit, range,
                                       previous.map { vital.number($0) + space + unit } ?? "-", vital.reference ?? "-"],
                               flag: flag, trend: current)
    }

    /// One value a day across `interval`, oldest first: each day's mean, or
    /// its total for a count. Nil for a day with nothing.
    static func daily(_ readings: [HealthReading], in interval: DateInterval, total: Bool, calendar: Calendar) -> [Double?] {
        let first = calendar.startOfDay(for: interval.start)
        let count = max(1, calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: interval.end)).day ?? 0)
        var sums = Array(repeating: 0.0, count: count)
        var counts = Array(repeating: 0, count: count)
        for reading in readings where reading.start >= interval.start && reading.start < interval.end {
            guard let index = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: reading.start)).day,
                  sums.indices.contains(index) else { continue }
            sums[index] += reading.value
            counts[index] += 1
        }
        return zip(sums, counts).map { sum, n in n == 0 ? nil : (total ? sum : sum / Double(n)) }
    }

    static func mean(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
    }

    // MARK: Labs

    static func labs(_ input: DoctorReportInput, _ format: Format) -> Built? {
        var blocks: [DoctorReportBlock] = []
        var flagged: [DoctorReportRow] = []

        let blood = input.bloodPanels.sorted { $0.date > $1.date }
        if let panel = blood.first(where: { input.includes($0.date) }) {
            let earlier = blood.first { $0.date < panel.date }
            var rows: [DoctorReportRow] = []
            for value in panel.markers {
                let marker = BloodMarkerCatalog.definition(for: value)
                let reading = LabMath.reading(value)
                let result = LabMath.format(reading.value, decimals: LabMath.decimals(for: reading.value)) ?? "-"
                let reference = bloodReference(value, marker: marker, reading: reading)
                let flag: DoctorReportFlag = switch reading.status {
                case .high: .high
                case .low: .low
                default: .none
                }
                let previous = earlier?.value(value.key).map { old in
                    let shown = LabMath.reading(old).value
                    return LabMath.format(shown, decimals: LabMath.decimals(for: shown)) ?? "-"
                }
                rows.append(DoctorReportRow(cells: [marker.name, result, reading.unit, reference, previous ?? "-"], flag: flag))
                if flag != .none {
                    flagged.append(self.flag(marker.name, result: "\(result) \(reading.unit)", reference: reference, date: panel.date, .labs, flag, format))
                }
            }
            let caption = "Blood, drawn \(format.day(panel.date))" + (earlier.map { ". Previous panel \(format.day($0.date))" } ?? "")
            blocks.append(.table(DoctorReportTable(
                caption: caption,
                columns: [col("Marker", 0.32), col("Result", 0.15, number: true), col("Unit", 0.15), col("Reference", 0.22), col("Previous", 0.16, number: true)],
                rows: flaggedFirst(rows), showsFlags: true)))
        }

        if let panel = input.urinePanels.sorted(by: { $0.date > $1.date }).first(where: { input.includes($0.date) }) {
            let rows = panel.values.map { value -> DoctorReportRow in
                let flag: DoctorReportFlag = switch value.status {
                case .high: .high
                case .low: .low
                default: .none
                }
                let name = value.marker?.name ?? value.key
                if flag != .none {
                    flagged.append(self.flag("Urine \(name.lowercased())", result: value.text, reference: value.marker?.usual, date: panel.date, .labs, flag, format))
                }
                return DoctorReportRow(cells: [name, value.text, value.marker?.usual ?? "-"], flag: flag)
            }
            let kind = panel.isApproximate ? "home dipstick read by the phone's camera, approximate" : "lab report"
            blocks.append(.table(DoctorReportTable(
                caption: "Urine, \(kind), \(format.day(panel.date))",
                columns: [col("Marker", 0.4), col("Result", 0.25, number: true), col("Usual", 0.35)],
                rows: flaggedFirst(rows), showsFlags: true)))
        }

        if let panel = input.stoolPanels.sorted(by: { $0.date > $1.date }).first(where: { input.includes($0.date) }) {
            let rows = panel.values.map { value -> DoctorReportRow in
                let flag: DoctorReportFlag = switch value.flag {
                case .actNow: .attention
                case .elevated, .borderline: .high
                case .low: .low
                default: .none
                }
                let name = value.marker?.name ?? value.key
                if flag != .none {
                    flagged.append(self.flag(name, result: value.text, reference: value.marker?.usual, date: panel.date, .labs, flag, format))
                }
                return DoctorReportRow(cells: [name, value.text, value.marker?.usual ?? "-"], flag: flag,
                                       note: value.flag.needsClinician ? value.advice : nil)
            }
            let kind = panel.kind == .microbiomeKit ? "microbiome kit" : "lab report"
            blocks.append(.table(DoctorReportTable(
                caption: "Stool, \(kind), \(format.day(panel.date))",
                columns: [col("Marker", 0.4), col("Result", 0.25, number: true), col("Usual", 0.35)],
                rows: flaggedFirst(rows), showsFlags: true)))
        }

        return make(.labs, note: "The latest of each test in the period. Ranges are the lab's own where it printed one, otherwise indicative adult ranges.",
                    blocks, flagged: flagged)
    }

    /// The lab's printed range when it is in the unit shown, otherwise the
    /// catalog's indicative one.
    static func bloodReference(_ value: BloodMarkerValue, marker: BloodMarker, reading: LabMath.MarkerReading) -> String {
        let sameUnit = BloodMarkerCatalog.normalize(value.enteredUnit) == BloodMarkerCatalog.normalize(reading.unit)
        let printed = sameUnit && (value.labRefLow != nil || value.labRefHigh != nil)
        let low = printed ? value.labRefLow : reading.low
        let high = printed ? value.labRefHigh : reading.high
        // A catalog range converted out of its storage unit carries the
        // conversion's noise (70.3 mg/dL); above ten it reads whole, as the
        // value beside it does.
        let converted = !printed && BloodMarkerCatalog.normalize(marker.storageUnit) != BloodMarkerCatalog.normalize(marker.displayUnit)
        func text(_ x: Double) -> String {
            LabMath.format(x, decimals: converted && abs(x) >= 10 ? 0 : LabMath.decimals(for: x)) ?? "-"
        }
        switch (low, high) {
        case let (low?, high?) where low > 0: return "\(text(low)) to \(text(high))"
        case let (_, high?): return "Under \(text(high))"
        case let (low?, nil): return "Over \(text(low))"
        default: return "-"
        }
    }

    /// Flagged rows first, the rest in the order they came.
    static func flaggedFirst(_ rows: [DoctorReportRow]) -> [DoctorReportRow] {
        rows.enumerated().sorted { ($0.element.flag.rank, $0.offset) < ($1.element.flag.rank, $1.offset) }.map(\.element)
    }

    // MARK: Tests and scans

    static func tests(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let sex: LabSex? = switch input.patient.sex {
        case .male: .male
        case .female: .female
        default: nil
        }
        var rows: [DoctorReportRow] = []
        var flagged: [DoctorReportRow] = []
        for kind in FunctionalTestKind.allCases {
            guard let result = input.functionalResults.filter({ $0.kind == kind && input.includes($0.date) })
                .max(by: { $0.date < $1.date }) else { continue }
            for field in kind.fields {
                guard let value = result.values[field.id],
                      let text = field.text(value, measures: input.units.measures) else { continue }
                let note = FunctionalAssessment.note(field: field.id, value: value, sex: sex)
                let flag: DoctorReportFlag = note?.isFlagged == true ? .attention : .none
                // "VO2 max, lab test" rather than "VO2 max, lab test, VO2 max".
                let name = kind.title.lowercased().contains(field.name.lowercased()) ? kind.title : "\(kind.title), \(field.name)"
                rows.append(DoctorReportRow(cells: [name, text, note?.text ?? "-", format.day(result.date)], flag: flag))
                if flag != .none {
                    flagged.append(self.flag(name, result: text, reference: note?.text, date: result.date, .tests, flag, format))
                }
            }
        }
        return make(.tests, [.table(DoctorReportTable(
            columns: [col("Measure", 0.36), col("Result", 0.18, number: true), col("Reads as", 0.3), col("Date", 0.16)],
            rows: rows, showsFlags: true))], flagged: flagged)
    }

    // MARK: Glucose

    static func glucose(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let unit = input.units.glucose
        let samples = input.health.glucose.filter { input.includes($0.start) && $0.value > 0 }
        guard !samples.isEmpty else { return nil }
        let fortnightStart = input.calendar.date(byAdding: .day, value: -14, to: input.now) ?? input.now
        let summary = GlucoseSummary.make(samples: samples.filter { $0.start >= fortnightStart }, meals: [], unit: unit,
                                          now: input.now, calendar: input.calendar)
        var facts: [DoctorReportFact] = []
        var flagged: [DoctorReportRow] = []
        func percent(_ share: Double?) -> String { share.map { "\(LabMath.format($0 * 100, decimals: $0 < 0.1 ? 1 : 0) ?? "-")%" } ?? "-" }

        if summary.isContinuous {
            // Battelino et al., Diabetes Care 2019;42:1593: more than 70 % in
            // 70 to 180 mg/dL, under 4 % below 70, under 1 % below 54.
            let lowShare = (summary.timeBelow70 ?? 0) > 0.04
            let veryLowShare = (summary.timeBelow54 ?? 0) > 0.01
            let inRangeLow = (summary.timeInRange ?? 1) < 0.7
            facts += [
                DoctorReportFact(label: "Time in range, \(unit.text(milligrams: GlucoseRange.low)) to \(unit.label(milligrams: GlucoseRange.high))",
                                 value: percent(summary.timeInRange), flag: inRangeLow ? .low : .none),
                DoctorReportFact(label: "Below \(unit.label(milligrams: GlucoseRange.low))", value: percent(summary.timeBelow70), flag: lowShare ? .high : .none),
                DoctorReportFact(label: "Below \(unit.label(milligrams: GlucoseRange.veryLow))", value: percent(summary.timeBelow54), flag: veryLowShare ? .high : .none),
                DoctorReportFact(label: "Above \(unit.label(milligrams: GlucoseRange.high))", value: percent(summary.timeAbove180)),
                DoctorReportFact(label: "Average", value: summary.averageMilligrams.map(unit.label) ?? "-"),
                DoctorReportFact(label: "GMI", value: summary.gmi.map { "\(LabMath.format($0, decimals: 1) ?? "-")%" } ?? "-"),
                DoctorReportFact(label: "Coefficient of variation", value: summary.cv.map { "\(LabMath.format($0, decimals: 0) ?? "-")%" } ?? "-"),
            ]
            if veryLowShare {
                flagged.append(flag("Glucose below \(unit.label(milligrams: GlucoseRange.veryLow))", result: percent(summary.timeBelow54),
                                    reference: "Under 1% (consensus)", date: input.now, .glucose, .high, format))
            } else if lowShare {
                flagged.append(flag("Glucose below \(unit.label(milligrams: GlucoseRange.low))", result: percent(summary.timeBelow70),
                                    reference: "Under 4% (consensus)", date: input.now, .glucose, .high, format))
            }
            if inRangeLow {
                flagged.append(flag("Glucose time in range", result: percent(summary.timeInRange),
                                    reference: "Over 70% (consensus)", date: input.now, .glucose, .low, format))
            }
        } else {
            let values = samples.map(\.value)
            facts += [
                DoctorReportFact(label: "Readings", value: "\(values.count)"),
                DoctorReportFact(label: "Average", value: unit.label(milligrams: values.reduce(0, +) / Double(values.count))),
                DoctorReportFact(label: "Lowest", value: unit.label(milligrams: values.min() ?? 0)),
                DoctorReportFact(label: "Highest", value: unit.label(milligrams: values.max() ?? 0)),
            ]
            if let lowest = values.min(), lowest < GlucoseRange.veryLow {
                flagged.append(flag("Glucose reading", result: unit.label(milligrams: lowest),
                                    reference: "Over \(unit.label(milligrams: GlucoseRange.veryLow))",
                                    date: samples.min { $0.value < $1.value }?.start, .glucose, .low, format))
            }
        }
        let note = summary.isContinuous
            ? "A continuous monitor's last 14 days, read against the 2019 international consensus on time in range."
            : "Single readings in the period, from Apple Health."
        return make(.glucose, note: note, [.facts(facts)], flagged: flagged)
    }

    // MARK: Rhythm and mobility

    static func rhythm(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let rhythm = input.health.rhythm.rhythm(now: input.now, calendar: input.calendar)
        let mobility = input.health.rhythm.mobility(now: input.now, calendar: input.calendar)
        var facts: [DoctorReportFact] = []
        var flagged: [DoctorReportRow] = []
        if let latest = rhythm.weeks.last {
            facts.append(DoctorReportFact(label: "AFib History, week of \(format.day(latest.start))",
                                          value: HeartRhythmSummary.burdenText(latest.burden)))
        }
        if mobility.steadiness != nil {
            let share = mobility.steadiness.map { " (\(Int(($0 * 100).rounded()))%)" } ?? ""
            let flag: DoctorReportFlag = mobility.level == .low || mobility.level == .veryLow ? .low : .none
            facts.append(DoctorReportFact(label: "Walking steadiness", value: mobility.level.title + share, flag: flag))
            if flag != .none {
                flagged.append(self.flag("Walking steadiness", result: mobility.level.title + share, reference: "OK, 40% and up (Apple)",
                                         date: input.now, .rhythm, flag, format))
            }
        }
        let falls = mobility.falls.filter { input.includes($0.start) }
        if !falls.isEmpty {
            let count = Int(falls.reduce(0) { $0 + $1.value }.rounded())
            let last = falls.map(\.start).max()
            facts.append(DoctorReportFact(label: "Falls detected by the watch", value: "\(count), last \(last.map(format.day) ?? "-")", flag: .attention))
            flagged.append(flag("Falls detected", result: "\(count)", reference: nil, date: last, .rhythm, .attention, format))
        }
        if let support = mobility.doubleSupport {
            facts.append(DoctorReportFact(label: "Double support time", value: "\(Int((support * 100).rounded()))%"))
        }
        if let asymmetry = mobility.asymmetry {
            facts.append(DoctorReportFact(label: "Walking asymmetry", value: "\(Int((asymmetry * 100).rounded()))%"))
        }

        let events = rhythm.events.filter { input.includes($0.date) }
        let rows = events.map { event in
            DoctorReportRow(cells: [event.kind.title, "\(format.day(event.date)), \(ScoreMath.clock(event.date, calendar: input.calendar))", event.kind.detail],
                            flag: event.kind == .irregular ? .attention : .none)
        }
        if let irregular = events.first(where: { $0.kind == .irregular }) {
            let count = events.filter { $0.kind == .irregular }.count
            flagged.append(flag("Irregular rhythm notifications", result: "\(count)", reference: nil, date: irregular.date, .rhythm, .attention, format))
        }
        return make(.rhythm, note: "From Apple Watch and iPhone, as Apple Health records them.", [
            .facts(facts),
            .table(DoctorReportTable(caption: "Notifications in the period",
                                     columns: [col("Notification", 0.28), col("When", 0.24), col("What set it off", 0.48)],
                                     rows: rows, showsFlags: true)),
        ], flagged: flagged)
    }

    // MARK: Sleep and activity

    static func sleepActivity(_ input: DoctorReportInput, _ format: Format) -> Built? {
        var rows: [DoctorReportRow] = []
        let days = input.period.days
        func row(_ title: String, _ series: [Double?], unit: String, decimals: Int) {
            let window = Array(series.suffix(days))
            let present = window.compactMap { $0 }
            guard let average = mean(window) else { return }
            func text(_ x: Double) -> String { LabMath.format(x, decimals: decimals) ?? "-" }
            let suffix = unit.isEmpty ? "" : " \(unit)"
            rows.append(DoctorReportRow(cells: [title, text(average) + suffix,
                                                present.count > 1 ? "\(text(present.min() ?? average)) to \(text(present.max() ?? average))" : "-",
                                                "\(present.count)"], trend: window))
        }
        if let scores = input.health.scores {
            row("Hours asleep", scores.detail.sleepHours, unit: "h", decimals: 1)
            row("Sleep score", scores.detail.sleep, unit: "", decimals: 0)
            row("Recovery score", scores.detail.recovery, unit: "", decimals: 0)
            row("Stress score", scores.detail.stress, unit: "", decimals: 0)
        }
        let steps = daily(input.vitals[DoctorReportVital.stepsID] ?? [], in: input.interval, total: true, calendar: input.calendar)
        row("Steps a day", steps, unit: "", decimals: 0)
        let note = "Scores are Soma's, 0 to 100, worked out on the phone from Apple Health; sleep reads at most the last 90 nights."
        return make(.sleepActivity, note: note, [.table(DoctorReportTable(
            columns: [col("Measure", 0.34), col("Average", 0.22, number: true), col("Range", 0.26, number: true), col("Days", 0.18, number: true)],
            rows: rows, showsTrend: true))])
    }

    // MARK: Mind

    static func mind(_ input: DoctorReportInput, _ format: Format) -> Built? {
        var rows: [DoctorReportRow] = []
        var flagged: [DoctorReportRow] = []
        let answered = input.assessments.filter { $0.isComplete && input.includes($0.date) }.sorted { $0.date > $1.date }
        for assessment in answered {
            guard let reading = assessment.reading else { continue }
            var flag: DoctorReportFlag = assessment.severity?.suggestsCare == true ? .attention : .none
            var note: String?
            if assessment.needsCrisisCare {
                flag = .attention
                let answer = assessment.instrument.options[min(assessment.answers[8], assessment.instrument.maxAnswer)]
                note = "Item 9 (thoughts of being better off dead or of self harm) answered \"\(answer)\"."
                flagged.append(self.flag(assessment.instrument.title, result: "Item 9: \(answer)", reference: "Not at all",
                                         date: assessment.date, .mind, .attention, format))
            } else if flag != .none {
                flagged.append(self.flag(assessment.instrument.title, result: "\(reading.value) \(reading.unit), \(reading.word)",
                                         reference: nil, date: assessment.date, .mind, flag, format))
            }
            rows.append(DoctorReportRow(cells: [assessment.instrument.title, "\(reading.value) \(reading.unit)", reading.word, format.day(assessment.date)],
                                        flag: flag, note: note))
        }
        return make(.mind, note: "Screening questionnaires the patient answered in Soma. A score is not a diagnosis.", [
            .table(DoctorReportTable(columns: [col("Questionnaire", 0.3), col("Score", 0.2, number: true), col("Band", 0.3), col("Date", 0.2)],
                                     rows: rows, showsFlags: true)),
        ], flagged: flagged)
    }

    // MARK: Cycle

    static func cycle(_ input: DoctorReportInput, _ format: Format) -> Built? {
        guard let cycle = input.cycle else { return nil }
        let calendar = input.calendar
        let periods = CycleHistory.periods(flowDays: cycle.flowDays, today: input.now, calendar: calendar)
        var facts: [DoctorReportFact] = []
        if let last = periods.last {
            facts.append(DoctorReportFact(label: "Last period started", value: format.day(last.start)))
        }
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: input.now) ?? input.now
        let recent = periods.filter { $0.start >= yearAgo }
        let lengths = CycleHistory.cycleLengths(recent, calendar: calendar).sorted()
        if !lengths.isEmpty {
            let median = lengths[lengths.count / 2]
            let range = lengths.count > 1 ? ", \(lengths.first ?? median) to \(lengths.last ?? median)" : ""
            facts.append(DoctorReportFact(label: "Cycle length, last 12 months",
                                          value: "\(median) days\(range), \(lengths.count) cycle\(lengths.count == 1 ? "" : "s")"))
        }
        let durations = recent.compactMap(\.days)
        if !durations.isEmpty {
            let average = Double(durations.reduce(0, +)) / Double(durations.count)
            facts.append(DoctorReportFact(label: "Period length", value: "\(LabMath.format(average, decimals: 0) ?? "-") days on average"))
        }
        let symptoms = CycleSymptom.allCases.compactMap { symptom -> String? in
            let days = Set((cycle.symptomDays[symptom] ?? []).filter(input.includes).map { calendar.startOfDay(for: $0) }).count
            return days == 0 ? nil : "\(symptom.title) \(days) day\(days == 1 ? "" : "s")"
        }
        if !symptoms.isEmpty {
            facts.append(DoctorReportFact(label: "Symptoms logged in the period", value: symptoms.joined(separator: ", ")))
        }
        if let stage = cycle.stage, stage != .none {
            let words: String = switch stage {
            case .earlyTransition: "the early menopause transition"
            case .lateTransition: "the late menopause transition"
            case .postmenopause: "postmenopause"
            case .none: ""
            }
            facts.append(DoctorReportFact(label: "Signs consistent with", value: "\(words) (STRAW+10), from cycles and symptoms only"))
        }
        return make(.cycle, note: "From Apple Health's cycle tracking.", [.facts(facts)])
    }

    // MARK: Mouth

    static func oral(_ input: DoctorReportInput, _ format: Format) -> Built? {
        guard let oral = input.health.oral, !oral.isEmpty else { return nil }
        var facts: [DoctorReportFact] = []
        let window = OralSummary.windowDays
        if let days = oral.brushedDays { facts.append(DoctorReportFact(label: "Days with a brushing", value: "\(days) of \(window)")) }
        if let twice = oral.brushedTwiceDays { facts.append(DoctorReportFact(label: "Days brushed twice", value: "\(twice) of \(window)")) }
        if let seconds = oral.averageSeconds { facts.append(DoctorReportFact(label: "Average brushing", value: OralSummary.duration(seconds) ?? "-")) }
        if let floss = oral.flossDays { facts.append(DoctorReportFact(label: "Days flossed", value: "\(floss)")) }
        if let bleed = oral.gumBleedDays { facts.append(DoctorReportFact(label: "Days gums bled", value: "\(bleed)")) }
        if let visit = oral.lastVisit { facts.append(DoctorReportFact(label: "Last dental visit", value: format.day(visit))) }
        if let next = oral.nextVisit { facts.append(DoctorReportFact(label: "Next dental visit", value: format.day(next))) }
        return make(.oral, note: "The last \(window) days, from a connected toothbrush and the patient's journal.", [.facts(facts)])
    }

    // MARK: Screenings

    static func screenings(_ input: DoctorReportInput, _ format: Format) -> Built? {
        let rows = input.screenings.filter { $0.state != .later }.map { due -> DoctorReportRow in
            let state: String = switch due.state {
            case .overdue: "Overdue"
            case .soon: "Due soon"
            case .later: "Later"
            case .done: "Up to date"
            }
            // Never recorded and past its start age: due now, not on the
            // birthday it first came due decades ago.
            let next = due.state == .overdue && due.lastDone == nil ? "Now" : due.dueDate.map(format.day) ?? "-"
            return DoctorReportRow(cells: [due.item.title, state, due.lastDone.map(format.day) ?? "Not recorded", next],
                                   flag: due.state == .overdue ? .attention : .none)
        }
        return make(.screenings, note: "Recommended for age and sex on USPSTF cadences, adjusted for family history.", [
            .table(DoctorReportTable(columns: [col("Screening", 0.4), col("Status", 0.18), col("Last done", 0.21), col("Next due", 0.21)],
                                     rows: rows, showsFlags: true)),
        ])
    }

    // MARK: DNA

    static func genome(_ input: DoctorReportInput, _ format: Format) -> Built? {
        guard let genome = input.genome else { return nil }
        var rows = genome.found.compactMap { variant -> DoctorReportRow? in
            guard let genotype = genome.genotype(variant) else { return nil }
            return DoctorReportRow(cells: [variant.gene, variant.id, genotype, variant.meaning(of: genotype)?.headline ?? variant.trait])
        }
        // APOE only when the person chose to see it on the DNA page.
        if input.showsAPOE, let apoe = genome.apoe {
            rows.append(DoctorReportRow(cells: ["APOE", "rs429358, rs7412", apoe.type.rawValue + (apoe.isAmbiguous ? ", or e1/e3" : ""),
                                                apoe.type.meaning.headline]))
        }
        let build = genome.build.map { ", \($0)" } ?? ""
        return make(.genome, note: "A consumer DNA file, not a clinical genetic test. Only the variants Soma reads are listed.", [
            .table(DoctorReportTable(caption: "\(genome.provider.title)\(build), imported \(format.day(genome.importedAt))",
                                     columns: [col("Gene", 0.14), col("Variant", 0.2), col("Genotype", 0.16), col("Linked to", 0.5)],
                                     rows: rows)),
        ])
    }
}

// MARK: - Vitals

/// The vital signs the report reads, with the reference each is held to.
nonisolated enum DoctorReportVital: String, CaseIterable, Sendable {
    case restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    case bloodPressure = "HKQuantityTypeIdentifierBloodPressureSystolic"
    case oxygen = "HKQuantityTypeIdentifierOxygenSaturation"
    case respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
    case hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    case vo2Max = "HKQuantityTypeIdentifierVO2Max"
    case weight = "HKQuantityTypeIdentifierBodyMass"
    case bmi = "HKQuantityTypeIdentifierBodyMassIndex"

    static let diastolicID = "HKQuantityTypeIdentifierBloodPressureDiastolic"
    static let stepsID = "HKQuantityTypeIdentifierStepCount"

    /// Everything the report reads for the vitals and the steps.
    static var identifiers: [String] { allCases.map(\.rawValue) + [diastolicID, stepsID] }

    var identifier: String { rawValue }
    var isDailyTotal: Bool { false }

    var title: String {
        switch self {
        case .restingHeartRate: "Resting heart rate"
        case .bloodPressure: "Blood pressure"
        case .oxygen: "Blood oxygen"
        case .respiratoryRate: "Breathing rate, asleep"
        case .hrv: "Heart rate variability, SDNN"
        case .vo2Max: "VO2 max, watch estimate"
        case .weight: "Weight"
        case .bmi: "Body mass index"
        }
    }

    func unit(_ measures: MeasureSystem) -> String {
        switch self {
        case .restingHeartRate: "bpm"
        case .bloodPressure: "mmHg"
        case .oxygen: "%"
        case .respiratoryRate: "/min"
        case .hrv: "ms"
        case .vo2Max: "ml/kg/min"
        case .weight: measures == .imperial ? "lb" : "kg"
        case .bmi: "kg/m²"
        }
    }

    /// Health's canonical value in the unit shown: a fraction as a percent,
    /// kilograms as pounds for imperial.
    func shown(_ value: Double, measures: MeasureSystem) -> Double {
        switch self {
        case .oxygen: value * 100
        case .weight where measures == .imperial: value * TrackMassUnit.poundsPerKilogram
        default: value
        }
    }

    func number(_ value: Double) -> String {
        let decimals = switch self {
        case .respiratoryRate, .vo2Max, .weight, .bmi: 1
        default: 0
        }
        return LabMath.format(value, decimals: decimals) ?? "-"
    }

    /// The range the period's average is flagged against, in the unit shown.
    var band: ClosedRange<Double>? {
        switch self {
        // AHA: a normal resting heart rate for adults is 60 to 100 bpm.
        case .restingHeartRate: 60...100
        // American Lung Association: 95 % or more is normal at rest.
        case .oxygen: 95...100
        // NIH MedlinePlus, vital signs: 12 to 20 breaths a minute at rest.
        case .respiratoryRate: 12...20
        // WHO: 18.5 to 24.9 is the normal weight range.
        case .bmi: 18.5...24.9
        default: nil
        }
    }

    var reference: String? {
        switch self {
        case .restingHeartRate: "60 to 100 (AHA)"
        case .bloodPressure: "Under 120/80 (AHA)"
        case .oxygen: "95 to 100"
        case .respiratoryRate: "12 to 20"
        case .bmi: "18.5 to 24.9 (WHO)"
        default: nil
        }
    }
}

// MARK: - Formatting

/// Dates the way the report writes them, in the input's calendar and zone.
struct DoctorReportFormat: Sendable {
    let calendar: Calendar

    init(_ input: DoctorReportInput) { calendar = input.calendar }

    func day(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    func monthYear(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).year()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

extension DoctorReportBuilder {
    typealias Format = DoctorReportFormat
}

private extension String {
    nonisolated var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
