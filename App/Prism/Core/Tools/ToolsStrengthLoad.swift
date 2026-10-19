//
//  ToolsStrengthLoad.swift
//  Prism
//
//  Progressive overload from logged strength sessions.
//
//  Pure and input driven: the caller hands in sessions, the engine does
//  arithmetic. No store, no HealthKit. The session model is this tool's own,
//  minimal on purpose: an exercise id and name, a date, reps and kilograms.
//
//  Two deliberate limits, both about honesty rather than effort:
//
//  1. Only sets that were actually completed AND carry both reps and weight
//     count. A bodyweight or time only set is real training but it is not
//     volume load, and folding it in with a zero would silently deflate the
//     number.
//  2. The estimated one rep max uses Epley, which is only meaningful under
//     about ten reps. Above that the formula drifts high, so high rep sets are
//     left out of the e1RM rather than quietly inflating a personal record.
//

import Foundation

extension SomaTools {

    nonisolated enum StrengthLoad {

        // MARK: Model

        struct LiftSet: Sendable, Equatable, Codable, Identifiable {
            var id: UUID
            var reps: Int?
            var weightKg: Double?
            /// nil reads as done: a set logged without a checkbox was lifted.
            var completed: Bool?

            init(id: UUID = UUID(), reps: Int?, weightKg: Double?, completed: Bool? = nil) {
                self.id = id
                self.reps = reps
                self.weightKg = weightKg
                self.completed = completed
            }

            var countsAsDone: Bool { completed ?? true }
        }

        struct Exercise: Sendable, Equatable, Codable, Identifiable {
            var exerciseID: String
            var name: String
            var sets: [LiftSet]
            var id: String { exerciseID }

            init(exerciseID: String, name: String? = nil, sets: [LiftSet] = []) {
                self.exerciseID = exerciseID
                self.name = name ?? exerciseID
                self.sets = sets
            }
        }

        struct Session: Sendable, Equatable, Codable, Identifiable {
            var id: UUID
            var date: Date
            var exercises: [Exercise]

            init(id: UUID = UUID(), date: Date, exercises: [Exercise]) {
                self.id = id
                self.date = date
                self.exercises = exercises
            }
        }

        // MARK: Tunables

        /// Reps above which Epley stops being trustworthy.
        static let maxRepsForOneRepMax = 10
        /// Week over week change, as a fraction, inside which load reads as
        /// held. Training volume is noisy; a 5% wobble is not a trend.
        static let flatBand = 0.05
        /// Weekly rise above which load climbs faster than tissue adapts. The
        /// usual guidance is about 10% a week at most.
        static let fastRise = 0.10
        /// Weeks the tool page shows.
        static let defaultWeekCount = 8

        // MARK: Set level

        /// Volume load of one set: reps times weight. nil unless completed and
        /// carrying both numbers.
        static func volumeLoad(of set: LiftSet) -> Double? {
            guard set.countsAsDone,
                  let reps = set.reps, reps > 0,
                  let weight = set.weightKg, weight > 0 else { return nil }
            return Double(reps) * weight
        }

        /// Epley estimated one rep max: weight times (1 + reps / 30). nil for a
        /// set that is incomplete, unloaded, or above `maxRepsForOneRepMax`.
        static func estimatedOneRepMax(of set: LiftSet) -> Double? {
            guard set.countsAsDone,
                  let reps = set.reps, reps > 0, reps <= maxRepsForOneRepMax,
                  let weight = set.weightKg, weight > 0 else { return nil }
            return weight * (1 + Double(reps) / 30)
        }

        // MARK: Session level

        /// Total volume load of a session, in kilogram reps.
        static func volumeLoad(of session: Session) -> Double {
            session.exercises.flatMap(\.sets).compactMap(volumeLoad(of:)).reduce(0, +)
        }

        /// Best estimated one rep max per exercise id in a session.
        static func bestOneRepMaxes(in session: Session) -> [String: Double] {
            var best: [String: Double] = [:]
            for exercise in session.exercises {
                for set in exercise.sets {
                    guard let e1rm = estimatedOneRepMax(of: set) else { continue }
                    best[exercise.exerciseID] = max(best[exercise.exerciseID] ?? 0, e1rm)
                }
            }
            return best
        }

        // MARK: Weekly rollup

        struct Week: Sendable, Equatable, Identifiable {
            /// 0 is the most recent week, 1 the one before, and so on.
            let index: Int
            let volumeLoad: Double
            let sessionCount: Int
            var id: Int { index }
        }

        /// Volume load in trailing 7 day windows ending at `end`. Index 0 is
        /// the current week. A week with no session is kept at zero, because a
        /// missed week is information, not a gap to skip.
        static func weeks(from sessions: [Session],
                          endingOn end: Date,
                          count: Int,
                          calendar: Calendar = .current) -> [Week] {
            guard count > 0 else { return [] }
            return (0..<count).map { index in
                let upper = calendar.date(byAdding: .day, value: -7 * index, to: end) ?? end
                let lower = calendar.date(byAdding: .day, value: -7, to: upper) ?? upper
                let inWeek = sessions.filter { $0.date > lower && $0.date <= upper }
                return Week(index: index,
                            volumeLoad: inWeek.reduce(0) { $0 + volumeLoad(of: $1) },
                            sessionCount: inWeek.count)
            }
        }

        // MARK: Verdict

        enum Trend: String, Sendable, Equatable {
            /// Climbing within a sustainable range.
            case building
            /// Climbing faster than tissue usually adapts. A caution about
            /// pacing, not a fault.
            case climbingFast
            /// Inside the flat band.
            case holding
            /// Falling. Neutral: a deload is deliberate training.
            case easing

            var label: String {
                switch self {
                case .building: return "Building"
                case .climbingFast: return "Climbing fast"
                case .holding: return "Holding"
                case .easing: return "Easing"
                }
            }
        }

        struct Report: Sendable, Equatable {
            let weeks: [Week]
            let currentVolume: Double
            let previousVolume: Double
            /// Signed week over week change as a fraction. nil when the previous
            /// week had no load, so nothing is divided by zero and no trend is
            /// invented from a standing start.
            let weekOverWeekChange: Double?
            let trend: Trend
            let currentSessionCount: Int
            /// True when there is not enough logged lifting to say anything.
            let isEmpty: Bool

            /// Mean of the weeks before this one that carried any load. A rest
            /// week is kept out on purpose: the reference is "a week you train",
            /// not the calendar.
            var priorLoadedWeeksMean: Double? {
                let prior = weeks.dropFirst().map(\.volumeLoad).filter { $0 > 0 }
                guard !prior.isEmpty else { return nil }
                return prior.reduce(0, +) / Double(prior.count)
            }

            /// The weeks oldest first, for a chart drawn left to right.
            var weeksOldestFirst: [Week] { weeks.reversed() }
        }

        static func report(from sessions: [Session],
                           endingOn end: Date,
                           weekCount: Int = defaultWeekCount,
                           calendar: Calendar = .current) -> Report {
            let buckets = weeks(from: sessions, endingOn: end, count: max(2, weekCount), calendar: calendar)
            let current = buckets.first?.volumeLoad ?? 0
            let previous = buckets.count > 1 ? buckets[1].volumeLoad : 0
            let change: Double? = previous > 0 ? (current - previous) / previous : nil

            let trend: Trend
            if let change {
                if change > fastRise { trend = .climbingFast }
                else if change > flatBand { trend = .building }
                else if change < -flatBand { trend = .easing }
                else { trend = .holding }
            } else {
                trend = current > 0 ? .building : .holding
            }

            return Report(weeks: buckets,
                          currentVolume: current,
                          previousVolume: previous,
                          weekOverWeekChange: change,
                          trend: trend,
                          currentSessionCount: buckets.first?.sessionCount ?? 0,
                          isEmpty: buckets.allSatisfy { $0.volumeLoad <= 0 })
        }

        // MARK: Per exercise progression

        struct ExerciseProgress: Sendable, Equatable, Identifiable {
            let exerciseID: String
            /// Name from the most recent session the exercise appeared in.
            let name: String
            /// Best estimated one rep max ever seen in the supplied sessions.
            let bestOneRepMax: Double
            /// Most recent session's best for the same exercise.
            let latestOneRepMax: Double
            /// Best estimate before the most recent session, nil on a first
            /// appearance.
            let previousBestOneRepMax: Double?
            /// Sessions the exercise appeared in.
            let appearances: Int
            let latestDate: Date

            var id: String { exerciseID }
            /// True when the latest session matched or beat the all time best.
            var isAtBest: Bool { latestOneRepMax >= bestOneRepMax }
            /// Soma addition: true when the latest session strictly beat every
            /// earlier one. A first appearance is not a record, it is a start.
            var isNewPersonalBest: Bool {
                guard let previousBestOneRepMax else { return false }
                return latestOneRepMax > previousBestOneRepMax
            }
        }

        /// Per exercise one rep max progression, strongest first. Only exercises
        /// with at least one Epley eligible set appear.
        static func progression(from sessions: [Session]) -> [ExerciseProgress] {
            let ordered = sessions.sorted { $0.date < $1.date }
            var best: [String: Double] = [:]
            var previousBest: [String: Double] = [:]
            var latest: [String: Double] = [:]
            var latestDate: [String: Date] = [:]
            var names: [String: String] = [:]
            var appearances: [String: Int] = [:]

            for session in ordered {
                let bests = bestOneRepMaxes(in: session)
                for exercise in session.exercises where bests[exercise.exerciseID] != nil {
                    names[exercise.exerciseID] = exercise.name
                }
                for (exerciseID, e1rm) in bests {
                    previousBest[exerciseID] = best[exerciseID]
                    best[exerciseID] = max(best[exerciseID] ?? 0, e1rm)
                    latest[exerciseID] = e1rm
                    latestDate[exerciseID] = session.date
                    appearances[exerciseID, default: 0] += 1
                }
            }

            return best.map { exerciseID, bestValue in
                ExerciseProgress(exerciseID: exerciseID,
                                 name: names[exerciseID] ?? exerciseID,
                                 bestOneRepMax: bestValue,
                                 latestOneRepMax: latest[exerciseID] ?? 0,
                                 previousBestOneRepMax: previousBest[exerciseID],
                                 appearances: appearances[exerciseID] ?? 0,
                                 latestDate: latestDate[exerciseID] ?? .distantPast)
            }
            .sorted { $0.bestOneRepMax > $1.bestOneRepMax }
        }

        /// The exercises whose latest session set a new personal best, most
        /// recent first.
        static func personalBests(from sessions: [Session]) -> [ExerciseProgress] {
            progression(from: sessions)
                .filter(\.isNewPersonalBest)
                .sorted { $0.latestDate > $1.latestDate }
        }

        // MARK: Formatting

        /// Signed whole percent, "+12%" or "-8%", for the week over week line.
        static func signedPercent(_ change: Double) -> String {
            let value = Int((change * 100).rounded())
            return value > 0 ? "+\(value)%" : "\(value)%"
        }
    }
}
