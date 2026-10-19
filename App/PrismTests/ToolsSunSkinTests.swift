//
//  ToolsSunSkinTests.swift
//  PrismTests
//
//  Sun Budget, skin type, vitamin D and Skin Forecast engines (SolarElevation,
//  SolarTimes, SolarDayAxis, ErythemalDoseEngine, FitzpatrickAssessment and its
//  sections, VitaminDEngine, SkinForecastEngine, and the pure half of the Sun
//  Budget contribution), plus the pure pieces of the view layer.
//

import Testing
import Foundation
@testable import Prism

private func close(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func utc(_ year: Int, _ month: Int, _ day: Int,
                 _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day,
                                          hour: hour, minute: minute))!
}

// MARK: - Solar elevation

/// The NOAA algorithm can be checked without a reference table: its geometry
/// imposes facts a bug breaks at once. Tolerances are wide (the general NOAA
/// model is good to a few tenths of a degree) yet tight enough to catch an
/// inverted sign, a radian taken for a degree, or a time zone applied twice.
@Suite("Solar elevation")
struct ToolsSolarElevationTests {

    private func elevation(_ date: Date, lat: Double, lon: Double) -> Double {
        SomaTools.SolarElevation.elevationDegrees(date: date, latitude: lat, longitude: lon)
    }

    /// Greenwich at UTC noon is close to true solar noon: about
    /// 90 minus 51.5 plus 23.4 degrees at the June solstice.
    @Test func middayAtGreenwichOnTheJuneSolsticeIsNearTheGeometricMaximum() {
        let noon = elevation(utc(2025, 6, 21, 12), lat: 51.48, lon: 0)
        #expect(close(noon, 90 - 51.48 + 23.44, 1.0))
    }

    /// Same place and time six months later: the gap is twice the obliquity.
    @Test func theTwoSolsticesDifferByTwiceTheObliquity() {
        let june = elevation(utc(2025, 6, 21, 12), lat: 51.48, lon: 0)
        let december = elevation(utc(2025, 12, 21, 12), lat: 51.48, lon: 0)
        #expect(june > december)
        #expect(close(june - december, 2 * 23.44, 1.5))
    }

    /// Solar midnight is below the horizon. In Palo Alto it falls near 08:00
    /// UTC, which is the offset the longitude has to carry.
    @Test func midnightIsBelowTheHorizon() {
        #expect(elevation(utc(2025, 6, 21, 0), lat: 51.48, lon: 0) < 0)
        #expect(elevation(utc(2025, 3, 20, 8), lat: 37.44, lon: -122.14) < 0)
    }

    /// At the equinox the equator sees the sun almost overhead at solar noon.
    /// This catches an inverted declination sign; the tolerance covers the
    /// equation of time.
    @Test func theSunIsOverheadOnTheEquatorAtEquinoxNoon() {
        let noon = elevation(utc(2025, 3, 20, 12), lat: 0, lon: 0)
        #expect(close(noon, 90, 2.5))
    }

    /// Fifteen degrees west is one hour later: Palo Alto's solar noon falls
    /// near 20:00 UTC.
    @Test func longitudeShiftsSolarNoonByFourMinutesPerDegree() {
        let paloAlto = -122.14
        let atUTCNoon = elevation(utc(2025, 6, 21, 12), lat: 37.44, lon: paloAlto)
        let atLocalNoon = elevation(utc(2025, 6, 21, 20), lat: 37.44, lon: paloAlto)
        #expect(atLocalNoon > atUTCNoon)
        #expect(atLocalNoon > 70)
    }

    @Test func theHemispheresSeeOppositeSeasons() {
        let instant = utc(2025, 12, 21, 12)
        #expect(elevation(instant, lat: 51.48, lon: 0) < elevation(instant, lat: -51.48, lon: 0))
    }

    /// Midnight sun: at the north pole in June the elevation stays positive.
    @Test func thePolarDayNeverSetsInJune() {
        for hour in stride(from: 0, to: 24, by: 3) {
            #expect(elevation(utc(2025, 6, 21, hour), lat: 89.9, lon: 0) > 0,
                    "the sun set at \(hour):00 UTC at the pole in June")
        }
    }

    @Test func thePolarNightNeverRisesInDecember() {
        for hour in stride(from: 0, to: 24, by: 3) {
            #expect(elevation(utc(2025, 12, 21, hour), lat: 89.9, lon: 0) < 0,
                    "the sun rose at \(hour):00 UTC at the pole in December")
        }
    }

    @Test func theAngleStaysWithinItsDomain() {
        for latitude in stride(from: -90.0, through: 90.0, by: 15) {
            for hour in stride(from: 0, to: 24, by: 6) {
                let value = elevation(utc(2025, 9, 22, hour), lat: latitude, lon: 0)
                #expect(!value.isNaN, "NaN at \(latitude) degrees, \(hour):00")
                #expect(value >= -90 && value <= 90)
            }
        }
    }

    /// The function forces UTC: callers in Tokyo and Paris read the same angle.
    @Test func theCallersCalendarTimeZoneDoesNotChangeTheResult() {
        let instant = utc(2025, 6, 21, 12)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!

        let a = SomaTools.SolarElevation.elevationDegrees(date: instant, latitude: 48.85,
                                                          longitude: 2.35, calendar: tokyo)
        let b = SomaTools.SolarElevation.elevationDegrees(date: instant, latitude: 48.85,
                                                          longitude: 2.35, calendar: paris)
        #expect(close(a, b, 1e-9))
    }
}

// MARK: - Solar times and the solar day axis

