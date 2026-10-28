//
//  FunctionalResultsTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Imaging and functional tests in the Body lab: the calcium score's
/// categories, the DEXA T-score's bands, units read at entry, the report
/// reader on sample text, the store, the lab VO2 max the biological age
/// prefers while it is recent, and the screenings a result counts as done.
@Suite("Lab: imaging and functional tests")
@MainActor
struct FunctionalResultsTests {
    private static func daysAgo(_ days: Double, from now: Date) -> Date { now.addingTimeInterval(-days * 86_400) }

    // MARK: Bands

    @Test("A calcium score falls in the AHA/ACC 2018 categories")
    func calciumCategories() {
        #expect(CalciumScore.category(agatston: 0) == .none)
        #expect(CalciumScore.category(agatston: 1) == .mild)
        #expect(CalciumScore.category(agatston: 99) == .mild)
        #expect(CalciumScore.category(agatston: 100) == .moderate)
        #expect(CalciumScore.category(agatston: 399) == .moderate)
        #expect(CalciumScore.category(agatston: 400) == .severe)
        #expect(CalciumScore.category(agatston: 1_250) == .severe)
    }

    @Test("A T-score falls in the WHO bands")
    func tScoreBands() {
        #expect(BoneDensityBand.band(tScore: 0.4) == .normal)
        #expect(BoneDensityBand.band(tScore: -1.0) == .normal)
        #expect(BoneDensityBand.band(tScore: -1.1) == .osteopenia)
        #expect(BoneDensityBand.band(tScore: -2.4) == .osteopenia)
        #expect(BoneDensityBand.band(tScore: -2.5) == .osteoporosis)
        #expect(BoneDensityBand.band(tScore: -3.2) == .osteoporosis)
        let dexa = DexaResult(FunctionalResult(kind: .dexa, date: .now, values: ["tScore": -2.6, "visceralFat": 0.8]))
        #expect(dexa.tScore == -2.6)
        #expect(dexa.visceralFatKg == 0.8)
        #expect(dexa.boneBand == .osteoporosis)
        #expect(DexaResult(FunctionalResult(kind: .dexa, date: .now, values: ["bodyFat": 22])).boneBand == nil)
    }

    @Test("An osteoporosis band or a calcium score from 100 points to a clinician, without a diagnosis")
    func notesPointToAClinician() throws {
        let bone = try #require(FunctionalAssessment.note(field: "tScore", value: -2.7, sex: .female))
        #expect(bone.isFlagged && bone.needsClinician)
        #expect(!bone.text.lowercased().contains("you have"))
        let calcium = try #require(FunctionalAssessment.note(field: "agatston", value: 140, sex: nil))
        #expect(calcium.needsClinician)
        #expect(FunctionalAssessment.note(field: "agatston", value: 0, sex: nil)?.isFlagged == false)
        // GOLD 2024: a ratio under 70% reads as airflow limitation.
        #expect(FunctionalAssessment.note(field: "fev1FvcRatio", value: 64, sex: nil)?.isFlagged == true)
        // EWGSOP2: low grip is under 27 kg for men, under 16 kg for women.
        #expect(FunctionalAssessment.note(field: "grip", value: 20, sex: .male)?.isFlagged == true)
        #expect(FunctionalAssessment.note(field: "grip", value: 20, sex: .female)?.isFlagged == false)
        #expect(FunctionalAssessment.note(field: "grip", value: 20, sex: nil) == nil)
        #expect(FunctionalAssessment.note(field: "vo2Max", value: 41, sex: .male) == nil)
    }

    @Test("A negative T-score sits on its rail, the band from -1 up")
    func negativeTScoreRail() throws {
        let result = FunctionalResult(kind: .dexa, date: .now, values: ["tScore": -1.3, "bodyFat": 23])
        let items = FunctionalItems.items(result, previous: nil, measures: .metric, sex: .female, route: nil)
        let bone = try #require(items.first { $0.id == "tScore" })
        let band = try #require(bone.band)
        let position = try #require(bone.position)
        #expect(position < band.lowerBound)
        #expect(bone.isFlagged)
        #expect(items.first { $0.id == "bodyFat" }?.band == nil)
    }

    // MARK: Units

