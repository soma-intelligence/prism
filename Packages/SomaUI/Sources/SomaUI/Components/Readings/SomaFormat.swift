//
//  SomaFormat.swift
//  SomaUI
//

import SwiftUI

/// How the app writes a duration and a plain number, in one place.
///
/// Sleep used to read "7:54" on Today, "7h 54m" in a hero, "7 hr 54 min" in a
/// card and "7 h 17" in a fast: four spellings of one thing. Every duration
/// goes through here instead, in the locale's narrow units ("7h 54m" in
/// English, "7h 54min" in French), whole minutes, a zero hour or minute left
/// out ("12h", "45m").
///
/// Two looks only: `duration(_:)` for a duration inside a line of text, and
/// ``SomaDurationText`` for a duration set large, its figures in one role and
/// its units smaller in another.
///
/// A value that was not measured is `nil` all the way to the view, which draws
/// ``SomaMissingValue``: never a hyphen, never a zero, and never a unit beside
/// the mark.
public enum SomaFormat {
    /// One part of a duration: its figures and the unit after them.
    public struct DurationPart: Sendable, Equatable, Hashable {
        public let value: String
        public let unit: String
    }

    /// A duration inside a line of text: "7h 54m", "45m", "12h".
    public static func duration(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        rounded(seconds).formatted(style(locale))
    }

    /// The same, or nil when nothing was measured, so the caller draws the
    /// missing mark rather than a hyphen.
    public static func duration(_ seconds: TimeInterval?, locale: Locale = .autoupdatingCurrent) -> String? {
        seconds.map { duration($0, locale: locale) }
    }

    /// A duration as its parts, figures apart from units, for a hero that
    /// sets the two in different roles: `[("7", "h"), ("54", "m")]`. The
    /// units are the locale's, read off the formatted string, never spelled
    /// here.
    public static func durationParts(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> [DurationPart] {
        let text = rounded(seconds).formatted(style(locale).attributed)
        var parts: [DurationPart] = []
        var value = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            switch run.measurement {
            case .value?:
                value += piece
            case .unit?:
                parts.append(DurationPart(value: value, unit: piece.trimmingCharacters(in: .whitespaces)))
                value = ""
            default:
                continue
            }
        }
        return parts
    }

    /// A plain number grouped the locale's way, to `decimals` places: "8,412",
    /// "36.5".
    public static func number(_ value: Double, decimals: Int = 0, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    /// The same, or nil when nothing was measured.
    public static func number(_ value: Double?, decimals: Int = 0, locale: Locale = .autoupdatingCurrent) -> String? {
        value.map { number($0, decimals: decimals, locale: locale) }
    }

    /// What VoiceOver says for a value that was not measured, where a view
    /// would draw ``SomaMissingValue``.
    public static var notMeasured: String { String(localized: "Not measured") }

    // MARK: Private

    private static func rounded(_ seconds: TimeInterval) -> Duration {
        .seconds(Int((max(0, seconds) / 60).rounded()) * 60)
    }

    private static func style(_ locale: Locale) -> Duration.UnitsFormatStyle {
        var style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .narrow)
        style.locale = locale
        return style
    }
}

/// A duration set large: each part's figures in `figures`, its unit after it
/// in `units` and the secondary ink, "7h 54m" with the 7 and the 54 big.
///
/// A nil duration draws ``SomaMissingValue`` in the figures' role with no unit
/// beside it.
public struct SomaDurationText: View {
    private let seconds: TimeInterval?
    private let figures: SomaFontSpec
    private let units: SomaFontSpec

    @Environment(\.somaTheme) private var theme
    @Environment(\.locale) private var locale

    public init(_ seconds: TimeInterval?, figures: SomaFontSpec, units: SomaFontSpec) {
        self.seconds = seconds
        self.figures = figures
        self.units = units
    }

    public var body: some View {
        if let seconds {
            let parts = SomaFormat.durationParts(seconds, locale: locale)
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.durationPartGap) {
                ForEach(parts, id: \.self) { part in
                    HStack(alignment: .firstTextBaseline, spacing: theme.metrics.durationUnitGap) {
                        Text(verbatim: part.value).somaFont(figures)
                        Text(verbatim: part.unit)
                            .somaFont(units)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: SomaFormat.duration(seconds, locale: locale)))
        } else {
            SomaMissingValue(figures)
        }
    }
}

#Preview("Durations") {
    let type = SomaTheme.standard.typography
    ZStack {
        SomaPreviewBackdrop()
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: SomaFormat.duration(28_440)).somaFont(type.body)
            SomaDurationText(28_440, figures: type.metricHero, units: type.metricHeroUnit)
            SomaDurationText(2_700, figures: type.metric, units: type.caption)
            SomaDurationText(nil, figures: type.metric, units: type.caption)
        }
    }
}