@Suite("Solar times")
struct ToolsSolarTimesTests {

    @Test func equatorOnEquinoxDayLengthIsRoughlyTwelveHours() throws {
        let times = try #require(SomaTools.SolarTimes.sunriseSunset(
            date: utc(2021, 3, 20), latitude: 0, longitude: 0, calendar: utcCalendar))
        #expect(times.sunrise < times.sunset)
        #expect(close(times.sunset.timeIntervalSince(times.sunrise), 12 * 3600, 20 * 60))
    }

    @Test func highArcticWinterSolsticeReturnsNil() {
        #expect(SomaTools.SolarTimes.sunriseSunset(
            date: utc(2021, 12, 21), latitude: 80, longitude: 0, calendar: utcCalendar) == nil)
    }

    /// Tokyo, the case that forced the merge of two ports. The June 21
    /// sunrise is 04:25 JST, so 19:25 UTC the day before.
    @Test func tokyoSummerSolsticeSunriseIsThePreviousUTCDay() throws {
        let c = utcCalendar
        let times = try #require(SomaTools.SolarTimes.sunriseSunset(
            date: utc(2026, 6, 21), latitude: 35.6895, longitude: 139.6917, calendar: c))

        #expect(times.sunrise < times.sunset)
        #expect(c.component(.day, from: times.sunrise) == 20)
        #expect(c.component(.day, from: times.sunset) == 21)
        // 2026-06-20T19:25:28Z and 2026-06-21T10:00:11Z.
        #expect(close(times.sunrise.timeIntervalSince1970, 1_781_983_528.006, 0.05))
        #expect(close(times.sunset.timeIntervalSince1970, 1_782_036_011.308, 0.05))
    }
}

/// Checked here is where the axis REFUSES to answer: an axis that clamped to
/// 0 or 1 outside the day would place a sun on the horizon at midnight.
@Suite("Solar day axis")
struct ToolsSolarDayAxisTests {

    /// A reference day, 06:00 to 20:00, fourteen hours.
    private let sunrise = Date(timeIntervalSinceReferenceDate: 6 * 3600)
    private let sunset = Date(timeIntervalSinceReferenceDate: 20 * 3600)

    private func axis() -> SomaTools.SolarDayAxis {
        SomaTools.SolarDayAxis(sunrise: sunrise, sunset: sunset)!
    }

    @Test func missingBoundHasNoAxis() {
        #expect(SomaTools.SolarDayAxis(sunrise: nil, sunset: sunset) == nil)
        #expect(SomaTools.SolarDayAxis(sunrise: sunrise, sunset: nil) == nil)
        #expect(SomaTools.SolarDayAxis(sunrise: nil, sunset: nil) == nil)
    }

    @Test func nonPositiveSpanHasNoAxis() {
        #expect(SomaTools.SolarDayAxis(sunrise: sunset, sunset: sunrise) == nil)
        #expect(SomaTools.SolarDayAxis(sunrise: sunrise, sunset: sunrise) == nil)
    }

    @Test func beforeSunriseIsOutside() {
        #expect(axis().progress(at: sunrise.addingTimeInterval(-1)) == nil)
        #expect(axis().progress(at: sunrise.addingTimeInterval(-6 * 3600)) == nil)
    }

    @Test func afterSunsetIsOutside() {
        #expect(axis().progress(at: sunset.addingTimeInterval(1)) == nil)
        #expect(axis().progress(at: sunset.addingTimeInterval(4 * 3600)) == nil)
    }

    @Test func boundsAreInclusive() {
        #expect(close(axis().progress(at: sunrise) ?? -1, 0, 0.0001))
        #expect(close(axis().progress(at: sunset) ?? -1, 1, 0.0001))
    }

    @Test func middayIsHalfway() {
        #expect(close(axis().progress(at: sunrise.addingTimeInterval(7 * 3600)) ?? -1, 0.5, 0.0001))
    }

    @Test func progressIsAFractionOfTheRealDayLength() {
        let midMorning = sunrise.addingTimeInterval(4.5 * 3600)
        #expect(close(axis().progress(at: midMorning) ?? -1, 4.5 / 14, 0.0001))
    }

    @Test func shorterDayMovesFaster() throws {
        let winter = try #require(SomaTools.SolarDayAxis(sunrise: sunrise,
                                                         sunset: sunrise.addingTimeInterval(8 * 3600)))
        let twoHoursIn = sunrise.addingTimeInterval(2 * 3600)
        #expect(close(winter.progress(at: twoHoursIn) ?? -1, 0.25, 0.0001))
        #expect(close(axis().progress(at: twoHoursIn) ?? -1, 2.0 / 14, 0.0001))
    }

    @Test func progressIsMonotonic() throws {
        let axis = self.axis()
        var previous = -1.0
        for hour in stride(from: 0.0, through: 14.0, by: 0.5) {
            let value = try #require(axis.progress(at: sunrise.addingTimeInterval(hour * 3600)))
            #expect(value > previous, "progress went back at \(hour) h")
            previous = value
        }
    }
}

// MARK: - Erythemal dose

@Suite("Erythemal dose engine")
struct ToolsErythemalDoseTests {

    private typealias Engine = SomaTools.ErythemalDoseEngine

    @Test func oneUVIndexUnitIsTwentyFiveMilliwattsPerSquareMetre() {
        #expect(close(Engine.erythemalIrradianceWPerM2(uvIndex: 1), 0.025, 1e-9))
        #expect(close(Engine.erythemalIrradianceWPerM2(uvIndex: 8), 0.2, 1e-9))
    }