    @Test("Pounds are read into kilograms and shown in the person's measures")
    func unitConversionLbToKg() throws {
        let grip = try #require(FunctionalCatalog.field("grip", in: .gripStrength))
        let kilograms = try #require(grip.toStorage(100, from: "lb"))
        #expect(abs(kilograms - 45.359_237) < 0.000_1)
        #expect(grip.toStorage(100, from: "lbs") == kilograms)
        #expect(grip.toStorage(40, from: "kg") == 40)
        #expect(grip.toStorage(40, from: "furlongs") == nil)
        #expect(grip.text(kilograms, measures: .imperial) == "100.0 lb")
        #expect(grip.text(kilograms, measures: .metric) == "45.4 kg")
        let visceral = try #require(FunctionalCatalog.field("visceralFat", in: .dexa))
        #expect(visceral.toStorage(850, from: "g") == 0.85)
        // A ratio printed as a fraction is stored as a percent.
        let ratio = try #require(FunctionalCatalog.field("fev1FvcRatio", in: .spirometry))
        #expect(ratio.toStorage(0.72, from: "") == 72)
        #expect(ratio.toStorage(72, from: "%") == 72)
        let fev1 = try #require(FunctionalCatalog.field("fev1", in: .spirometry))
        #expect(fev1.toStorage(3_200, from: "mL") == 3.2)
        // A missing value is nil, never a zero, so the view draws the mark.
        let agatston = try #require(FunctionalCatalog.field("agatston", in: .calciumScore))
        #expect(agatston.text(nil, measures: .metric) == nil)
    }

    // MARK: Reading a report

    @Test("A DEXA report reads its T-score, its negative sign and its masses")
    func readsDexaReport() {
        let text = """
        DXA BODY COMPOSITION AND BONE DENSITY
        Femoral neck T-score   -1.8
        BMD 0.812 g/cm2
        Total body fat 27.4 %
        Lean mass 51 200 g
        Visceral fat mass 0.94 kg
        """
        let found = Dictionary(uniqueKeysWithValues: FunctionalReportReader.detect(in: text, kind: .dexa).map { ($0.fieldID, $0) })
        #expect(found["tScore"]?.value == -1.8)
        #expect(found["boneDensity"]?.value == 0.812)
        #expect(found["bodyFat"]?.value == 27.4)
        #expect(found["visceralFat"]?.value == 0.94)
        #expect(found["visceralFat"]?.unit == "kg")
        // "51 200 g" is one number, in grams.
        #expect(found["leanMass"]?.value == 51_200)
        #expect(found["leanMass"]?.unit == "g")
    }

    @Test("Without a kind, the reader picks the test the page is about")
    func readerGuessesKind() {
        let text = """
        Coronary artery calcium scan
        Total Agatston score: 142
        MESA percentile 71
        """
        #expect(FunctionalReportReader.guessKind(in: text) == .calciumScore)
        let found = FunctionalReportReader.detect(in: text, kind: nil)
        #expect(found.first { $0.fieldID == "agatston" }?.value == 142)
        #expect(found.first { $0.fieldID == "percentile" }?.value == 71)
        #expect(FunctionalReportReader.guessKind(in: "Nothing here") == nil)
    }

    // MARK: Store

