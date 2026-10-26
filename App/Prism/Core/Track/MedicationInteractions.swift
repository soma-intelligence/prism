//
//  MedicationInteractions.swift
//  Prism
//
//  A short, sourced table of what a supplement on the plan can do to a blood
//  result or to a medication. It is not a drug database and claims no
//  completeness: each row is one well documented pair, worded as
//  information, and every one ends by sending the person to the doctor,
//  pharmacist or lab who knows the rest. Nothing here suggests an amount.
//

import Foundation

/// One thing worth knowing about a supplement next to a marker or a
/// medication.
nonisolated struct InteractionNote: Identifiable, Equatable, Sendable {
    /// The rule and what it met: one note per marker or medication.
    var id: String { ruleID + "." + (markerID ?? subject) }
    /// The table row the note comes from, so a page can fold the notes of
    /// one rule into one card.
    let ruleID: String
    /// The supplement as it is named on the plan.
    let supplement: String
    /// The blood marker the note is about, nil for a medication pair.
    let markerID: String?
    /// The marker's or the medication's name, as the person reads it.
    let subject: String
    let text: String
    /// Where the row comes from.
    let source: String
}

nonisolated enum MedicationInteractions {
    /// One row of the table.
    struct Rule: Sendable {
        let id: String
        /// Names the supplement goes by on a label, folded (see ``fold(_:)``).
        let supplementNames: [String]
        /// Marker ids in ``BloodMarkerCatalog``, and words for a marker typed
        /// by hand that the catalog does not hold (troponin).
        let markerIDs: Set<String>
        let markerWords: [String]
        /// Medication names, folded, generic and common brand names.
        let medicationNames: [String]
        let text: @Sendable (_ supplement: String, _ subject: String) -> String
        let source: String
    }

    static let biotin = Rule(
        id: "biotin",
        supplementNames: ["biotin", "biotine", "vitamin b7", "vitamine b7", "vitamin h", "b7"],
        markerIDs: ["tsh", "freeT4", "freeT3"],
        markerWords: ["troponin", "troponine"],
        medicationNames: [],
        text: { supplement, subject in
            String(localized: "\(supplement) can interfere with many lab tests and make \(subject) read falsely high or low. Tell your doctor or the lab you take it before the next draw.")
        },
        source: "FDA Safety Communication on biotin and lab tests, 2017, updated 2019"
    )

    static let creatine = Rule(
        id: "creatine",
        supplementNames: ["creatine", "kreatin"],
        markerIDs: ["creatinine", "egfr"],
        markerWords: [],
        medicationNames: [],
        text: { supplement, subject in
            String(localized: "\(supplement) raises blood creatinine with no change in the kidneys, which can make \(subject) look worse than the kidneys are. Mention it to whoever reads this result.")
        },
        source: "ISSN position stand on creatine, Kreider et al., 2017"
    )

    /// Vitamin K antagonists only: the newer anticoagulants do not act
    /// through vitamin K.
    static let vitaminK = Rule(
        id: "vitaminK",
        supplementNames: ["vitamin k", "vitamin k1", "vitamin k2", "vitamine k", "vitamine k2", "k2", "mk 7", "mk7",
                          "menaquinone", "phylloquinone", "phytonadione"],
        markerIDs: [],
        markerWords: [],
        medicationNames: ["warfarin", "coumadin", "jantoven", "acenocoumarol", "sintrom", "phenprocoumon",
                          "marcumar", "fluindione", "previscan"],
        text: { supplement, subject in
            String(localized: "\(supplement) works against \(subject), and a change in it can shift your INR. Talk to the doctor who follows your INR before starting, stopping or changing it.")
        },
        source: "NIH Office of Dietary Supplements, Vitamin K fact sheet"
    )

    static let stJohnsWort = Rule(
        id: "stJohnsWort",
        supplementNames: ["st john s wort", "saint john s wort", "st johns wort", "hypericum", "millepertuis"],
        markerIDs: [],
        markerWords: [],
        medicationNames: ["sertraline", "zoloft", "fluoxetine", "prozac", "paroxetine", "paxil", "deroxat",
                          "citalopram", "celexa", "escitalopram", "lexapro", "seroplex", "fluvoxamine",
                          "venlafaxine", "effexor", "desvenlafaxine", "duloxetine", "cymbalta", "vortioxetine",
                          "mirtazapine", "trazodone", "amitriptyline", "nortriptyline", "clomipramine"],
        text: { supplement, subject in
            String(localized: "\(supplement) taken with \(subject) can raise the risk of serotonin syndrome, and it changes how well many other medicines work. Talk to your doctor or pharmacist before taking both.")
        },
        source: "NCCIH, St. John's Wort"
    )

    static let rules = [biotin, creatine, vitaminK, stJohnsWort]

    /// The notes for the active supplements on the plan against the markers
    /// of a panel and the medications the person takes. Empty when nothing
    /// meets: no note is the common case and says nothing is wrong.
    ///
    /// - Parameter medications: medication names as Apple Health or the plan
    ///   holds them ("Warfarin 5 mg" matches warfarin).
    static func notes(for supplements: [TrackSupplement], markers: [BloodMarker], medications: [String] = []) -> [InteractionNote] {
        var notes: [InteractionNote] = []
        var seen: Set<String> = []
        for supplement in supplements where supplement.isActive {
            for rule in rules where matches(supplement.name, any: rule.supplementNames) {
                for marker in markers where rule.markerIDs.contains(marker.id) || matches(marker.name, any: rule.markerWords) {
                    let note = InteractionNote(ruleID: rule.id, supplement: supplement.name, markerID: marker.id,
                                               subject: marker.name, text: rule.text(supplement.name, marker.name),
                                               source: rule.source)
                    if seen.insert(note.id).inserted { notes.append(note) }
                }
                for medication in medications where matches(medication, any: rule.medicationNames) {
                    let note = InteractionNote(ruleID: rule.id, supplement: supplement.name, markerID: nil,
                                               subject: medication, text: rule.text(supplement.name, medication),
                                               source: rule.source)
                    if seen.insert(note.id).inserted { notes.append(note) }
                }
            }
        }
        return notes
    }

    /// The notes of one rule and one supplement folded into one, its
    /// subjects listed ("TSH and Free T4"): one card per supplement and
    /// rule on a page, in the order the notes came.
    static func folded(_ notes: [InteractionNote]) -> [InteractionNote] {
        var order: [String] = []
        var groups: [String: [InteractionNote]] = [:]
        for note in notes {
            let key = note.ruleID + "|" + note.supplement
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(note)
        }
        return order.compactMap { key in
            guard let group = groups[key], let first = group.first,
                  let rule = rules.first(where: { $0.id == first.ruleID }) else { return nil }
            guard group.count > 1 else { return first }
            let subject = group.map(\.subject).formatted(.list(type: .and))
            return InteractionNote(ruleID: first.ruleID, supplement: first.supplement, markerID: first.markerID,
                                   subject: subject, text: rule.text(first.supplement, subject), source: first.source)
        }
    }

    /// Lower case, accents dropped, anything that is not a letter or a digit
    /// turned into a space: "St. John's Wort" reads "st john s wort".
    static func fold(_ name: String) -> String {
        let plain = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let spaced = plain.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Whether one of `names` appears in `text` as whole words.
    static func matches(_ text: String, any names: [String]) -> Bool {
        let words = " " + fold(text) + " "
        return names.contains { words.contains(" " + fold($0) + " ") }
    }
}