    @Test func negativeUVIsFlooredAtZero() {
        #expect(Engine.erythemalIrradianceWPerM2(uvIndex: -3) == 0)
    }

    @Test func theMinimalErythemalDoseRisesWithPhototype() {
        let doses = SomaTools.Fitzpatrick.allCases.map(Engine.medJPerM2)
        #expect(doses == doses.sorted())
        #expect(doses.first == 200)
        #expect(doses.last == 1000)
    }

    /// Type I under UV 8: 200 J/m2 over 0.2 W/m2 is 1000 s, about 16.7 min.
    @Test func burnTimeIsTheDoseDividedByTheRate() throws {
        let minutes = try #require(Engine.minutesToBurn(uvIndex: 8, fitzpatrick: .typeI))
        #expect(close(minutes, 1000.0 / 60.0, 0.001))
    }

    @Test func doublingTheUVHalvesTheTimeToBurn() throws {
        let low = try #require(Engine.minutesToBurn(uvIndex: 4, fitzpatrick: .typeIII))
        let high = try #require(Engine.minutesToBurn(uvIndex: 8, fitzpatrick: .typeIII))
        #expect(close(low / high, 2, 0.001))
    }

    @Test func spfMultipliesTheTolerableTime() throws {
        let bare = try #require(Engine.minutesToBurn(uvIndex: 6, fitzpatrick: .typeII))
        let protected = try #require(Engine.minutesToBurn(uvIndex: 6, fitzpatrick: .typeII, spf: 30))
        #expect(close(protected / bare, 30, 0.001))
    }

    @Test func anSPFBelowOneIsTreatedAsBareSkin() throws {
        let bare = try #require(Engine.minutesToBurn(uvIndex: 6, fitzpatrick: .typeII))
        let nonsense = try #require(Engine.minutesToBurn(uvIndex: 6, fitzpatrick: .typeII, spf: 0.2))
        #expect(close(nonsense, bare, 1e-9))
    }

    @Test func noUVMeansNoCountdown() {
        #expect(Engine.minutesToBurn(uvIndex: 0, fitzpatrick: .typeI) == nil)
        #expect(Engine.minutesToBurn(uvIndex: -1, fitzpatrick: .typeVI) == nil)
    }

    @Test func darkerSkinBurnsLaterAtTheSameUV() throws {
        let pale = try #require(Engine.minutesToBurn(uvIndex: 7, fitzpatrick: .typeI))
        let deep = try #require(Engine.minutesToBurn(uvIndex: 7, fitzpatrick: .typeVI))
        #expect(deep > pale)
        #expect(close(deep / pale, 1000.0 / 200.0, 0.001))
    }

    // Integration over the day

    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ hours: Double) -> Date {
        origin.addingTimeInterval(hours * 3600)
    }

    private func samples(_ points: [(hours: Double, uv: Double)]) -> [Engine.UVSample] {
        points.map { .init(date: at($0.hours), uv: $0.uv) }
    }

    /// Under a CONSTANT curve the integration must land exactly on the flat model.
    @Test func aConstantForecastReproducesTheFlatModel() throws {
        let flat = try #require(Engine.minutesToBurn(uvIndex: 8, fitzpatrick: .typeI))
        let instant = try #require(Engine.burnInstant(from: origin,
                                                      hourly: samples([(0, 8), (6, 8)]),
                                                      fitzpatrick: .typeI))
        #expect(close(instant.timeIntervalSince(origin) / 60, flat, 0.01))
    }

    /// The bug this engine fixes. Linear ramp 0 to 12 over six hours, start at
    /// hour 1 (UV 2), type III (MED 350): 90 * (T^2 minus 1) = 350 gives
    /// T = 2.211 h, 72.7 min after the start.
    @Test func aRisingForecastBurnsSoonerThanTheFrozenReading() throws {
        let flat = try #require(Engine.minutesToBurn(uvIndex: 2, fitzpatrick: .typeIII))
        let instant = try #require(Engine.burnInstant(from: at(1),
                                                      hourly: samples([(0, 0), (6, 12)]),
                                                      fitzpatrick: .typeIII))
        let minutes = instant.timeIntervalSince(at(1)) / 60
        #expect(close(minutes, 72.7, 0.5))
        #expect(minutes < flat)
    }

    @Test func sunBeforeTheStartIsNotCredited() throws {
        let day = samples([(0, 8), (12, 8)])
        let early = try #require(Engine.burnInstant(from: origin, hourly: day, fitzpatrick: .typeI))
        let late = try #require(Engine.burnInstant(from: at(3), hourly: day, fitzpatrick: .typeI))
        #expect(close(early.timeIntervalSince(origin), late.timeIntervalSince(at(3)), 0.01))
    }

    @Test func spfPushesTheInstantOutOnTheCurve() throws {
        let day = samples([(0, 8), (12, 8)])
        let bare = try #require(Engine.burnInstant(from: origin, hourly: day, fitzpatrick: .typeI))
        let protected = try #require(Engine.burnInstant(from: origin, hourly: day,
                                                        fitzpatrick: .typeI, spf: 15))
        #expect(close(protected.timeIntervalSince(origin) / bare.timeIntervalSince(origin), 15, 0.001))
    }

    /// The third case the flat model could not say: sun is left, but not
    /// enough to burn.
    @Test func nilWhenWhatIsLeftOfTheDayNeverReachesTheDose() {
        #expect(Engine.burnInstant(from: origin, hourly: samples([(0, 1), (2, 1)]),
                                   fitzpatrick: .typeVI) == nil)
    }

    @Test func nilWhenTheStartIsPastTheWholeForecast() {
        #expect(Engine.burnInstant(from: at(20), hourly: samples([(0, 9), (6, 9)]),
                                   fitzpatrick: .typeI) == nil)
    }

    @Test func aSingleSampleIsNotAForecast() {
        #expect(Engine.burnInstant(from: origin, hourly: samples([(0, 11)]),
                                   fitzpatrick: .typeI) == nil)
    }

    @Test func theForecastIsSortedBeforeIntegration() throws {
        let ordered = try #require(Engine.burnInstant(from: origin,
                                                      hourly: samples([(0, 2), (3, 6), (6, 10)]),
                                                      fitzpatrick: .typeII))
        let shuffled = try #require(Engine.burnInstant(from: origin,
                                                       hourly: samples([(6, 10), (0, 2), (3, 6)]),
                                                       fitzpatrick: .typeII))
        #expect(ordered == shuffled)
    }

    /// A falling afternoon: the quadratic's leading term is negative and the
    /// root kept must stay in the segment. 10 to 0 over six hours, type I:
    /// T = 0.2266 h, 13.6 min.
    @Test func aFallingForecastSolvesInsideItsSegment() throws {
        let instant = try #require(Engine.burnInstant(from: origin,
                                                      hourly: samples([(0, 10), (6, 0)]),
                                                      fitzpatrick: .typeI))
        #expect(close(instant.timeIntervalSince(origin) / 60, 13.6, 0.2))
    }
}

