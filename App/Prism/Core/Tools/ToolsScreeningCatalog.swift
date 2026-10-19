//
//  ToolsScreeningCatalog.swift
//  Prism
//
//  The preventive screening catalog. Data only: no logic lives here, so this
//  is the one file to reread when a guideline moves.
//
//  Jurisdiction: United States. Tier `.recommended` is USPSTF grade A or B and
//  carries a start age and an interval the app asserts. Tier `.discuss` is
//  everything weaker and can never be reported as due.
//
//  Two items are gated on the tobacco answer. Without that gate the app would
//  tell a lifelong non smoker they are overdue for a lung CT.
//

import Foundation

extension SomaTools {

    nonisolated enum ScreeningCatalog {

        static let items: [ScreeningItem] = recommended + discuss

        /// Lookup by stable id, for a record whose item has since left the
        /// catalog.
        static func item(id: String) -> ScreeningItem? {
            items.first { $0.id == id }
        }

        // MARK: Tier recommended (USPSTF grade A or B)

        static let recommended: [ScreeningItem] = [
            ScreeningItem(
                id: "colorectal",
                title: "Colorectal screening",
                tier: .recommended,
                icon: "circle.dashed.inset.filled",
                startAge: 45,
                stopAge: 75,
                intervalMonths: 120,
                evidence: "Catches polyps before they turn. The one screening with a mortality benefit measured in whole percentage points.",
                citation: "USPSTF 2021 grade A",
                modifiers: [
                    ScreeningModifier(flag: .familyColorectal,
                                      startAgeOverride: 40,
                                      yearsBeforeRelativeDiagnosis: 10,
                                      intervalMonthsOverride: 60)
                ]),

            ScreeningItem(
                id: "cervical",
                title: "Cervical screening",
                tier: .recommended,
                icon: "staroflife",
                eligibility: .female,
                startAge: 21,
                stopAge: 65,
                // The shorter of the two accepted cadences. Storing the five year
                // HPV cadence by default would call a three year cytology user up
                // to date when they are not. `nextDueOverride` carries the other.
                intervalMonths: 36,
                evidence: "Cytology every three years, or HPV testing every five. Set a revised interval on your record if you are on the five-year schedule.",
                citation: "USPSTF 2018 grade A"),

            ScreeningItem(
                id: "mammography",
                title: "Mammography",
                tier: .recommended,
                icon: "heart.text.square",
                eligibility: .female,
                startAge: 40,
                stopAge: 74,
                intervalMonths: 24,
                evidence: "Every two years from 40. Family history pulls the start earlier.",
                citation: "USPSTF 2024 grade B",
                modifiers: [
                    ScreeningModifier(flag: .familyBreastOvarian,
                                      startAgeOverride: 30,
                                      yearsBeforeRelativeDiagnosis: 10)
                ]),

            ScreeningItem(
                id: "lipids",
                title: "Lipid panel",
                tier: .recommended,
                icon: "drop.triangle",
                startAge: 40,
                intervalMonths: 60,
                evidence: "The numbers a cardiovascular risk estimate is built from. Every five years is enough absent a reason.",
                citation: "USPSTF 2022",
                modifiers: [
                    ScreeningModifier(flag: .familyEarlyCardiac,
                                      startAgeOverride: 20,
                                      intervalMonthsOverride: 24)
                ]),

            ScreeningItem(
                id: "bloodPressure",
                title: "Blood pressure check",
                tier: .recommended,
                icon: "gauge.with.dots.needle.bottom.50percent",
                startAge: 18,
                intervalMonths: 12,
                evidence: "Annually, in a clinic, on a cuff. The cheapest screening there is.",
                citation: "USPSTF 2021 grade A"),

            ScreeningItem(
                id: "prediabetes",
                title: "Blood sugar screening",
                tier: .recommended,
                icon: "cube.transparent",
                startAge: 35,
                stopAge: 70,
                intervalMonths: 36,
                evidence: "Fasting glucose or HbA1c every three years from 35. Earlier with a family history.",
                citation: "USPSTF 2021 grade B",
                modifiers: [
                    ScreeningModifier(flag: .familyDiabetes, startAgeOverride: 25)
                ]),

            ScreeningItem(
                id: "hepatitisC",
                title: "Hepatitis C test",
                tier: .recommended,
                icon: "cross.vial",
                startAge: 18,
                stopAge: 79,
                intervalMonths: nil,
                evidence: "Once in adult life. Curable when found, silent for decades when not.",
                citation: "USPSTF 2020 grade B"),

            ScreeningItem(
                id: "hiv",
                title: "HIV test",
                tier: .recommended,
                icon: "shield.lefthalf.filled",
                startAge: 15,
                stopAge: 65,
                intervalMonths: nil,
                evidence: "Once in adult life, more often with ongoing exposure.",
                citation: "USPSTF 2019 grade A"),

            ScreeningItem(
                id: "osteoporosis",
                title: "Bone density scan",
                tier: .recommended,
                icon: "figure.stand",
                eligibility: .female,
                startAge: 65,
                intervalMonths: 120,
                evidence: "DEXA from 65, or from 50 with a family history of osteoporosis or hip fracture.",
                citation: "USPSTF 2025 grade B",
                modifiers: [
                    ScreeningModifier(flag: .familyOsteoporosis, startAgeOverride: 50)
                ]),

            ScreeningItem(
                id: "aorticUltrasound",
                title: "Abdominal aortic ultrasound",
                tier: .recommended,
                icon: "waveform.path.ecg.rectangle",
                eligibility: .male,
                startAge: 65,
                stopAge: 75,
                intervalMonths: nil,
                requiresRiskFlag: .tobaccoEverSmoker,
                evidence: "Once, for men 65 to 75 who have ever smoked. Silent until it is not.",
                citation: "USPSTF 2019 grade B"),

            ScreeningItem(
                id: "lungCT",
                title: "Low-dose lung CT",
                tier: .recommended,
                icon: "lungs",
                startAge: 50,
                stopAge: 80,
                intervalMonths: 12,
                requiresRiskFlag: .tobaccoEverSmoker,
                evidence: "Yearly from 50 with a 20 pack-year history. Answer the tobacco question to enable it.",
                citation: "USPSTF 2021 grade B")
        ]

        // MARK: Tier discuss (never due, never late)

        static let discuss: [ScreeningItem] = [
            ScreeningItem(
                id: "calciumScore",
                title: "Coronary calcium score",
                tier: .discuss,
                icon: "heart.circle",
                startAge: 40,
                intervalMonths: nil,
                evidence: "A decision aid, not a screening test: it reclassifies risk when a statin decision is genuinely borderline.",
                citation: "ACC/AHA 2018",
                // Present so the page can sort this to the top of the discuss
                // section for someone with early cardiac family history. The
                // tier still forbids a due state.
                modifiers: [ScreeningModifier(flag: .familyEarlyCardiac)]),

            ScreeningItem(
                id: "skinExam",
                title: "Skin examination",
                tier: .discuss,
                icon: "hand.raised.fingers.spread",
                startAge: 18,
                intervalMonths: 12,
                evidence: "Evidence is insufficient either way for people without symptoms. Worth raising if you have a family history or many moles.",
                citation: "USPSTF grade I",
                modifiers: [ScreeningModifier(flag: .familyMelanoma)]),

            ScreeningItem(
                id: "psa",
                title: "PSA test",
                tier: .discuss,
                icon: "flask",
                eligibility: .male,
                startAge: 55,
                stopAge: 69,
                intervalMonths: 24,
                evidence: "A shared decision between 55 and 69, not a default. The harms of overdiagnosis are real.",
                citation: "USPSTF 2018 grade C",
                modifiers: [ScreeningModifier(flag: .familyProstate)]),

            ScreeningItem(
                id: "dental",
                title: "Dental checkup",
                tier: .discuss,
                icon: "mouth",
                startAge: 18,
                intervalMonths: 12,
                evidence: "No federal screening recommendation exists. Professional consensus is roughly annual.",
                citation: "professional consensus"),

            ScreeningItem(
                id: "vision",
                title: "Eye examination",
                tier: .discuss,
                icon: "eye",
                startAge: 18,
                intervalMonths: 24,
                evidence: "Evidence is insufficient for asymptomatic adults. Different question if you notice a change.",
                citation: "USPSTF grade I"),

            ScreeningItem(
                id: "hearing",
                title: "Hearing test",
                tier: .discuss,
                icon: "ear",
                startAge: 50,
                intervalMonths: 24,
                evidence: "Evidence is insufficient for routine screening in adults who report no difficulty.",
                citation: "USPSTF grade I"),

            ScreeningItem(
                id: "sleepStudy",
                title: "Sleep study",
                tier: .discuss,
                icon: "bed.double",
                startAge: 18,
                intervalMonths: nil,
                evidence: "Driven by symptoms, not by population screening. Snoring plus daytime sleepiness is the conversation starter.",
                citation: "USPSTF grade I")
        ]
    }
}
