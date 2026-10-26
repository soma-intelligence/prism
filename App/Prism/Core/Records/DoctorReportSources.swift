//
//  DoctorReportSources.swift
//  Prism
//
//  Where the doctor report's input comes from: the stores on the phone, read
//  as they are, and Apple Health, read once through a `HealthSampleSource`.
//  Nothing is written and nothing is sent; the builder turns what this
//  returns into the report.
//

import Foundation
import HealthExportCore

extension DoctorReportHealth {
    /// Every Health identifier the report reads apart from the cycle, which
    /// is sensitive and only read once its page has asked.
    static var identifiers: [String] {
        DoctorReportVital.identifiers + [HomeMetric.bloodGlucose, OralSummary.brushingID] + RhythmMobilityReadings.identifiers
    }

    /// The cycle's identifiers: the flow and each symptom.
    static var cycleIdentifiers: [String] {
        [HomeMetric.menstrualFlow, HomeMetric.wristTemperature] + CycleSymptom.allCases.map(\.identifier)
    }

    /// Reads what the report needs from `source`: the vitals over the period
    /// and the one before it, glucose, rhythm and mobility, the scores, the
    /// brushings, and the cycle only when `includeCycle` is true.
    ///
    /// - Parameters:
    ///   - scores: the scores already worked out, when the dashboard has
    ///     them; read here otherwise.
    ///   - journalDays: the Journal's days, for floss and gums.
    static func read(
        from source: any HealthSampleSource,
        period: DoctorReportPeriod,
        includeCycle: Bool,
        scores: SomaScores? = nil,
        journalDays: [(date: Date, day: JournalDay)] = [],
        lastDentalVisit: Date? = nil,
        bookedDentalVisit: Date? = nil,
        age: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> DoctorReportHealth {
        var health = DoctorReportHealth()
        let span = period.days * 2 + 1
        for identifier in DoctorReportVital.identifiers {
            let readings = await source.home(identifier, days: span, now: now, calendar: calendar)
            if !readings.isEmpty { health.vitals[identifier] = readings }
        }
        health.glucose = await source.home(HomeMetric.bloodGlucose, days: period.days, now: now, calendar: calendar)
        health.rhythm = await RhythmMobilityReadings.read(from: source, now: now, calendar: calendar)
        if let scores {
            health.scores = scores
        } else {
            let inputs = await SomaScoresReader.read(from: source, now: now, calendar: calendar)
            health.scores = SomaScores.compute(inputs)
        }
        let brushing = await source.home(OralSummary.brushingID, days: OralSummary.windowDays, now: now, calendar: calendar)
        let oral = OralSummary.make(brushing: brushing, journalDays: journalDays, lastVisit: lastDentalVisit,
                                    bookedVisit: bookedDentalVisit, now: now, calendar: calendar)
        health.oral = oral.isEmpty ? nil : oral

        if includeCycle {
            // Value 5 is "none": a day logged without flow.
            let flow = await source.home(HomeMetric.menstrualFlow, days: 400, now: now, calendar: calendar)
                .filter { $0.code != 5 }.map(\.start)
            var symptoms: [CycleSymptom: [Date]] = [:]
            for symptom in CycleSymptom.allCases {
                let days = await source.home(symptom.identifier, days: 400, now: now, calendar: calendar)
                    .filter { $0.code != CycleSymptom.notPresentCode }.map(\.start)
                if !days.isEmpty { symptoms[symptom] = days }
            }
            if !flow.isEmpty || !symptoms.isEmpty {
                let wrist = await source.home(HomeMetric.wristTemperature, days: 40, now: now, calendar: calendar)
                let stage = PerimenopauseSignal.assess(
                    cycles: CycleHistory.periods(flowDays: flow, today: now, calendar: calendar),
                    symptoms: symptoms, wristTemperature: wrist, now: now, calendar: calendar, age: age
                ).stage
                health.cycle = DoctorReportCycle(flowDays: flow, symptomDays: symptoms, stage: stage)
            }
        }
        return health
    }
}

/// The phone's stores, read into an input.
enum DoctorReportSources {
    /// Everything but Apple Health: the record, the lab, the plan, the
    /// screenings, the questionnaires and the DNA file, as they stand.
    static func input(period: DoctorReportPeriod, topics: Set<DoctorReportTopic>, health: DoctorReportHealth,
                      healthMedications: [HealthMedication] = [], now: Date = .now) -> DoctorReportInput {
        var input = DoctorReportInput(now: now, period: period, topics: topics)
        let profile = SomaProfileStore.shared.profile
        let card = HomeLog.shared.medical
        let screeningProfile = ScreeningReminders.profile(now: now)
        input.patient = DoctorReportPatient(
            name: profile.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? profile.name : card.name,
            birthday: profile.birthday ?? screeningProfile.birthday,
            sex: profile.sex ?? screeningProfile.sex)
        input.record = MedicalRecordStore.shared.record
        input.cardMedications = card.medications
        input.bloodPanels = BloodPanelStore.shared.panels
        input.urinePanels = UrinePanelStore.shared.panels
        input.stoolPanels = StoolPanelStore.shared.panels
        input.functionalResults = FunctionalResultStore.shared.results
        let supplements = TrackLogStore.shared.activeSupplements
        input.supplements = supplements
        input.medications = MedicationList.merged(supplements: supplements, health: healthMedications)
        let markers = (BloodPanelStore.shared.latest?.markers ?? []).map(BloodMarkerCatalog.definition(for:))
        input.interactionNotes = MedicationInteractions.notes(
            for: supplements, markers: markers,
            medications: healthMedications.filter { !$0.isArchived }.map(\.name))
        input.screenings = SomaTools.ScreeningSchedule.due(for: screeningProfile, ledger: ScreeningReminders.ledger, now: now)
        input.assessments = MindStore.shared.assessments
        input.genome = GenomeStore.shared.result
        input.showsAPOE = GenomeStore.shared.showsAPOE
        input.units = GlobalSettings.shared.units
        input.health = health
        return input
    }
}
