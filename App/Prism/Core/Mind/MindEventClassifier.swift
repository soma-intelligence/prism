//
//  MindEventClassifier.swift
//  Prism
//
//  What a moment of the day is, and which way it pulls by default: words
//  only, never the length; the most
//  specific category wins; the calendar's name is read only when the title
//  says nothing; and an unknown title weighs zero rather than being forced
//  into the nearest category. Titles never leave the phone.
//
//  Soma adds food, which the Figma's day sheet groups on its own.
//

import Foundation

nonisolated enum MindEventCategory: String, CaseIterable, Codable, Sendable {
    case restorative, social, focus, meeting, admin, care, travel, food, unknown

    /// The heading the day sheet groups by.
    var title: String {
        switch self {
        case .restorative: "Movement"
        case .social: "People"
        case .focus: "Focus"
        case .meeting: "Work"
        case .admin: "Errands"
        case .care: "Care"
        case .travel: "Travel"
        case .food: "Food"
        case .unknown: "Other"
        }
    }

    /// The signed cold start weight, in points, before a person's own days
    /// say otherwise: a session can make up for a meeting and a half, and
    /// care is not punished like a chore.
    var points: Double {
        switch self {
        case .restorative: 8
        case .social: 5
        case .focus: 2
        case .food: 0
        case .care: -1
        case .admin: -3
        case .travel: -3
        case .meeting: -4
        case .unknown: 0
        }
    }

    /// The categories a correction can choose, what gives first.
    static let selectable: [MindEventCategory] = [.restorative, .social, .food, .focus, .care, .admin, .travel, .meeting]
}

nonisolated enum MindEventClassifier {
    /// The most specific first: care, movement, travel and errands name an
    /// activity; meetings and people are catch-alls, so they go last.
    private static let order: [MindEventCategory] = [.care, .restorative, .travel, .admin, .food, .focus, .social, .meeting]

    static func category(title: String, calendarTitle: String = "") -> MindEventCategory {
        for text in [title, calendarTitle] {
            let hay = normalize(text)
            guard !hay.isEmpty else { continue }
            if let found = order.first(where: { category in keywords[category]?.contains { hay.contains($0) } ?? false }) {
                return found
            }
        }
        return .unknown
    }

    /// Lowercase, accents folded, punctuation to spaces, one guard space on
    /// each side, so a short keyword never matches inside a longer word.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : " " + trimmed + " "
    }

    /// The key a person's correction is kept under: the folded title, so
    /// renaming one "Weekly sync" renames them all.
    static func fingerprint(_ title: String) -> String {
        String(normalize(title).trimmingCharacters(in: .whitespaces).prefix(64))
    }

    static let keywords: [MindEventCategory: [String]] = [
        .restorative: [
            " sport ", " gym ", " yoga ", " pilates ", " run ", " running ", " swim ", " workout ",
            " training ", " climbing ", " tennis ", " padel ", " football ", " walk ", " walked ",
            " hike ", " nap ", " massage ", " spa ", " sauna ", " meditation ", " breathwork ",
            " stretch ", " mobility ", " seance ", " muscu ", " piscine ", " course ", " marche ",
            " randonnee ", " sieste ", " escalade ", " bike ", " ride ", " park ",
        ],
        .social: [
            " drinks ", " birthday ", " party ", " family ", " friends ", " coffee with ", " date ",
            " wedding ", " visit ", " apero ", " anniversaire ", " famille ", " amis ", " soiree ",
            " mariage ", " sister ", " brother ", " mum ", " mom ", " dad ", " call with ",
        ],
        .food: [
            " breakfast ", " lunch ", " dinner ", " brunch ", " meal ", " restaurant ", " cook ",
            " cooking ", " dejeuner ", " diner ", " repas ", " petit dejeuner ",
        ],
        .focus: [
            " deep work ", " focus ", " writing ", " study ", " revision ", " research ", " prep ",
            " coding ", " redaction ", " ecriture ", " etude ", " recherche ", " preparation ",
        ],
        .meeting: [
            " meeting ", " meetings ", " call ", " standup ", " stand up ", " sync ", " review ",
            " 1 1 ", " one on one ", " one to one ", " interview ", " workshop ", " demo ", " kickoff ",
            " retro ", " debrief ", " presentation ", " board ", " client ", " reunion ", " appel ",
            " entretien ", " point ", " comite ", " atelier ", " visio ", " conference ", " email ",
            " emails ", " office ", " work ",
        ],
        .admin: [
            " bank ", " tax ", " taxes ", " paperwork ", " insurance ", " admin ", " renewal ",
            " moving ", " notary ", " lawyer ", " banque ", " impots ", " assurance ", " demarches ",
            " demenagement ", " notaire ", " avocat ", " prefecture ", " errand ", " errands ",
        ],
        .care: [
            " doctor ", " dentist ", " therapy ", " therapist ", " physio ", " osteopath ", " checkup ",
            " check up ", " blood test ", " clinic ", " hospital ", " vaccine ", " surgery ", " psy ",
            " medecin ", " docteur ", " dentiste ", " therapie ", " kine ", " osteo ", " prise de sang ",
            " hopital ", " vaccin ",
        ],
        .travel: [
            " flight ", " airport ", " train ", " commute ", " drive ", " road trip ", " departure ",
            " arrival ", " vol ", " aeroport ", " gare ", " trajet ", " navette ",
        ],
    ]
}
