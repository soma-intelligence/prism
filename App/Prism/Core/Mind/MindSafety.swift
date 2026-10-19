//
//  MindSafety.swift
//  Prism
//
//  What Mind does when an entry reads as distress, with this bias:
//  showing the lines when they were not needed is acceptable, missing a
//  person who needed them is not.
//

import Foundation

/// How strong and how explicit a distress signal is.
nonisolated enum MindDistress: Int, Comparable, Sendable {
    /// Nothing in the entry asks for help.
    case none = 0
    /// A heavy entry with no words of danger: a very unpleasant feeling named
    /// hopeless, lonely or overwhelmed. The resources are offered, quietly.
    case heavy = 1
    /// A veiled disclosure: a means next to a loss, or a sense of being a
    /// burden. Treated as a positive signal on purpose.
    case indirect = 2
    /// Explicit words of ending one's life, self harm or harming someone.
    case direct = 3

    static func < (lhs: MindDistress, rhs: MindDistress) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Whether the resources open at once rather than as an offer.
    var isUrgent: Bool { self >= .indirect }
}

/// The deterministic guard. Every word it knows is written here, never
/// generated, and the entry never leaves the phone to be judged.
nonisolated enum MindSafetyGuard {
    /// The feelings that make a very unpleasant entry a heavy one.
    static let heavyLabels: Set<String> = ["hopeless", "lonely", "overwhelmed", "ashamed", "drained", "scared"]
    /// At or under this valence (Apple's -1 to 1) an entry is very unpleasant.
    static let heavyValence = -0.6

    /// Reads one entry: its valence, the feelings named, and any words.
    static func check(valence: Double?, labels: [String], text: String) -> MindDistress {
        let fromText = classify(text)
        if fromText > .none { return fromText }
        if let valence, valence <= heavyValence, labels.contains(where: heavyLabels.contains) {
            return .heavy
        }
        return .none
    }

    // MARK: - Words

    private static let directIdeation: [String] = [
        "je veux mourir", "je vais me tuer", "je veux me suicider", "je vais me suicider",
        "me suicider", "en finir avec la vie", "en finir avec tout", "mettre fin a mes jours",
        "plus envie de vivre", "j ai plus envie d etre la", "je veux disparaitre",
        "je pense a en finir", "je veux en finir",
        "kill myself", "killing myself", "i want to die", "i m going to kill myself",
        "im going to kill myself", "end my life", "end my own life", "ending my life",
        "take my own life", "take my life", "taking my own life", "taking my life",
        "i don t want to be here anymore", "i don t want to be alive", "i want to disappear",
        "i can t go on", "i give up on life", "i no longer want to live",
        "i don t want to live anymore", "not worth living", "suicide", "suicid",
    ]

    private static let selfHarm: [String] = [
        "me faire du mal", "me mutiler", "me couper", "me scarifier",
        "self harm", "hurt myself", "cut myself", "burn myself", "injure myself", "harm myself",
    ]

    private static let harmToOthers: [String] = [
        "je vais le tuer", "je vais la tuer", "je vais les tuer",
        "kill them", "hurt them", "i want to hurt", "i will hurt", "i will kill",
    ]

    private static let means: [String] = [
        "pont", "corde", "pilules", "medicaments", "arme a feu", "fusil", "pistolet", "couteau", "lame", "toit",
        "bridge", "rope", "pills", "medication", "gun", "firearm", "rifle", "pistol", "knife", "blade",
        "overdose", "rooftop",
    ]

    private static let firstPersonIntent: [String] = [
        "j ai achete", "j ai pris", "j ai trouve", "je cherche", "je regarde", "je stocke",
        "j ai mis de cote", "je pense a utiliser", "j ai acces a",
        "i bought", "i purchased", "i found", "i am looking at", "i m looking at", "i stockpiled",
        "i stored", "i got", "i have access to", "i am thinking of using", "i m thinking of using",
        "thinking about using",
    ]

    private static let loss: [String] = [
        "perdu mon travail", "perdu mon emploi", "licencie", "rupture", "divorce", "deces",
        "lost my job", "got fired", "laid off", "break up", "breakup", "someone died", "death of",
    ]

    /// Burden and hopelessness: enough alone for the indirect tier.
    private static let burden: [String] = [
        "sans moi", "fardeau", "personne ne me regretterait", "tout le monde irait mieux",
        "je ne sers a rien", "je sers a rien", "plus d espoir", "aucune issue",
        "without me", "burden", "no one would miss me", "everyone would be better off",
        "nobody cares about me", "no one cares about me", "i am worthless", "i m worthless",
        "no hope", "no way out", "there is no point", "there s no point", "what s the point",
    ]

    /// The words of one entry, read for distress.
    static func classify(_ raw: String) -> MindDistress {
        let text = normalize(raw)
        guard !text.isEmpty else { return .none }
        let padded = " " + text + " "

        if (directIdeation + selfHarm + harmToOthers).contains(where: { padded.contains($0) }) {
            return .direct
        }
        if burden.contains(where: { padded.contains($0) }) { return .indirect }
        let meansHits = means.filter { padded.contains(" " + $0) }
        guard !meansHits.isEmpty else { return .none }
        if loss.contains(where: { padded.contains($0) }) { return .indirect }
        let intent = meansHits.contains { term in
            firstPersonIntent.contains { prefix in
                guard let p = padded.range(of: prefix), let m = padded.range(of: " " + term) else { return false }
                return p.lowerBound <= m.lowerBound
            }
        }
        return intent ? .indirect : .none
    }

    /// Lowercase, accents folded, apostrophes and dashes to spaces, spaces
    /// collapsed: "J’en ai fini" reads as "j en ai fini".
    static func normalize(_ raw: String) -> String {
        var text = raw
        for mark in ["\u{2019}", "\u{02BC}", "'", "-", "\u{2013}", "\u{2014}"] {
            text = text.replacingOccurrences(of: mark, with: " ")
        }
        return text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// One human line: a number to call, or a page to open when no number is
/// known for certain.
nonisolated struct MindCrisisLine: Equatable, Sendable, Identifiable {
    var name: String
    var dial: String?
    var web: URL?
    var hours: String

    var id: String { name + (dial ?? web?.absoluteString ?? "") }

    /// What tapping the row opens: the phone, or the directory.
    var url: URL? {
        if let dial {
            return URL(string: "tel:" + dial.filter { $0.isNumber || $0 == "+" })
        }
        return web
    }
}

/// Where to turn, by region. Hardcoded and never generated: a region gets
/// its own lines only when its crisis line is known with certainty, and
/// everywhere else gets the findahelpline.com directory rather than a
/// plausible wrong number.
nonisolated enum MindCrisisResources {
    static let title = "You’re not alone"
    static let disclaimer = "Soma is an app, not a health professional. If you’re in danger right now, reach one of these lines. They’re free, confidential and staffed by people."

    static let directory = MindCrisisLine(
        name: "Find a Helpline",
        web: URL(string: "https://findahelpline.com"),
        hours: "Lines for every country"
    )

    private static let europe112: Set<String> = [
        "AL", "AD", "BA", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "GR", "HU", "IS", "IT", "XK", "LV",
        "LI", "LT", "LU", "MT", "MD", "MC", "ME", "MK", "NO", "PL", "PT", "RO", "SM", "RS", "SK", "SI",
        "SE", "TR", "UA", "VA",
    ]

    static func lines(region raw: String?) -> [MindCrisisLine] {
        let region = (raw ?? "").uppercased()
        let always = "24/7"
        func line(_ name: String, _ dial: String) -> MindCrisisLine {
            MindCrisisLine(name: name, dial: dial, hours: always)
        }
        let own: [MindCrisisLine]? = switch region {
        case "US", "CA": [line("988 Suicide and Crisis Lifeline", "988"), line("Emergency services", "911")]
        case "FR": [line("3114, suicide prevention", "3114"), line("SAMU", "15")]
        case "BE": [line("Centre de prévention du suicide", "0800 32 123"), line("Zelfmoordlijn", "1813"), line("Emergency services", "112")]
        case "CH": [line("La Main Tendue", "143"), line("Emergency services", "144")]
        case "GB": [line("Samaritans", "116 123"), line("Emergency services", "999")]
        case "IE": [line("Samaritans Ireland", "116 123"), line("Emergency services", "112")]
        case "AU": [line("Lifeline Australia", "13 11 14"), line("Emergency services", "000")]
        case "ES": [line("024, suicide prevention", "024"), line("Emergency services", "112")]
        case "MX": [line("Línea de la Vida", "800 911 2000"), line("Emergency services", "911")]
        case "DE": [line("Telefonseelsorge", "0800 111 0 111"), line("Emergency services", "112")]
        case "AT": [line("Telefonseelsorge", "142"), line("Emergency services", "112")]
        case "NL": [line("113 Zelfmoordpreventie", "113"), line("Emergency services", "112")]
        case "KR": [line("109 suicide prevention", "109"), line("Emergency services", "119")]
        default: nil
        }
        if let own { return own + [directory] }
        return (europe112.contains(region) ? [line("Emergency services", "112")] : []) + [directory]
    }
}
