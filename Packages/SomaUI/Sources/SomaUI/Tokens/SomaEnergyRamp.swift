//
//  SomaEnergyRamp.swift
//  SomaUI
//

import SwiftUI

/// The energy bank's colour, from empty to full: red at the floor, orange,
/// then amber through the middle and green at the top.
///
/// A data colour like ``SomaHealthHue``, never chrome: the battery's fill,
/// the day's curve and the history's bars read their level off this ramp, so
/// one glance at a hue says how full the bank is. Each stop is lifted a step
/// on the dark ground and deepened a step on the light one, so a thin line
/// still reads against either page.
public struct SomaEnergyRamp: Sendable, Equatable {
    /// One stop: where on the 0...1 scale it sits, and its colour there.
    public struct Stop: Sendable, Equatable {
        public let location: Double
        public let value: SomaColorValue

        public init(location: Double, value: SomaColorValue) {
            self.location = location
            self.value = value
        }
    }

    public let stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops.sorted { $0.location < $1.location }
    }

    /// Empty to full.
    public static let standard = SomaEnergyRamp(stops: [
        Stop(location: 0.00, value: SomaColorValue(light: 0xE0352B, dark: 0xFF4B3E)),
        Stop(location: 0.30, value: SomaColorValue(light: 0xEE6A1F, dark: 0xFF7A2E)),
        Stop(location: 0.55, value: SomaColorValue(light: 0xE0A100, dark: 0xFFC53D)),
        Stop(location: 0.80, value: SomaColorValue(light: 0x7DB52A, dark: 0xB4E04A)),
        Stop(location: 1.00, value: SomaColorValue(light: 0x24A148, dark: 0x4CD964)),
    ])

    /// Empty to full in calm, natural tones: clay at the floor, then sand,
    /// sage and a deep sage at the top. The energy bank reads its level off
    /// this one; the bright ramp above stays for the scales that need to
    /// warn.
    public static let calm = SomaEnergyRamp(stops: [
        Stop(location: 0.00, value: SomaColorValue(light: 0xC0694A, dark: 0xE08A6A)),
        Stop(location: 0.35, value: SomaColorValue(light: 0xC99448, dark: 0xE3B46C)),
        Stop(location: 0.65, value: SomaColorValue(light: 0x8C9F5C, dark: 0xADC27E)),
        Stop(location: 1.00, value: SomaColorValue(light: 0x4E957B, dark: 0x72BE9F)),
    ])

    /// The level as one of three plain tones, never a blend between them:
    /// clay under a third, sand to two thirds, sage above. A fill reads
    /// cleaner in a tone than in the olive a sand and a sage mix to.
    public static func tone(at share: Double) -> SomaColorValue {
        switch share {
        case ..<0.34: SomaColorValue(light: 0xC0694A, dark: 0xE08A6A)
        case ..<0.67: SomaColorValue(light: 0xCF9E5A, dark: 0xE3B46C)
        default: charge
        }
    }

    /// The bank filling: sleep and rest putting charge back.
    public static let charge = SomaColorValue(light: 0x4E957B, dark: 0x72BE9F)
    /// The bank emptying: the day drawing on it.
    public static let drain = SomaColorValue(light: 0xD3A673, dark: 0xC99A66)

    /// The colour at `share` of a full bank, `share` in 0...1, mixed between
    /// the two stops either side, in each appearance.
    public func value(at share: Double) -> SomaColorValue {
        let share = min(1, max(0, share))
        guard let first = stops.first, let last = stops.last else { return SomaColorValue(0) }
        if share <= first.location { return first.value }
        if share >= last.location { return last.value }
        let upper = stops.firstIndex { $0.location >= share } ?? stops.count - 1
        let a = stops[max(0, upper - 1)]
        let b = stops[upper]
        let span = b.location - a.location
        let t = span > 0 ? (share - a.location) / span : 0
        return SomaColorValue(light: Self.mix(a.value.light, b.value.light, t),
                              dark: Self.mix(a.value.dark, b.value.dark, t))
    }

    /// The ramp as gradient stops, for a fill or a stroke that runs from
    /// empty at one end to full at the other.
    public var gradientStops: [Gradient.Stop] {
        stops.map { Gradient.Stop(color: $0.value.color, location: $0.location) }
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF)
            let y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}