// MARK: - Fitzpatrick assessment

@Suite("Fitzpatrick assessment")
struct ToolsFitzpatrickAssessmentTests {

    private typealias Form = SomaTools.FitzpatrickAssessment

    @Test func tenItemsScoredZeroToFourGiveATotalOutOfForty() {
        #expect(Form.Item.allCases.count == 10)
        #expect(Form.optionPoints == [0, 1, 2, 3, 4])
        #expect(Form.maximumTotal == 40)
    }

    @Test func bandsTileTheScale() {
        let bands = Form.bands
        #expect(bands.count == 6)
        #expect(bands.first?.range.lowerBound == 0)
        #expect(bands.last?.range.upperBound == Form.maximumTotal)
        for (previous, next) in zip(bands, bands.dropFirst()) {
            #expect(next.range.lowerBound == previous.range.upperBound + 1,
                    "bands \(previous.range) and \(next.range) are not contiguous")
        }
        #expect(bands.map(\.type) == [.typeI, .typeII, .typeIII, .typeIV, .typeV, .typeVI])
    }

    @Test func bandBoundaries() {
        let expected: [(Int, SomaTools.Fitzpatrick)] = [
            (0, .typeI),   (6, .typeI),
            (7, .typeII),  (13, .typeII),
            (14, .typeIII), (20, .typeIII),
            (21, .typeIV), (27, .typeIV),
            (28, .typeV),  (34, .typeV),
            (35, .typeVI), (40, .typeVI)
        ]
        for (total, type) in expected {
            #expect(Form.type(forTotal: total) == type, "total \(total)")
        }
    }

    @Test func typeIsMonotonicInTheTotal() {
        let types = (0...Form.maximumTotal).map { Form.type(forTotal: $0).rawValue }
        #expect(types == types.sorted())
        #expect(types.first == SomaTools.Fitzpatrick.typeI.rawValue)
        #expect(types.last == SomaTools.Fitzpatrick.typeVI.rawValue)
    }

    @Test func outOfRangeTotalsClampInsteadOfFailing() {
        #expect(Form.type(forTotal: -12) == .typeI)
        #expect(Form.type(forTotal: 999) == .typeVI)
    }

    @Test func allLowestAnswersScoreTypeI() {
        let result = Form.result(answers: answers(all: 0))
        #expect(result?.total == 0)
        #expect(result?.type == .typeI)
    }

    @Test func allHighestAnswersScoreTypeVI() {
        let result = Form.result(answers: answers(all: 4))
        #expect(result?.total == 40)
        #expect(result?.type == .typeVI)
    }

    /// An unanswered item is not worth zero: zero is a VALID answer (lowest
    /// tolerance), so scoring an incomplete form would produce a credible,
    /// wrong type I.
    @Test func anIncompleteFormHasNoScore() {
        var partial = answers(all: 2)
        partial[.faceExposure] = nil
        #expect(Form.result(answers: partial) == nil)
    }

    @Test func anOutOfRangeAnswerIsRefused() {
        var tampered = answers(all: 2)
        tampered[.sunburn] = 9
        #expect(Form.result(answers: tampered) == nil)
    }

    @Test func distanceToTheNearestBandEdge() {
        #expect(scored(total: 14)?.pointsToNearestEdge == 0)
        #expect(scored(total: 20)?.pointsToNearestEdge == 0)
        #expect(scored(total: 17)?.pointsToNearestEdge == 3)
        #expect(scored(total: 17)?.isBorderline == false)
        #expect(scored(total: 15)?.isBorderline == true)
    }

    @Test func encodeThenDecodeRoundTrips() throws {
        let original = answers(all: 3)
        let encoded = try #require(Form.encode(answers: original))
        #expect(Form.decode(encoded) == original)
    }

    @Test func anIncompleteFormDoesNotEncode() {
        var partial = answers(all: 1)
        partial[.eyeColour] = nil
        #expect(Form.encode(answers: partial) == nil)
    }

    @Test func malformedStoredValuesDecodeToNil() {
        #expect(Form.decode("") == nil)
        #expect(Form.decode("1,2,3") == nil)
        #expect(Form.decode("0,1,2,3,4,0,1,2,3,x") == nil)
        #expect(Form.decode("0,1,2,3,4,0,1,2,3,7") == nil)
        #expect(Form.decode("0,1,2,3,4,0,1,2,3,4,4") == nil)
    }

    /// Every item carries its question and exactly one answer per point value,
    /// so the sheet can never show a blank row.
    @Test func everyItemHasAPromptAndFiveAnswers() {
        for item in Form.Item.allCases {
            #expect(!item.prompt.isEmpty)
            #expect(item.options.count == Form.optionPoints.count, "item \(item)")
            #expect(item.options.allSatisfy { !$0.isEmpty })
        }
        #expect(Form.Item.sunburn.option(points: 4) == "Never burns")
        #expect(Form.Item.sunburn.option(points: 9) == Form.Item.sunburn.options[0])
    }

    private func answers(all points: Int) -> [Form.Item: Int] {
        Dictionary(uniqueKeysWithValues: Form.Item.allCases.map { ($0, points) })
    }

    /// A complete form whose total is `total`, spread over the items.
    private func scored(total: Int) -> Form.Result? {
        var remaining = total
        var built: [Form.Item: Int] = [:]
        for item in Form.Item.allCases {
            let points = min(4, max(0, remaining))
            built[item] = points
            remaining -= points
        }
        let result = Form.result(answers: built)
        #expect(result?.total == total, "the fixture must reach \(total)")
        return result
    }
}

