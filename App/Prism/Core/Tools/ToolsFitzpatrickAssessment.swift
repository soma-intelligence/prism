//
//  ToolsFitzpatrickAssessment.swift
//  Prism
//
//  The Fitzpatrick self-assessment: ten scored questions that place a
//  phototype for someone who does not know theirs. Sun Budget and the vitamin
//  D estimate both need a Fitzpatrick type, and a bare roman numeral picker
//  only works for a user who already knows the answer.
//
//  WHY A QUESTIONNAIRE AND NOT THE CAMERA. Fitzpatrick is defined by how skin
//  REACTS to sun, burning and tanning, not by how dark it looks. Two people
//  with the same measured tone can sit two types apart. The reaction history
//  is something only the user can report, so a questionnaire is the
//  instrument, not a fallback for a missing camera.
//
//  THE INSTRUMENT. Ten items in three sections (genetic disposition, reaction
//  to sun exposure, tanning habits), each scored 0 to 4, so the total runs 0
//  to 40 and rises with tolerance to sun. This is the standard self
//  administered form of the Fitzpatrick scale (Fitzpatrick 1988), the same
//  scale `ErythemalDoseEngine.medJPerM2` keys its minimal erythemal doses on.
//
//  WHAT IT IS NOT. A wellness estimate, like everything around it. The last
//  two items ask about RECENT sun exposure, so a freshly tanned person scores
//  higher and lands a type up: that is intended for burn risk purposes (tanned
//  skin does burn slower today) and it means the result is a phototype AS OF
//  NOW, not an immutable trait. It is not a dermatological diagnosis and it
//  does not assess skin cancer risk.
//
//  Pure and nonisolated. The questions and answers are the copy the sheet
//  shows, kept here as plain English strings next to the scoring so an item
//  cannot be added without its prose.
//

import Foundation

extension SomaTools {