    @Test("The store keeps each test newest first, and an empty one says so")
    func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "functional-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let store = FunctionalResultStore(url: url)
        #expect(store.results.isEmpty)
        #expect(store.latest(.gripStrength) == nil)
        let old = FunctionalResult(kind: .gripStrength, date: Self.daysAgo(200, from: now), values: ["grip": 38])
        let new = FunctionalResult(kind: .gripStrength, date: Self.daysAgo(5, from: now), values: ["grip": 41], note: "Right hand")
        let vo2 = FunctionalResult(kind: .labVO2, date: Self.daysAgo(30, from: now), values: ["vo2Max": 44])
        store.save(old)
        store.save(new)
        store.save(vo2)
        let reopened = FunctionalResultStore(url: url)
        #expect(reopened.latest(.gripStrength)?.id == new.id)
        #expect(reopened.latest(.gripStrength)?.note == "Right hand")
        #expect(reopened.history(.gripStrength).map(\.id) == [old.id, new.id])
        // In the catalog's order, not the order they were saved.
        #expect(reopened.kinds == [.labVO2, .gripStrength])
        reopened.delete(new)
        #expect(FunctionalResultStore(url: url).latest(.gripStrength)?.id == old.id)
    }

    // MARK: Biological age

    @Test("A lab VO2 max from three months ago wins over the watch's")
    func labVO2WinsWhenRecent() throws {
        let now = Date()
        var inputs = BiologicalAge.Inputs(chronologicalAge: 46, sex: .male)
        inputs.vo2Max = Array(repeating: 35, count: 60)
        inputs.asOf = now
        inputs.labVO2 = BiologicalAge.LabVO2(value: 52, date: Self.daysAgo(90, from: now))
        let result = try #require(BiologicalAge.compute(inputs))
        let vo2 = try #require(result.components.first { $0.label.hasPrefix("VO2 max") })
        #expect(abs(vo2.zScore - BiologicalAge.vo2MaxZ(52, age: 46, sex: .male)) < 0.000_001)
        #expect(vo2.label.contains("lab"))
        // A lab test alone is enough: it needs no fortnight of readings.
        inputs.vo2Max = []
        #expect(BiologicalAge.compute(inputs)?.components.contains { $0.label.hasPrefix("VO2 max") } == true)
    }

    @Test("A lab VO2 max from fourteen months ago gives way to the watch")
    func labVO2IgnoredWhenOld() throws {
        let now = Date()
        var inputs = BiologicalAge.Inputs(chronologicalAge: 46, sex: .male)
        inputs.vo2Max = Array(repeating: 35, count: 60)
        inputs.asOf = now
        inputs.labVO2 = BiologicalAge.LabVO2(value: 52, date: Calendar.current.date(byAdding: .month, value: -14, to: now)!)
        let result = try #require(BiologicalAge.compute(inputs))
        let vo2 = try #require(result.components.first { $0.label.hasPrefix("VO2 max") })
        #expect(abs(vo2.zScore - BiologicalAge.vo2MaxZ(35, age: 46, sex: .male)) < 0.000_001)
        #expect(!vo2.label.contains("lab"))
    }

    @Test("The store hands the latest lab VO2 max to the biological age")
    func storeGivesLabVO2() {
        let store = FunctionalResultStore(url: nil)
        #expect(store.labVO2 == nil)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        store.save(FunctionalResult(kind: .labVO2, date: date, values: ["vo2Max": 47.5]))
        #expect(store.labVO2 == BiologicalAge.LabVO2(value: 47.5, date: date))
    }

    // MARK: Screening ledger

    @Test("A calcium score or a DEXA with a T-score marks its screening done, once")
    func ledgerMarksDone() {
        let store = FunctionalResultStore(url: nil)
        let scan = Date(timeIntervalSince1970: 1_780_000_000)
        store.save(FunctionalResult(kind: .calciumScore, date: scan, values: ["agatston": 0]))
        store.save(FunctionalResult(kind: .dexa, date: scan, values: ["tScore": -1.4, "bodyFat": 24]))
        let ledger = SomaTools.ScreeningLedger().withResults(store.screeningRecords)
        #expect(ledger.lastRecord(for: "calciumScore")?.performedOn == scan)
        #expect(ledger.lastRecord(for: "osteoporosis")?.performedOn == scan)
        // Folding twice, or over a record the person wrote that day, adds nothing.
        #expect(ledger.withResults(store.screeningRecords).records(for: "calciumScore").count == 1)
        var logged = SomaTools.ScreeningLedger()
        logged.log(itemID: "osteoporosis", performedOn: scan)
        #expect(logged.withResults(store.screeningRecords).records(for: "osteoporosis").count == 1)
        // A body composition scan without a T-score says nothing about bone.
        let composition = FunctionalResultStore(url: nil)
        composition.save(FunctionalResult(kind: .dexa, date: scan, values: ["bodyFat": 24]))
        #expect(SomaTools.ScreeningLedger().withResults(composition.screeningRecords).lastRecord(for: "osteoporosis") == nil)
    }

    @Test("A DEXA counted from the lab makes the bone scan no longer due")
    func ledgerStatusFollows() throws {
        let store = FunctionalResultStore(url: nil)
        let now = Date()
        store.save(FunctionalResult(kind: .dexa, date: Self.daysAgo(30, from: now), values: ["tScore": -0.6]))
        let ledger = SomaTools.ScreeningLedger().withResults(store.screeningRecords)
        let bone = try #require(ledger.statuses(age: 67, sex: .female, today: now).first { $0.item.id == "osteoporosis" })
        #expect(bone.lastDone != nil)
        #expect(!bone.isDue)
    }

    @Test("A T-score names its band on the band line, and a usual one reads Normal range")
    func boneBandWord() {
        func line(_ tScore: Double) -> LabBandItem? {
            FunctionalItems.items(FunctionalResult(kind: .dexa, date: .now, values: ["tScore": tScore]), previous: nil,
                                  measures: .metric, sex: .female, route: nil).first { $0.id == "tScore" }
        }
        #expect(line(-1.8)?.status == LabBandStatus(word: "Osteopenia range", isOut: true))
        #expect(line(-2.8)?.status == LabBandStatus(word: "Osteoporosis range", isOut: true))
        #expect(line(0.4)?.status == LabBandStatus(word: "Normal range", isOut: false))
        #expect(FunctionalAssessment.bandWord(field: "agatston", value: 140) == "Moderate calcium")
        #expect(FunctionalAssessment.bandWord(field: "grip", value: 10) == nil)
    }

    @Test("Without a band word the line keeps the generic words")
    func genericWords() {
        let high = LabBandItem(id: "x", title: "X", value: "9", band: 0.2...0.6, position: 0.9)
        #expect(high.status == LabBandStatus(word: "Above normal", isOut: true))
        let low = LabBandItem(id: "x", title: "X", value: "1", band: 0.2...0.6, position: 0.1)
        #expect(low.status?.word == "Below normal")
        let flagged = LabBandItem(id: "x", title: "X", value: "Positive", isFlagged: true)
        #expect(flagged.status?.word == "Out of range")
        #expect(LabBandItem(id: "x", title: "X", value: nil).status == nil)
    }
}