/// The sections only group the items for display, but the grouping IS the
/// published instrument: four genetic items, four about reaction to sun, two
/// about recent tanning.
@Suite("Fitzpatrick assessment sections")
struct ToolsFitzpatrickAssessmentSectionTests {

    private typealias Form = SomaTools.FitzpatrickAssessment

    @Test func eachItemBelongsToItsPublishedSection() {
        let expected: [Form.Item: Form.Section] = [
            .eyeColour: .geneticDisposition,
            .hairColour: .geneticDisposition,
            .skinColour: .geneticDisposition,
            .freckles: .geneticDisposition,
            .sunburn: .sunReaction,
            .tanDepth: .sunReaction,
            .tanSpeed: .sunReaction,
            .faceSensitivity: .sunReaction,
            .lastExposure: .tanningHabits,
            .faceExposure: .tanningHabits
        ]
        #expect(expected.count == Form.Item.allCases.count)
        for item in Form.Item.allCases {
            #expect(item.section == expected[item], "item \(item)")
        }
    }

    @Test func sectionsListTheirItemsInFormOrder() {
        #expect(Form.Section.geneticDisposition.items == [.eyeColour, .hairColour, .skinColour, .freckles])
        #expect(Form.Section.sunReaction.items == [.sunburn, .tanDepth, .tanSpeed, .faceSensitivity])
        #expect(Form.Section.tanningHabits.items == [.lastExposure, .faceExposure])
    }

    @Test func sectionsPartitionTheForm() {
        let listed = Form.Section.allCases.flatMap(\.items)
        #expect(listed == Form.Item.allCases)
        #expect(Set(listed).count == listed.count)
    }

    @Test func theIdentityIsTheStoredPosition() {
        #expect(Form.Item.allCases.map(\.id) == Array(0...9))
        #expect(Form.Item.faceExposure.id == 9)
    }
}

// MARK: - Vitamin D

@Suite("Vitamin D engine")
struct ToolsVitaminDTests {

    private typealias Engine = SomaTools.VitaminDEngine
    private let daytimeElevation = 60.0
    private let skin = 0.25

    @Test func noSynthesisAtNightRateIsZeroAndTimeToGoalIsNil() {
        #expect(Engine.synthesisRateIUPerMin(uvIndex: 0, solarElevationDeg: -10,
                                             fitzpatrick: .typeII, exposedSkinFraction: skin) == 0)
        #expect(Engine.timeToGoalMinutes(goalIU: 1000, uvIndex: 0, solarElevationDeg: -10,
                                         fitzpatrick: .typeII, exposedSkinFraction: skin) == nil)
    }

    @Test func higherUVProducesHigherRate() {
        let low = Engine.synthesisRateIUPerMin(uvIndex: 4, solarElevationDeg: daytimeElevation,
                                               fitzpatrick: .typeIII, exposedSkinFraction: skin)
        let high = Engine.synthesisRateIUPerMin(uvIndex: 8, solarElevationDeg: daytimeElevation,
                                                fitzpatrick: .typeIII, exposedSkinFraction: skin)
        #expect(high > low)
    }

    @Test func darkerSkinProducesLowerRate() {
        let fair = Engine.synthesisRateIUPerMin(uvIndex: 6, solarElevationDeg: daytimeElevation,
                                                fitzpatrick: .typeII, exposedSkinFraction: skin)
        let dark = Engine.synthesisRateIUPerMin(uvIndex: 6, solarElevationDeg: daytimeElevation,
                                                fitzpatrick: .typeVI, exposedSkinFraction: skin)
        #expect(fair > dark)
    }

    /// Anchor of the tuning: type II, UV 6, sun above the gate, 0.25 skin
    /// reaches about 1000 IU in roughly 15 minutes.
    @Test func calibrationTypeIIAboutOneThousandIUInFifteenMinutes() throws {
        let minutes = try #require(Engine.timeToGoalMinutes(goalIU: 1000, uvIndex: 6,
                                                            solarElevationDeg: daytimeElevation,
                                                            fitzpatrick: .typeII,
                                                            exposedSkinFraction: skin))
        #expect(close(minutes, 15, 2.0))
    }

    @Test func timeToGoalIsMonotonicInGoal() {
        func time(_ goal: Double) -> Double {
            Engine.timeToGoalMinutes(goalIU: goal, uvIndex: 6, solarElevationDeg: daytimeElevation,
                                     fitzpatrick: .typeIII, exposedSkinFraction: skin) ?? .nan
        }
        #expect(time(500) < time(1000))
        #expect(time(1000) < time(2000))
    }

    @Test func timeToGoalShrinksAsRateGrows() {
        let slow = Engine.timeToGoalMinutes(goalIU: 1000, uvIndex: 4, solarElevationDeg: daytimeElevation,
                                            fitzpatrick: .typeIII, exposedSkinFraction: skin) ?? .nan
        let fast = Engine.timeToGoalMinutes(goalIU: 1000, uvIndex: 9, solarElevationDeg: daytimeElevation,
                                            fitzpatrick: .typeIII, exposedSkinFraction: skin) ?? .nan
        #expect(fast < slow)
    }

    @Test func elevationGateOpensWithHighSunEvenAtLowUV() {
        #expect(Engine.synthesisRateIUPerMin(uvIndex: 2, solarElevationDeg: 55,
                                             fitzpatrick: .typeII, exposedSkinFraction: skin) > 0)
    }

    @Test func synthesisBundlesRateAndMinutesFromOneSetOfConditions() {
        let open = Engine.synthesis(uvIndex: 6, solarElevationDeg: daytimeElevation, fitzpatrick: .typeII)
        #expect(open.isPossible)
        #expect(close(open.rateIUPerMin, 67.5, 1e-9))
        let closed = Engine.synthesis(uvIndex: 1, solarElevationDeg: 20, fitzpatrick: .typeII)
        #expect(!closed.isPossible)
        #expect(closed.rateIUPerMin == 0)
    }
}

