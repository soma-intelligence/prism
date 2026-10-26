//
//  SomaDataScale.swift
//  SomaUI
//

import SwiftUI

/// A measure's colour along its own scale: the UV index from green to violet,
/// the air quality index from green to maroon, a temperature from blue to red.
///
/// A data colour like ``SomaHealthHue`` and ``SomaEnergyRamp``, never chrome.
/// Each stop sits at a value in the measure's own unit, so the published
/// bands (UV 3, 6, 8, 11; AQI 50, 100, 150, 200, 300) land where the
/// agencies draw them. Each stop is lifted a step on the dark ground and
/// deepened a step on the light one, so a thin bar still reads on either page.
public struct SomaDataScale: Sendable, Equatable {
    /// One stop: the value it sits at, and its colour there.
    public struct Stop: Sendable, Equatable {
        public let at: Double
        public let value: SomaColorValue

        public init(at: Double, value: SomaColorValue) {
            self.at = at
            self.value = value
        }
    }

    /// The span the scale draws, low end to high end.
    public let range: ClosedRange<Double>
    public let stops: [Stop]

    public init(range: ClosedRange<Double>, stops: [Stop]) {
        self.range = range
        self.stops = stops.sorted { $0.at < $1.at }
    }

    /// Where `measure` sits along the scale, 0 at the low end and 1 at the high.
    public func share(of measure: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (measure - range.lowerBound) / span))
    }

    /// The colour at `measure`, mixed between the stops either side.
    public func value(at measure: Double) -> SomaColorValue {
        guard let first = stops.first, let last = stops.last else { return SomaColorValue(0) }
        if measure <= first.at { return first.value }
        if measure >= last.at { return last.value }
        let upper = stops.firstIndex { $0.at >= measure } ?? stops.count - 1
        let a = stops[max(0, upper - 1)]
        let b = stops[upper]
        let gap = b.at - a.at
        let t = gap > 0 ? (measure - a.at) / gap : 0
        return SomaColorValue(light: Self.mix(a.value.light, b.value.light, t),
                              dark: Self.mix(a.value.dark, b.value.dark, t))
    }

    /// The scale as gradient stops from its low end to its high end.
    public var gradientStops: [Gradient.Stop] {
        stops.map { Gradient.Stop(color: $0.value.color, location: share(of: $0.at)) }
    }

    /// The scale as a gradient, for a bar or an arc.
    public var gradient: Gradient { Gradient(stops: gradientStops) }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF)
            let y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

private extension SomaColorValue {
    static let scaleGreen = SomaColorValue(light: 0x2E9E4A, dark: 0x4CD964)
    static let scaleYellow = SomaColorValue(light: 0xD9A600, dark: 0xFFD60A)
    static let scaleOrange = SomaColorValue(light: 0xE8711C, dark: 0xFF9F0A)
    static let scaleRed = SomaColorValue(light: 0xD93A2B, dark: 0xFF5345)
    static let scaleViolet = SomaColorValue(light: 0x8A3FD1, dark: 0xBF6BF5)
    static let scaleMaroon = SomaColorValue(light: 0x8C2A4E, dark: 0xD0577F)
    static let scaleBlue = SomaColorValue(light: 0x3866DB, dark: 0x5E86FF)
    static let scaleCyan = SomaColorValue(light: 0x1E9CC8, dark: 0x5AC8FA)
    static let scaleDusk = SomaColorValue(light: 0x5A55D6, dark: 0x8A86FF)
    static let scaleGold = SomaColorValue(light: 0xE0A100, dark: 0xFFCC33)
}

public extension SomaDataScale {
    /// The UV index, 0 to 11 and over, in the WHO's five bands.
    static let uvIndex = SomaDataScale(range: 0...11, stops: [
        Stop(at: 0, value: .scaleGreen),
        Stop(at: 2.5, value: .scaleGreen),
        Stop(at: 4, value: .scaleYellow),
        Stop(at: 6.5, value: .scaleOrange),
        Stop(at: 9, value: .scaleRed),
        Stop(at: 11, value: .scaleViolet),
    ])

    /// The US air quality index, 0 to 300, good to hazardous.
    static let airQuality = SomaDataScale(range: 0...300, stops: [
        Stop(at: 0, value: .scaleGreen),
        Stop(at: 40, value: .scaleGreen),
        Stop(at: 85, value: .scaleYellow),
        Stop(at: 135, value: .scaleOrange),
        Stop(at: 185, value: .scaleRed),
        Stop(at: 240, value: .scaleViolet),
        Stop(at: 300, value: .scaleMaroon),
    ])

    /// Air temperature in degrees Celsius, freezing blue to hot red.
    static let temperature = SomaDataScale(range: -10...40, stops: [
        Stop(at: -10, value: .scaleBlue),
        Stop(at: 4, value: .scaleCyan),
        Stop(at: 15, value: .scaleGreen),
        Stop(at: 23, value: .scaleYellow),
        Stop(at: 30, value: .scaleOrange),
        Stop(at: 40, value: .scaleRed),
    ])

    /// Minutes in daylight over a day, dusk to full sun.
    static let daylight = SomaDataScale(range: 0...120, stops: [
        Stop(at: 0, value: .scaleDusk),
        Stop(at: 30, value: .scaleOrange),
        Stop(at: 120, value: .scaleGold),
    ])

    /// A pollen count as its level, 0 for none to 4 for very high, the steps
    /// the National Allergy Bureau draws for each kind: green to red.
    static let pollen = SomaDataScale(range: 0...4, stops: [
        Stop(at: 0, value: .scaleGreen),
        Stop(at: 1, value: .scaleGreen),
        Stop(at: 2, value: .scaleYellow),
        Stop(at: 3, value: .scaleOrange),
        Stop(at: 4, value: .scaleRed),
    ])

    /// A sound level in dBA: quiet green, the 70 dB line amber, 80 and over red.
    static let soundLevel = SomaDataScale(range: 30...100, stops: [
        Stop(at: 30, value: .scaleGreen),
        Stop(at: 60, value: .scaleGreen),
        Stop(at: 72, value: .scaleYellow),
        Stop(at: 80, value: .scaleOrange),
        Stop(at: 90, value: .scaleRed),
        Stop(at: 100, value: .scaleRed),
    ])
}
