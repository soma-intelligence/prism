//
//  StoolPanelTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The stool half of the Body lab: the catalog's bands and their sources, a
/// positive stool blood test pointing to a doctor, the report reader on a
/// consumer kit and on a lab report, a half read report, diversity with no
/// universal band, and the store.
@Suite("Lab: stool and microbiome")
@MainActor
struct StoolPanelTests {
    // MARK: Bands

    @Test("Calprotectin reads usual under 50, borderline to 200, raised above (NICE DG11)")
    func calprotectinFlags() throws {
        let marker = try #require(StoolCatalog.marker(id: "calprotectin"))
        #expect(marker.flag(value: 12) == .usual)
        #expect(marker.flag(value: 49.9) == .usual)
        #expect(marker.flag(value: 50) == .borderline)
        #expect(marker.flag(value: 200) == .borderline)
        #expect(marker.flag(value: 201) == .elevated)
        #expect(marker.flag(value: 201).needsClinician)
        #expect(!marker.flag(value: 120).needsClinician)
    }

    @Test("A positive stool blood test (FIT) asks for a doctor now, in words that are not a diagnosis")
    func fitPositiveIsUrgent() throws {
        let marker = try #require(StoolCatalog.marker(id: "fit"))
        #expect(marker.flag(value: 1) == .actNow)
        #expect(marker.flag(value: 0) == .usual)
        let panel = StoolPanel(sampledAt: .now, createdAt: .now, kind: .labReport,
                               values: [StoolValue(key: "fit", value: 1, enteredUnit: "", source: .manual)])
        #expect(panel.urgent.map(\.key) == ["fit"])
        let advice = try #require(panel.urgent.first?.advice)
        #expect(advice.contains("doctor"))
        #expect(!advice.lowercased().contains("cancer"))
        #expect(!advice.lowercased().contains("you have"))
        #expect(StoolValue(key: "fit", value: 1, enteredUnit: "", source: .manual).text == "Positive")
    }

    @Test("Elastase and H. pylori follow their guidelines")
    func digestionFlags() throws {
        let elastase = try #require(StoolCatalog.marker(id: "elastase"))
        #expect(elastase.flag(value: 350) == .usual)
        #expect(elastase.flag(value: 150) == .borderline)
        #expect(elastase.flag(value: 80) == .low)
        #expect(elastase.flag(value: 80).needsClinician)
        let pylori = try #require(StoolCatalog.marker(id: "hPylori"))
        #expect(pylori.flag(value: 1) == .elevated)
        #expect(pylori.flag(value: 1).needsClinician)
        #expect(pylori.flag(value: 0) == .usual)
    }

    @Test("Diversity and the taxa have no universal band: they compare with your own tests")
    func diversityHasNoUniversalBand() throws {
        for id in ["shannon", "akkermansia", "faecalibacterium", "bifidobacterium", "firmicutesBacteroidetes"] {
            let marker = try #require(StoolCatalog.marker(id: id), "\(id) missing")
            #expect(!marker.hasBand, "\(id) should have no band")
            #expect(marker.flag(value: 0.1) == .noBand)
            #expect(marker.flag(value: 9) == .noBand)
            #expect(!marker.flag(value: 9).needsClinician)
        }
        let store = StoolPanelStore(url: nil)
        store.save(StoolPanel(sampledAt: .now.addingTimeInterval(-86_400 * 120), createdAt: .now, kind: .microbiomeKit,
                              values: [StoolValue(key: "shannon", value: 3.4, enteredUnit: "", source: .extracted)]))
        store.save(StoolPanel(sampledAt: .now, createdAt: .now, kind: .microbiomeKit,
                              values: [StoolValue(key: "shannon", value: 3.9, enteredUnit: "", source: .extracted)]))
        #expect(store.previous(of: "shannon")?.value.value == 3.4)
        #expect(store.latest?.flagged.isEmpty == true)
    }

    // MARK: Reading a report

    @Test("A consumer microbiome kit's text reads diversity, taxa and the ratio")
    func readsViome23Text() {
        let text = """
        Your gut microbiome results
        Shannon diversity index: 3.82
        Akkermansia muciniphila  2.4 %
        Faecalibacterium prausnitzii  7.9%
        Bifidobacterium  0,8 %
        Firmicutes/Bacteroidetes ratio 1.6
        Methanogens: low
        """
        let found = Dictionary(uniqueKeysWithValues: StoolReportReader.detect(in: text).map { ($0.id, $0.value) })
        #expect(found["shannon"] == 3.82)
        #expect(found["akkermansia"] == 2.4)
        #expect(found["faecalibacterium"] == 7.9)
        #expect(found["bifidobacterium"] == 0.8)
        #expect(found["firmicutesBacteroidetes"] == 1.6)
        #expect(found.count == 5)
    }