// MARK: - Skin forecast

/// The rule carrying this engine is normalization by the weights of the
/// present drivers only: a station without AQI must neither improve nor
/// degrade the index.
@Suite("Skin forecast engine")
struct ToolsSkinForecastTests {

    private typealias Engine = SomaTools.SkinForecastEngine
    private typealias Environment = SomaTools.SkinEnvironment

    @Test func eachDriverRampsFromItsComfortCeilingToItsHarshPoint() {
        #expect(Engine.uvPenalty(0) == 0)
        #expect(Engine.uvPenalty(3) == 0)
        #expect(close(Engine.uvPenalty(6.5), 0.5, 1e-9))
        #expect(Engine.uvPenalty(10) == 1)
        #expect(Engine.uvPenalty(14) == 1)

        #expect(Engine.aqiPenalty(50) == 0)
        #expect(close(Engine.aqiPenalty(125), 0.5, 1e-9))
        #expect(Engine.aqiPenalty(400) == 1)

        #expect(Engine.windPenalty(15) == 0)
        #expect(close(Engine.windPenalty(30), 0.5, 1e-9))
        #expect(Engine.windPenalty(80) == 1)
    }

    @Test func temperatureIsComfortableInsideItsBandAndPenalisedOnBothSides() {
        #expect(Engine.temperaturePenalty(16) == 0)
        #expect(Engine.temperaturePenalty(20) == 0)
        #expect(Engine.temperaturePenalty(24) == 0)
        #expect(Engine.temperaturePenalty(5) > 0)
        #expect(Engine.temperaturePenalty(30) > 0)
        #expect(Engine.temperaturePenalty(-5) == 1)
        #expect(Engine.temperaturePenalty(35) == 1)
        #expect(Engine.temperaturePenalty(-40) == 1)
    }

    /// 21 degrees on the cold side, 11 on the hot side.
    @Test func theColdAndHotSlopesAreAsymmetric() {
        let fiveBelowBand = Engine.temperaturePenalty(11)
        let fiveAboveBand = Engine.temperaturePenalty(29)
        #expect(close(fiveBelowBand, 5.0 / 21.0, 1e-9))
        #expect(close(fiveAboveBand, 5.0 / 11.0, 1e-9))
        #expect(fiveAboveBand > fiveBelowBand)
    }

