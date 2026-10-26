//
//  BodyLabTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Lane 4, the Body lab: the logic of PhenoAge, biological
/// age, eGFR, PREVENT, the risk enhancers, the ledger, the report reader)
/// and the arithmetic the pages share. Every number here is pinned so a
/// port that drifts from the published models fails.
@Suite("Body lab")
@MainActor
struct BodyLabTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))! }

    // MARK: PhenoAge

    /// Every marker at its population median, which are healthy values: the
    /// model reads younger than the calendar, and nothing is imputed.
    @Test("PhenoAge at the medians reads younger than the calendar age")
    func phenoAgeAtMedians() {
        let markers = Dictionary(uniqueKeysWithValues: BloodMarkerKey.allCases.map { ($0, $0.referenceMedian(sex: .female)) })
        let result = PhenoAge.compute(markers: markers, chronologicalAge: 46, sex: .female)
        #expect(result.imputed.isEmpty)
        #expect(result.completeness == 1)
        #expect(result.phenotypicAge < 46 && result.phenotypicAge > 30)
        #expect(result.perMarkerYears.values.allSatisfy { abs($0) < 0.001 })
    }

    @Test("Worse inflammation and glucose read older")
    func phenoAgeDirection() {
        let base: [BloodMarkerKey: Double] = [.albumin: 45, .creatinine: 70, .glucose: 5.0, .crp: 0.1]
        var worse = base
        worse[.crp] = 1.0
        worse[.glucose] = 7.0
        let a = PhenoAge.compute(markers: base, chronologicalAge: 50, sex: .male)
        let b = PhenoAge.compute(markers: worse, chronologicalAge: 50, sex: .male)
        #expect(b.phenotypicAge > a.phenotypicAge)
        #expect(a.imputed.count == 5)
        #expect(b.perMarkerYears[.crp]! > 0)
    }

    @Test("Units convert into the Levine units")
    func levineUnits() {
        #expect(abs(BloodMarkerKey.glucose.toLevineUnit(90, from: "mg/dL")! - 4.995) < 0.01)
        #expect(BloodMarkerKey.crp.toLevineUnit(1, from: "mg/L") == 0.1)
        #expect(BloodMarkerKey.creatinine.toLevineUnit(1, from: "mg/dL") == 88.42)
        #expect(BloodMarkerKey.albumin.toLevineUnit(4.5, from: "g/dl") == 45)
        #expect(BloodMarkerKey.albumin.toLevineUnit(4.5, from: "oz") == nil)
    }

    // MARK: Biological age

    @Test("Nothing measured gives no estimate")
    func bioAgeNeedsInputs() {
        #expect(BiologicalAge.compute(.init(chronologicalAge: 46, sex: .female)) == nil)
    }

    @Test("A fit month reads younger, and one component is clamped to three years")
    func bioAgeFit() {
        var inputs = BiologicalAge.Inputs(chronologicalAge: 46, sex: .male)
        inputs.vo2Max = Array(repeating: 55, count: 60)
        inputs.restingHR = Array(repeating: 50, count: 60)
        inputs.steps = Array(repeating: 11_000, count: 60)
        let result = BiologicalAge.compute(inputs)!
        #expect(result.estimatedAge < 46)
        #expect(result.components.allSatisfy { abs($0.yearsDelta) <= 3 })
        #expect(result.deltaYears >= -6)
    }

    @Test("A panel of three or more markers joins the estimate")
    func bioAgeWithBlood() {
        var inputs = BiologicalAge.Inputs(chronologicalAge: 46, sex: .female)
        inputs.bloodMarkers = [.albumin: 47, .glucose: 4.8, .crp: 0.05]
        inputs.bloodPanels = 1
        let result = BiologicalAge.compute(inputs)!
        #expect(result.components.contains { $0.isBlood })
        inputs.bloodMarkers = [.albumin: 47, .glucose: 4.8]
        #expect(BiologicalAge.compute(inputs) == nil)
    }

    @Test("Extended markers only ever add years")
    func extendedMarkers() {
        let good = BiologicalAge.extendedContributions(["hdl": 70, "vitaminD": 45])
        #expect(good.allSatisfy { $0.years == 0 })
        let bad = BiologicalAge.extendedContributions(["hdl": 30])
        #expect(bad.first!.years > 0)
    }

    // MARK: Risk

    /// CKD-EPI 2021: a 50 year old woman at 0.7 mg/dL sits at the knee of
    /// the curve, 142 x 0.9938^50 x 1.012.
    @Test("CKD-EPI 2021 at the knee")
    func egfr() {
        let expected = 142 * pow(0.9938, 50) * 1.012
        #expect(abs(EGFR.ckdEpi2021(creatinineMgDl: 0.7, ageYears: 50, sex: .female) - expected) < 0.01)
        #expect(EGFR.ckdEpi2021(creatinineMgDl: 2.0, ageYears: 50, sex: .male) < 45)
    }

    func panel(_ values: [String: Double]) -> BloodPanel {
        BloodPanel(sampledAt: now, createdAt: now, markers: values.map {
            BloodMarkerValue(key: $0.key, value: $0.value, enteredUnit: "", source: .manual)
        })
    }

    var answered: CardiometabolicProfile {
        CardiometabolicProfile(statinUse: false, bpMedicationUse: false, currentSmoker: false, diabetes: false)
    }

    @Test("Missing inputs are listed, never filled")
    func riskMissing() {
        let report = CardiometabolicRisk.report(panels: [], systolicBP: nil, ageYears: 50, sex: nil,
                                                profile: CardiometabolicProfile(), bodyMassIndex: nil)
        #expect(report.inputs == nil)
        #expect(Set(report.missing) == [.totalCholesterol, .hdl, .creatinine, .systolicBP, .statinUse,
                                        .bpMedicationUse, .currentSmoker, .diabetes, .sex])
        #expect(report.estimates.count == 6)
        #expect(report.estimates.allSatisfy { $0.percent == nil && $0.refusal == .requiredInputsMissing })
    }

    /// A healthy 50 year old woman: PREVENT's ten year ASCVD is low single digits.
    @Test("PREVENT for a healthy 50 year old is low")
    func riskLow() {
        let p = panel(["totalCholesterol": 200, "hdl": 60, "creatinine": 70])
        let report = CardiometabolicRisk.report(panels: [p], systolicBP: 118, ageYears: 50, sex: .female,
                                                profile: answered, bodyMassIndex: 23)
        let headline = report.headline!.percent!
        #expect(headline > 0.5 && headline < 3)
        #expect(report.headline?.tier == .low)
        #expect(report.missing.isEmpty)
        #expect(report.estimates.allSatisfy { $0.percent != nil })
    }

    @Test("Smoking and pressure raise the risk, and the drivers name them")
    func riskDrivers() {
        let p = panel(["totalCholesterol": 240, "hdl": 40, "creatinine": 90])
        var profile = answered
        profile.currentSmoker = true
        let report = CardiometabolicRisk.report(panels: [p], systolicBP: 150, ageYears: 60, sex: .male,
                                                profile: profile, bodyMassIndex: nil)
        #expect(report.headline!.percent! > 7.5)
        #expect(report.drivers.map(\.id).contains("smoking"))
        #expect(report.drivers.map(\.id).contains("systolicBP"))
        #expect(report.estimates.first { $0.outcome == .heartFailure }?.refusal == .bodyMassIndexUnavailable)
    }

    @Test("Outside ages are refused, not clamped")
    func riskAge() {
        let p = panel(["totalCholesterol": 200, "hdl": 60, "creatinine": 70])
        let report = CardiometabolicRisk.report(panels: [p], systolicBP: 118, ageYears: 25, sex: .female,
                                                profile: answered, bodyMassIndex: 23)
        #expect(report.headline?.refusal == .ageOutsideValidatedRange)
    }

    @Test("Enhancers tier ApoB and Lp(a)")
    func enhancers() {
        let e = RiskEnhancers.enhancers(panel: panel(["apoB": 82, "lpA": 150]), sex: .male)
        #expect(e.first { $0.id == "apoB" }?.tier == .borderline)
        #expect(e.first { $0.id == "lpA" }?.tier == .elevated)
    }

    // MARK: Ledger

    @Test("Ledger coefficients hold their values")
    func ledger() {
        #expect(LongevityLedger.stepMinutes(8_412) == 8.412)
        #expect(LongevityLedger.stepMinutes(20_000) == 10)
        #expect(LongevityLedger.sleepMinutes(7.2) == 2)
        #expect(LongevityLedger.sleepMinutes(5.5) == -3)
        #expect(LongevityLedger.sleepMinutes(6.5) == 0)
        #expect(LongevityLedger.alcoholMinutes(1) == 0)
        #expect(LongevityLedger.alcoholMinutes(3) == -10)
        #expect(LongevityLedger.caffeineMinutes(100) == -2)
        let day = LongevityLedger.breakdown(.init(date: now, steps: 5_000, exerciseMinutes: 10, sleepHours: nil,
                                                  drinks: nil, lateCaffeineMg: 100))
        #expect(day.minutes[.sleep] == nil)
        #expect(abs(day.net - (5 + 3 - 2)) < 0.0001)
    }

    @Test("Journal tags become drinks and cups")
    func ledgerDays() {
        let daily = LabDaily(steps: [1_000, 2_000, 3_000], exerciseMinutes: [nil, 5, 10], sleepHours: [7, nil, 8])
        let today = calendar.startOfDay(for: now)
        let days = LongevityLedger.days(from: daily, tags: { $0 == today ? ["coffee-late", "alcohol"] : [] },
                                        now: now, calendar: calendar)
        #expect(days.count == 3)
        #expect(days.last?.lateCaffeineMg == 100)
        #expect(days.last?.drinks == 1)
        #expect(days.first?.lateCaffeineMg == nil)
        #expect(days[1].sleepHours == nil)
    }

    // MARK: Report reader

    @Test("The reader finds markers next to their labels, European decimals included")
    func reader() {
        let text = """
        Cholestérol total 1,95 g/L 1,50 - 2,00
        HDL 62 mg/dL > 40
        Apolipoprotein B 82 mg/dL
        Patient born 1980
        """
        let found = BloodReportReader.detect(in: text)
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        #expect(byID["totalCholesterol"]?.value == 1.95)
        #expect(byID["totalCholesterol"]?.unit == "g/l")
        #expect(byID["totalCholesterol"]?.refLow == 1.5)
        #expect(byID["hdl"]?.value == 62)
        #expect(byID["hdl"]?.refLow == 40)
        #expect(byID["apoB"]?.value == 82)
        #expect(found.count == 3)
    }

    @Test("Decimals parse either way")
    func decimals() {
        #expect(BloodReportReader.parseDecimal("1,95") == 1.95)
        #expect(BloodReportReader.parseDecimal("1.234,5") == 1234.5)
        #expect(BloodReportReader.parseDecimal("1,234.5") == 1234.5)
        #expect(BloodReportReader.parseDecimal("-") == nil)
    }

    @Test("A typed draft saves only values in accepted units, in storage units")
    func draft() {
        var draft = BloodPanelDraft.typed()
        #expect(draft.lines.count == 10)
        draft.lines[0].text = "82"
        let glucose = draft.lines.firstIndex { $0.markerID == "glucose" }!
        draft.lines[glucose].text = "90"
        let saved = draft.panel(now: now)
        #expect(saved.markers.count == 2)
        #expect(abs(saved.value("glucose")!.value - 4.995) < 0.01)
    }

    // MARK: Shared arithmetic

    @Test("Marker readings convert to the display unit and flag outside values")
    func markerReading() {
        let apoB = LabMath.reading(BloodMarkerValue(key: "apoB", value: 95, enteredUnit: "mg/dL", source: .manual))
        #expect(apoB.status == .high)
        #expect(apoB.rangeText == "under 90")
        let glucose = LabMath.reading(BloodMarkerValue(key: "glucose", value: 5.0, enteredUnit: "mg/dL", source: .manual))
        #expect(glucose.value == 90)
        #expect(glucose.status == .normal)
    }

    @Test("Usual band, change and forward fill")
    func series() {
        #expect(LabMath.usualBand([1, 2, 3]) == nil)
        #expect(LabMath.usualBand([1, 2, 3, 4, 5]) == 2...4)
        let points = [LabPoint(date: now.addingTimeInterval(-40 * 86_400), value: 70),
                      LabPoint(date: now.addingTimeInterval(-2 * 86_400), value: 68.5)]
        #expect(LabMath.change(points, days: 30, now: now, calendar: calendar) == -1.5)
        let filled = LabMath.forwardFilled(points, days: 10, now: now, calendar: calendar)
        #expect(filled.count == 10)
        #expect(filled.first == 70)
        #expect(filled.last == 68.5)
        #expect(LabMath.signed(-0.6, decimals: 1) == "\u{2212}0.6")
    }

    @Test("Cuff readings pair by instant")
    func pressures() {
        let t = now
        let pairs = LabHealth.pair(systolic: [LabPoint(date: t, value: 118)],
                                   diastolic: [LabPoint(date: t.addingTimeInterval(1), value: 76),
                                               LabPoint(date: t.addingTimeInterval(-3600), value: 90)])
        #expect(pairs == [PressureReading(date: t, systolic: 118, diastolic: 76)])
    }

    @Test("Stores keep what is saved, newest first")
    func stores() {
        let store = BloodPanelStore(url: nil)
        store.save(BloodPanel(sampledAt: now.addingTimeInterval(-86_400 * 100), createdAt: now, markers: [
            BloodMarkerValue(key: "apoB", value: 91, enteredUnit: "mg/dL", source: .manual)]))
        store.save(BloodPanel(sampledAt: now, createdAt: now, markers: [
            BloodMarkerValue(key: "apoB", value: 82, enteredUnit: "mg/dL", source: .manual)]))
        #expect(store.latest?.value("apoB")?.value == 82)
        #expect(store.previous(of: "apoB")?.value.value == 91)
        let measures = BodyMeasurementStore(url: nil)
        measures.save(BodyMeasurementEntry(date: now.addingTimeInterval(-86_400 * 30), values: [.waist: 83]))
        measures.save(BodyMeasurementEntry(date: now, values: [.waist: 81, .hips: 95]))
        #expect(measures.span(.waist)?.first.1 == 83)
        #expect(measures.span(.waist)?.latest.1 == 81)
        #expect(measures.span(.chest) == nil ? true : false)
    }

    @Test("Glucose fasting is the first morning reading")
    func glucose() {
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 7))!
        let points = [LabPoint(date: morning, value: 89),
                      LabPoint(date: morning.addingTimeInterval(3600), value: 95),
                      LabPoint(date: morning.addingTimeInterval(6 * 3600), value: 137)]
        #expect(GlucoseDays.fasting(points, calendar: calendar).map(\.value) == [89])
        #expect(GlucoseDays.rise(points) == 48)
    }
}