    @Test("A lab stool report reads numbers, units and words")
    func readsGenericLabText() {
        let text = """
        FAECAL CALPROTECTIN      85 ug/g      < 50
        Pancreatic elastase-1    420 µg/g     > 200
        Faecal immunochemical test (FIT)   Negative
        Helicobacter pylori stool antigen: NOT DETECTED
        """
        let found = Dictionary(uniqueKeysWithValues: StoolReportReader.detect(in: text).map { ($0.id, $0) })
        #expect(found["calprotectin"]?.value == 85)
        #expect(found["elastase"]?.value == 420)
        #expect(found["fit"]?.value == 0)
        #expect(found["hPylori"]?.value == 0)
        // A FIT printed as a number reads positive from 20 µg Hb/g.
        #expect(StoolReportReader.detect(in: "FIT  34 ug Hb/g").first?.value == 1)
        #expect(StoolReportReader.detect(in: "FIT  6 ug Hb/g").first?.value == 0)
        #expect(StoolReportReader.detect(in: "Occult blood (FIT): POSITIVE").first?.value == 1)
    }

    @Test("A half read report keeps what it read and computes nothing on the rest")
    func partialReportSavesOnlyWhatWasRead() {
        let text = """
        Calprotectin 260 ug/g
        Elastase  (result illegible)
        """
        var draft = StoolDraft.extracted(StoolReportReader.detect(in: text))
        #expect(draft.lines.map(\.markerID) == ["calprotectin"])
        draft.lines.append(.init(markerID: "elastase", unit: "µg/g", source: .manual))
        let panel = draft.panel(now: .now)
        #expect(panel.values.map(\.key) == ["calprotectin"])
        #expect(panel.value("elastase") == nil)
        #expect(panel.needingCare.map(\.key) == ["calprotectin"])
        #expect(StoolValue(key: "elastase", value: 0, enteredUnit: "", source: .manual).marker?.name == "Pancreatic elastase")
    }

    // MARK: Store

    @Test("The store keeps tests newest first, and an empty one has no latest")
    func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "stool-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StoolPanelStore(url: url)
        #expect(store.latest == nil)
        let old = StoolPanel(sampledAt: .now.addingTimeInterval(-86_400 * 90), createdAt: .now, kind: .labReport,
                             values: [StoolValue(key: "calprotectin", value: 40, enteredUnit: "µg/g", source: .extracted)])
        let new = StoolPanel(sampledAt: .now, createdAt: .now, kind: .labReport,
                             values: [StoolValue(key: "calprotectin", value: 140, enteredUnit: "µg/g", source: .manual),
                                      StoolValue(key: "fit", value: 0, enteredUnit: "", source: .manual)])
        store.save(old)
        store.save(new)
        let reopened = StoolPanelStore(url: url)
        #expect(reopened.panels.map(\.id) == [new.id, old.id])
        #expect(reopened.latest?.flagged.map(\.key) == ["calprotectin"])
        #expect(reopened.latest?.urgent.isEmpty == true)
        #expect(reopened.previous(of: "calprotectin")?.value.value == 40)
        reopened.delete(new)
        #expect(StoolPanelStore(url: url).latest?.id == old.id)
    }

    // MARK: The band line

    @Test("A borderline result says Borderline beside its value, not Above normal")
    func borderlineWord() {
        let borderline = LabBandItem(stool: StoolValue(key: "calprotectin", value: 120, enteredUnit: "µg/g", source: .manual), previous: nil)
        #expect(borderline.status == LabBandStatus(word: "Borderline", isOut: true))
        #expect(borderline.detail?.contains("Borderline") == false)

        let raised = LabBandItem(stool: StoolValue(key: "calprotectin", value: 260, enteredUnit: "µg/g", source: .manual), previous: nil)
        #expect(raised.status?.word == "Above normal")

        let usual = LabBandItem(stool: StoolValue(key: "calprotectin", value: 20, enteredUnit: "µg/g", source: .manual), previous: nil)
        #expect(usual.status == LabBandStatus(word: "Normal range", isOut: false))

        let elastase = LabBandItem(stool: StoolValue(key: "elastase", value: 150, enteredUnit: "µg/g", source: .manual), previous: nil)
        #expect(elastase.status?.word == "Borderline")
    }
}