    @Test func aComfortableDayScoresOneHundredWithNoLever() throws {
        let reading = try #require(Engine.reading(for: Environment(
            uvIndex: 2, aqi: 30, windKph: 8, temperatureC: 20)))
        #expect(reading.index == 100)
        #expect(close(reading.deficit, 0, 1e-9))
        #expect(reading.topLever == nil)
        #expect(reading.band == .calm)
    }

    @Test func aHarshDayScoresZero() throws {
        let reading = try #require(Engine.reading(for: Environment(
            uvIndex: 11, aqi: 300, windKph: 60, temperatureC: 40)))
        #expect(reading.index == 0)
        #expect(close(reading.deficit, 1, 1e-9))
        #expect(reading.band == .high)
    }

    @Test func aMissingDriverNeitherInflatesNorDeflatesTheIndex() throws {
        let withGoodAir = try #require(Engine.reading(for: Environment(
            uvIndex: 8, aqi: 20, windKph: 10, temperatureC: 20)))
        let withoutAir = try #require(Engine.reading(for: Environment(
            uvIndex: 8, windKph: 10, temperatureC: 20)))
        #expect(withGoodAir.deficit != withoutAir.deficit,
                "without AQI the total weight drops, so the same UV penalty weighs more")
        #expect(withGoodAir.index > withoutAir.index)

        // The normalization itself: one driver at mid ramp gives a deficit of
        // 0.5 whatever its weight.
        let uvOnly = try #require(Engine.reading(for: Environment(uvIndex: 6.5)))
        let windOnly = try #require(Engine.reading(for: Environment(windKph: 30)))
        #expect(close(uvOnly.deficit, 0.5, 1e-9))
        #expect(close(windOnly.deficit, 0.5, 1e-9))
        #expect(uvOnly.index == windOnly.index)
    }

    @Test func anEmptyEnvironmentYieldsNoReading() {
        #expect(Engine.reading(for: Environment()) == nil)
        #expect(Engine.reading(uvIndex: nil, aqi: nil, windKph: nil, temperatureC: nil,
                               humidityPercent: 60) == nil)
        #expect(Environment(humidityPercent: 60).hasNoScoredDriver)
    }

    @Test func nonFiniteValuesAreTreatedAsAbsent() throws {
        let reading = try #require(Engine.reading(for: Environment(
            uvIndex: .nan, aqi: 20, windKph: .infinity, temperatureC: 20)))
        #expect(!reading.deficit.isNaN)
        #expect(reading.index == 100)
    }

    /// The lever is the largest WEIGHTED penalty, not the largest raw one.
    @Test func theLeverIsTheLargestWeightedPenaltyNotTheLargestRawOne() throws {
        let windy = try #require(Engine.reading(for: Environment(uvIndex: 6.5, windKph: 45)))
        #expect(windy.topLever == .wind)
        let sunny = try #require(Engine.reading(for: Environment(uvIndex: 10, windKph: 45)))
        #expect(sunny.topLever == .uv)
    }

    @Test func aPenaltyBelowTheFloorProducesNoLever() throws {
        let barely = try #require(Engine.reading(for: Environment(uvIndex: 3.5)))
        #expect(Engine.uvPenalty(3.5) * Engine.weightUV < Engine.leverFloor)
        #expect(barely.topLever == nil)
        #expect(barely.index < 100)
    }

    @Test func bandThresholds() {
        #expect(SomaTools.SkinBand(index: 100) == .calm)
        #expect(SomaTools.SkinBand(index: 80) == .calm)
        #expect(SomaTools.SkinBand(index: 79) == .mild)
        #expect(SomaTools.SkinBand(index: 60) == .mild)
        #expect(SomaTools.SkinBand(index: 59) == .reactive)
        #expect(SomaTools.SkinBand(index: 40) == .reactive)
        #expect(SomaTools.SkinBand(index: 39) == .high)
        #expect(SomaTools.SkinBand(index: 0) == .high)
        #expect(SomaTools.SkinBand.calmThreshold == 80)
        for band in SomaTools.SkinBand.allCases {
            #expect(SomaTools.SkinBand(index: band.range.lowerBound) == band)
            #expect(SomaTools.SkinBand(index: band.range.upperBound) == band)
        }
    }

    @Test func theEnvironmentIsCarriedThroughUnchanged() throws {
        let environment = Environment(uvIndex: 7, aqi: 90, windKph: 22, temperatureC: 29,
                                      humidityPercent: 55)
        let reading = try #require(Engine.reading(for: environment))
        #expect(reading.environment == environment)
        #expect(reading.index == Int((100 * (1 - reading.deficit)).rounded()))
    }

    /// The rails come from the same ramps as the score, and a missing driver
    /// draws an empty rail, never a comfortable one.
    @Test func driverRowsReuseTheScoringRamps() throws {
        let reading = try #require(Engine.reading(for: Environment(uvIndex: 6.5, windKph: 45)))
        let rows = reading.drivers
        #expect(rows.map(\.feature) == SomaTools.SkinFeature.allCases)
        #expect(rows[0].penalty.map { close($0, 0.5, 1e-9) } == true)
        #expect(rows[1].penalty == nil)
        #expect(rows[1].value == nil)
        #expect(rows[2].isTopLever)
        #expect(rows.filter(\.isTopLever).count == 1)
        #expect(Engine.comfortZone(.temperature).comfort == 16...24)
    }
}

// MARK: - Sun Budget

@Suite("Sun Budget")
struct ToolsSunBudgetTests {

    private typealias Budget = SomaTools.SunBudget
    private let now = utc(2026, 6, 21, 12)

    @Test func horizonProgressIncreasesWithAvailableMargin() {
        let urgent = Budget.Reading(conditions: .init(uv: 10, solarElevationDeg: 60),
                                    fitzpatrick: .typeI, spf: .bare, now: now)
        let roomy = Budget.Reading(conditions: .init(uv: 2, solarElevationDeg: 25),
                                   fitzpatrick: .typeVI, spf: .bare, now: now)
        #expect(urgent.horizonProgress < roomy.horizonProgress)
        #expect((0...1).contains(urgent.horizonProgress))
        #expect((0...1).contains(roomy.horizonProgress))
    }

    @Test func horizonProgressIsFullWhenThereIsNoBurnRisk() {
        let night = Budget.Reading(conditions: .init(uv: 0, solarElevationDeg: -3),
                                   fitzpatrick: .typeII, spf: .bare, now: now)
        #expect(night.horizonProgress == 1)
        #expect(night.outcome == .noRiskNow)
    }