    nonisolated enum FitzpatrickAssessment {

        // MARK: - Items

        /// The three sections of the form. They only group the items for
        /// display; every item scores on the same 0 to 4 scale and the total is
        /// one sum.
        nonisolated enum Section: Int, CaseIterable, Sendable, Identifiable {
            case geneticDisposition
            case sunReaction
            case tanningHabits

            var id: Int { rawValue }

            var items: [Item] { Item.allCases.filter { $0.section == self } }

            /// Section heading on the sheet.
            var title: String {
                switch self {
                case .geneticDisposition: return "Genetic disposition"
                case .sunReaction:        return "Reaction to sun"
                case .tanningHabits:      return "Recent sun habits"
                }
            }
        }

        /// One question. The raw value is its position in the form, so a stored
        /// answer set keeps its meaning as long as the cases keep their numbers.
        /// APPEND ONLY: renumbering an existing case silently re-reads old
        /// answers as answers to a different question.
        nonisolated enum Item: Int, CaseIterable, Identifiable, Sendable {
            case eyeColour = 0
            case hairColour = 1
            case skinColour = 2
            case freckles = 3
            case sunburn = 4
            case tanDepth = 5
            case tanSpeed = 6
            case faceSensitivity = 7
            case lastExposure = 8
            case faceExposure = 9

            var id: Int { rawValue }

            var section: Section {
                switch self {
                case .eyeColour, .hairColour, .skinColour, .freckles:
                    return .geneticDisposition
                case .sunburn, .tanDepth, .tanSpeed, .faceSensitivity:
                    return .sunReaction
                case .lastExposure, .faceExposure:
                    return .tanningHabits
                }
            }

            /// The question as the sheet asks it.
            var prompt: String {
                switch self {
                case .eyeColour:       return "What colour are your eyes?"
                case .hairColour:      return "What is your natural hair colour?"
                case .skinColour:      return "What colour is your skin where the sun never reaches it?"
                case .freckles:        return "How many freckles do you have on skin the sun does not reach?"
                case .sunburn:         return "What happens if you stay too long in the sun?"
                case .tanDepth:        return "How deeply do you tan?"
                case .tanSpeed:        return "Do you turn brown within a few hours of sun exposure?"
                case .faceSensitivity: return "How does your face react to the sun?"
                case .lastExposure:    return "When did you last expose your skin to the sun, a sunlamp or self-tanner?"
                case .faceExposure:    return "Do you expose your face to the sun?"
                }
            }

            /// The five answers, in `optionPoints` order (lowest tolerance
            /// first), so `options[points]` is the answer worth `points`.
            var options: [String] {
                switch self {
                case .eyeColour:
                    return ["Light blue, grey or green", "Blue, grey or green",
                            "Hazel or light brown", "Dark brown", "Brownish black"]
                case .hairColour:
                    return ["Red", "Blond", "Chestnut or dark blond", "Dark brown", "Black"]
                case .skinColour:
                    return ["Reddish", "Very pale", "Pale with a beige tint",
                            "Light brown", "Dark brown"]
                case .freckles:
                    return ["Many", "Several", "A few", "Almost none", "None"]
                case .sunburn:
                    return ["Painful redness, blisters, peeling", "Blisters, then peeling",
                            "Burns, sometimes followed by peeling", "Rarely burns", "Never burns"]
                case .tanDepth:
                    return ["Hardly, or not at all", "A light tan", "A decent tan",
                            "Tans easily", "Goes dark brown quickly"]
                case .tanSpeed:
                    return ["Never", "Rarely", "Sometimes", "Often", "Always"]
                case .faceSensitivity:
                    return ["Very sensitive", "Sensitive", "Normal",
                            "Very resistant", "Never had a problem"]
                case .lastExposure:
                    return ["More than three months ago", "Two to three months ago",
                            "One to two months ago", "Less than a month ago",
                            "Less than two weeks ago"]
                case .faceExposure:
                    return ["Never", "Hardly ever", "Sometimes", "Often", "Always"]
                }
            }

            /// The answer text worth `points`. Anything outside `optionPoints`
            /// returns the lowest option rather than trapping, since a corrupted
            /// stored answer must not crash a settings screen.
            func option(points: Int) -> String {
                let options = options
                guard points >= 0, points < options.count else { return options[0] }
                return options[points]
            }
        }

        /// Points an option can carry. Every item offers exactly these five, in
        /// this order, lowest tolerance first. Kept as one shared range rather
        /// than per-item lists: the instrument's scoring is uniform, and an item
        /// that quietly used a different scale would break the total's meaning.
        static let optionPoints: [Int] = [0, 1, 2, 3, 4]

        /// The best possible total, i.e. every item at maximum tolerance.
        static var maximumTotal: Int { Item.allCases.count * (optionPoints.last ?? 0) }

        // MARK: - Scoring

        /// The published score bands of the self-assessment, lightest first.
        /// Each band is closed and they tile 0 to `maximumTotal` with no gap and
        /// no overlap, which the tests assert.
        static let bands: [(range: ClosedRange<Int>, type: Fitzpatrick)] = [
            (0...6,   .typeI),
            (7...13,  .typeII),
            (14...20, .typeIII),
            (21...27, .typeIV),
            (28...34, .typeV),
            (35...40, .typeVI)
        ]

        /// The phototype for a total. Totals outside 0 to `maximumTotal` cannot
        /// come from a completed form; they clamp to the nearest end rather than
        /// returning nil, so a corrupted stored answer still yields a usable
        /// type instead of blanking the pages that read it.
        static func type(forTotal total: Int) -> Fitzpatrick {
            let clamped = min(max(total, 0), maximumTotal)
            return bands.first { $0.range.contains(clamped) }?.type ?? .typeIII
        }

        /// The band a phototype occupies, for showing how far a total sits from
        /// the next type. nil for a type no band names, which cannot happen
        /// while `bands` covers all six.
        static func band(for type: Fitzpatrick) -> ClosedRange<Int>? {
            bands.first { $0.type == type }?.range
        }

        // MARK: - Result

        /// A scored form. Only ever built from a COMPLETE answer set: a partial
        /// form has no total, and a total over nine items would read as a very
        /// low tolerance tenth answer rather than as missing data.
        nonisolated struct Result: Equatable, Sendable {
            let total: Int
            let type: Fitzpatrick
            /// Points to the nearest band edge, 0 when the total sits exactly on
            /// one. Small values mean the answer sits at a boundary and the
            /// neighbouring type is nearly as defensible, which the sheet says
            /// out loud rather than presenting the type as exact.
            let pointsToNearestEdge: Int

            /// Whether the sheet should show `Copy.borderline` under the result.
            var isBorderline: Bool { pointsToNearestEdge <= 1 }
        }

        /// Scores a complete set of answers. nil when any item is unanswered or
        /// any answer falls outside `optionPoints`.
        static func result(answers: [Item: Int]) -> Result? {
            var total = 0
            for item in Item.allCases {
                guard let points = answers[item], optionPoints.contains(points) else { return nil }
                total += points
            }
            let type = type(forTotal: total)
            guard let band = band(for: type) else { return nil }
            return Result(total: total,
                          type: type,
                          pointsToNearestEdge: min(total - band.lowerBound, band.upperBound - total))
        }

        // MARK: - Persistence

        /// Answers as a compact string, one point value per item in `Item` order.
        ///
        /// Deliberately NOT a Codable blob: adding a non-optional field to a
        /// persisted Codable wipes every stored value on the next read. A comma
        /// joined list of small integers survives anything except a renumbering
        /// of `Item`, and a list of the wrong length is simply refused below.
        static func encode(answers: [Item: Int]) -> String? {
            let points = Item.allCases.compactMap { answers[$0] }
            guard points.count == Item.allCases.count else { return nil }
            return points.map(String.init).joined(separator: ",")
        }

        /// Reads back what `encode` wrote. nil on anything unexpected (wrong
        /// length, non-numeric, out of range points), so a stale or hand edited
        /// value reopens an empty form instead of showing invented answers.
        static func decode(_ raw: String) -> [Item: Int]? {
            let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == Item.allCases.count else { return nil }
            var answers: [Item: Int] = [:]
            for (item, part) in zip(Item.allCases, parts) {
                guard let points = Int(part), optionPoints.contains(points) else { return nil }
                answers[item] = points
            }
            return answers
        }

        // MARK: - Sheet copy

        /// The fixed prose around the questions. Plain English; the counts are
        /// formatted by `progress(answered:)` and `score(_:)`.
        nonisolated enum Copy {
            static let entryLink = "I don\u{2019}t know my type"
            static let sheetTitle = "Your skin type"
            static let intro = "Ten questions place your phototype, the scale both the burn time and the vitamin D estimate are keyed on. Answer for your skin as it is right now."
            static let borderline = "This total sits on the edge of its band. The neighbouring type fits nearly as well, so pick whichever matches how you actually burn."
            static let caveat = "The last two questions ask about recent sun, so a fresh tan lifts the result: this is your phototype as of today, not a fixed trait. A wellness estimate, not a medical assessment."
            static let fromAnswers = "From your answers"
            static let assumed = "Assumed, not answered"
            static let settingDetail = "The burn time and the vitamin D estimate are both keyed on this type, and they swing by roughly a factor of five across the six. Pick the numeral if you know yours, or answer the ten questions."

            /// "4 of 10 answered".
            static func progress(answered: Int) -> String {
                "\(answered) of \(Item.allCases.count) answered"
            }

            /// "Score 17 of 40".
            static func score(_ total: Int) -> String {
                "Score \(total) of \(maximumTotal)"
            }
        }
    }
}
