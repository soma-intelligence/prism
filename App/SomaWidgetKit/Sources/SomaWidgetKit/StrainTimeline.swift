import Foundation

/// When the Strain widget redraws: the same snapshot every quarter hour for
/// three hours, so the dot that marks now moves along the energy curve
/// between two writes by the app.
public enum StrainTimeline {
    /// How far ahead the last entry sits.
    public static let horizon: TimeInterval = 3 * 3600
    /// The gap between two entries.
    public static let step: TimeInterval = 15 * 60

    /// `now`, then every quarter hour up to three hours ahead: 13 dates.
    public static func entryDates(from now: Date) -> [Date] {
        let count = Int(horizon / step)
        return (0...count).map { now.addingTimeInterval(Double($0) * step) }
    }
}