    /// Without a curve the outcome is the flat model; with one, the day can
    /// run out before the dose does.
    @Test func outcomeFollowsTheCurveWhenThereIsOne() {
        let flat = Budget.Reading(conditions: .init(uv: 8, solarElevationDeg: 60),
                                  fitzpatrick: .typeI, now: now)
        #expect(flat.outcome.minutes.map { close($0, 1000.0 / 60.0, 0.001) } == true)

        let dimDay = [SomaTools.ErythemalDoseEngine.UVSample(date: now, uv: 1),
                      .init(date: now.addingTimeInterval(2 * 3600), uv: 1)]
        let outlasts = Budget.Reading(conditions: .init(uv: 1, solarElevationDeg: 30, hourly: dimDay),
                                      fitzpatrick: .typeVI, now: now)
        #expect(outlasts.outcome == .outlastsDay)
        #expect(outlasts.selectedBand == .noRisk)
    }

    @Test func spfWhatIfIsMonotonicAndGainIsTheDifference() throws {
        let conditions = Budget.Conditions(uv: 6, solarElevationDeg: 60)
        let rows = Budget.whatIf(conditions: conditions, fitzpatrick: .typeII, now: now)
        let minutes = rows.compactMap { $0.outcome.minutes }
        #expect(rows.map { $0.spf } == Budget.SPF.allCases)
        #expect(minutes == minutes.sorted())

        let spf30 = Budget.Reading(conditions: conditions, fitzpatrick: .typeII, spf: .spf30, now: now)
        let gain = try #require(spf30.spfGainMinutes)
        let bare = try #require(spf30.bareOutcome.minutes)
        #expect(close(gain, bare * 29, 1e-6))
        #expect(Budget.Reading(conditions: conditions, fitzpatrick: .typeII, now: now).spfGainMinutes == nil)
    }

    @Test func bandCutsAtTwentyAndFortyFiveMinutes() {
        #expect(Budget.Band(bareMinutes: nil) == .noRisk)
        #expect(Budget.Band(bareMinutes: 19.9) == .high)
        #expect(Budget.Band(bareMinutes: 20) == .moderate)
        #expect(Budget.Band(bareMinutes: 44.9) == .moderate)
        #expect(Budget.Band(bareMinutes: 45) == .low)
        #expect(Budget.Reading.horizonMarks == [20.0 / 90.0, 45.0 / 90.0])
    }

    @Test func durationBreaksToHoursAtNinetyMinutes() {
        #expect(Budget.duration(17.4) == .init(value: "17", unit: .minutes))
        #expect(Budget.duration(89.4) == .init(value: "89", unit: .minutes))
        #expect(Budget.duration(138) == .init(value: "2.3", unit: .hours))
    }

    /// A peak only source still gets a day curve: zero at night, the peak at
    /// the sun's highest sample, and a burn instant walked along it.
    @Test func aPeakUVBuildsADayCurveShapedByTheSun() throws {
        let curve = Budget.estimatedHourlyUV(peakUV: 9, latitude: 37.44, longitude: -122.14,
                                             day: utc(2026, 6, 21, 0), calendar: utcCalendar)
        #expect(curve.count == 25)
        let peak = try #require(curve.max { $0.uv < $1.uv })
        #expect(close(peak.uv, 9, 1e-9))
        // Palo Alto solar noon is near 20:00 UTC.
        #expect(abs(peak.date.timeIntervalSince(utc(2026, 6, 21, 20))) <= 3600)
        // 08:00 UTC is local midnight: no UV.
        #expect(curve.first { $0.date == utc(2026, 6, 21, 8) }?.uv == 0)

        #expect(Budget.estimatedHourlyUV(peakUV: 9, latitude: 89.9, longitude: 0,
                                         day: utc(2025, 12, 21), calendar: utcCalendar).isEmpty)
        #expect(Budget.estimatedHourlyUV(peakUV: 0, latitude: 37.44, longitude: -122.14,
                                         day: utc(2026, 6, 21), calendar: utcCalendar).isEmpty)
    }

    @Test func conditionsFromPlainNumbers() throws {
        let at = utc(2026, 6, 21, 18)
        let conditions = try #require(Budget.conditions(uvIndex: nil, latitude: 37.44,
                                                        longitude: -122.14, date: at,
                                                        peakUV: 9, calendar: utcCalendar))
        #expect(conditions.uv > 0 && conditions.uv < 9)
        #expect(conditions.solarElevationDeg > 45)
        #expect(conditions.hourly.count > 1)
        #expect(conditions.solarDay != nil)

        let reading = Budget.Reading(conditions: conditions, fitzpatrick: .typeII, now: at)
        #expect(reading.minutesToBurnAtPeak.map { close($0, 250 / (9 * 0.025) / 60, 1e-6) } == true)

        // No UV information at all is the page's empty state.
        #expect(Budget.conditions(uvIndex: nil, latitude: 37.44, longitude: -122.14,
                                  date: at, calendar: utcCalendar) == nil)
    }

    @Test func chartMarkersPlaceNowAndTheBurnOnTheWindow() throws {
        let hourly = (0...12).map {
            SomaTools.ErythemalDoseEngine.UVSample(date: utc(2026, 6, 21, 6 + $0), uv: $0 == 0 || $0 == 12 ? 0 : 8)
        }
        let reading = Budget.Reading(conditions: .init(uv: 8, solarElevationDeg: 60, hourly: hourly),
                                     fitzpatrick: .typeI, now: utc(2026, 6, 21, 12))
        let window = try #require(Budget.chartWindow(for: reading, calendar: utcCalendar))
        #expect(window.startHour == 6 && window.endHour == 18)
        let markers = Budget.chartMarkers(for: reading, startHour: window.startHour,
                                          endHour: window.endHour, calendar: utcCalendar)
        #expect(markers.now.map { close($0, 0.5, 1e-9) } == true)
        #expect((markers.burn ?? 0) > 0.5)
    }
}
