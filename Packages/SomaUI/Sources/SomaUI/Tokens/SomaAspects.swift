//
//  SomaAspects.swift
//  SomaUI
//

import SwiftUI

/// The six parts of a person Soma reads, in the order the orb pages through
/// them: the whole body first, then head to toe, the way the website's hero
/// tours them.
public enum SomaAspect: String, CaseIterable, Identifiable, Sendable, Codable {
    case body
    case mind
    case sleep
    case heart
    case gut
    case activity

    public var id: String { rawValue }

    /// The aspect's name, as the site and every eyebrow print it.
    public var title: LocalizedStringResource {
        switch self {
        case .body: "Body"
        case .mind: "Mind"
        case .sleep: "Sleep"
        case .heart: "Heart"
        case .gut: "Gut"
        case .activity: "Activity"
        }
    }

    /// The aspect after this one, wrapping round, as a swipe to the left asks.
    public var next: SomaAspect {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The aspect before this one, wrapping round.
    public var previous: SomaAspect {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }
}

/// The website hero's Warp shader settings for one aspect, as
/// `components/ui/aspects.ts` in the landing page writes them.
///
/// The orb keeps these deep stops in both appearances: the site's pastel light
/// palette reads as porcelain on the cream ground, too faint to carry the move
/// written on it.
public struct SomaOrbPalette: Sendable, Equatable {
    /// Four stops: dark, light, dark, light.
    public var stops: [SomaColorValue]
    /// The rim light and the halo.
    public var accent: SomaColorValue
    public var proportion: Double
    public var softness: Double
    public var distortion: Double
    public var swirl: Double
    public var shapeScale: Double
    /// Degrees.
    public var rotation: Double
    /// How fast the weather flows, against the clock.
    public var speed: Double
    /// How close the camera sits: above 1 is closer.
    public var zoom: Double

    public init(
        stops: [SomaColorValue],
        accent: SomaColorValue,
        proportion: Double,
        softness: Double,
        distortion: Double,
        swirl: Double,
        shapeScale: Double,
        rotation: Double,
        speed: Double,
        zoom: Double
    ) {
        self.stops = stops
        self.accent = accent
        self.proportion = proportion
        self.softness = softness
        self.distortion = distortion
        self.swirl = swirl
        self.shapeScale = shapeScale
        self.rotation = rotation
        self.speed = speed
        self.zoom = zoom
    }
}

/// How one aspect is drawn wherever it appears.
public struct SomaAspectLook: Sendable, Equatable {
    /// The hue that names the aspect: an identity dot, a chart's marks. Text
    /// never wears it, and it never fills more than a mark.
    public var identity: SomaColorValue
    /// What its orb is painted with.
    public var orb: SomaOrbPalette

    public init(identity: SomaColorValue, orb: SomaOrbPalette) {
        self.identity = identity
        self.orb = orb
    }
}

/// The light every orb is shaded with, whatever its aspect.
public struct SomaOrbShading: Sendable, Equatable {
    /// How far the light from the top left darkens the far side.
    public var light: Double
    /// Strength of the accent along the rim.
    public var rim: Double
    /// How far the palette is pushed toward its dark stops, so the orb reads
    /// as a deep body with bright weather on it rather than a flat disc.
    public var depth: Double
    /// How many turns of weather the sphere holds.
    public var detail: Double
    /// Strength of the halo on the dark ground.
    public var haloDark: Double
    /// Strength of the halo on the cream ground, where it softens.
    public var haloLight: Double
    /// How quickly the halo fades past the rim.
    public var haloFalloff: Double
    /// How far the halo reaches, as a share of the orb's diameter on each side.
    public var haloReach: Double
    /// The shadow the orb sets down on the cream ground. The dark ground has none.
    public var contactShadowOpacity: Double
    /// The shadow under the move written on the orb, which keeps it legible over
    /// the brightest weather.
    public var labelShadowOpacity: Double

    public init(
        light: Double = 0.85,
        rim: Double = 0.22,
        depth: Double = 1.35,
        detail: Double = 2.0,
        // The halo and the rim were halved and more on 2026-10-03: the owner
        // found the orb too glowy. It reads as a solid sphere with a faint
        // edge light now, not a lamp.
        haloDark: Double = 0.12,
        haloLight: Double = 0.08,
        haloFalloff: Double = 14,
        haloReach: Double = 0.2,
        contactShadowOpacity: Double = 0.16,
        labelShadowOpacity: Double = 0.45
    ) {
        self.light = light
        self.rim = rim
        self.depth = depth
        self.detail = detail
        self.haloDark = haloDark
        self.haloLight = haloLight
        self.haloFalloff = haloFalloff
        self.haloReach = haloReach
        self.contactShadowOpacity = contactShadowOpacity
        self.labelShadowOpacity = labelShadowOpacity
    }
}

/// Every aspect's look, and the shading their orbs share.
public struct SomaAspects: Sendable, Equatable {
    public var body: SomaAspectLook
    public var mind: SomaAspectLook
    public var sleep: SomaAspectLook
    public var heart: SomaAspectLook
    public var gut: SomaAspectLook
    public var activity: SomaAspectLook
    public var shading: SomaOrbShading

    public init(
        body: SomaAspectLook,
        mind: SomaAspectLook,
        sleep: SomaAspectLook,
        heart: SomaAspectLook,
        gut: SomaAspectLook,
        activity: SomaAspectLook,
        shading: SomaOrbShading = SomaOrbShading()
    ) {
        self.body = body
        self.mind = mind
        self.sleep = sleep
        self.heart = heart
        self.gut = gut
        self.activity = activity
        self.shading = shading
    }

    public subscript(_ aspect: SomaAspect) -> SomaAspectLook {
        get {
            switch aspect {
            case .body: body
            case .mind: mind
            case .sleep: sleep
            case .heart: heart
            case .gut: gut
            case .activity: activity
            }
        }
        set {
            switch aspect {
            case .body: body = newValue
            case .mind: mind = newValue
            case .sleep: sleep = newValue
            case .heart: heart = newValue
            case .gut: gut = newValue
            case .activity: activity = newValue
            }
        }
    }
}

public extension SomaAspects {
    /// The identity hues are the chart gallery's `aspect/*` variables: the
    /// site's hues, stepped until the data palette validator passed on both
    /// grounds. The orb palettes are the site's shader settings, converted from
    /// its `hsl()` strings.
    static let standard = SomaAspects(
        body: SomaAspectLook(
            identity: SomaColorValue(light: 0x5E6672, dark: 0xAEB4BF),
            orb: SomaOrbPalette(
                stops: [SomaColorValue(0x1E1C1A), SomaColorValue(0xBAAC97),
                        SomaColorValue(0x393532), SomaColorValue(0xD8D0C0)],
                accent: SomaColorValue(0xDECDAF),
                proportion: 0.45, softness: 1, distortion: 0.25, swirl: 0.8,
                shapeScale: 0.1, rotation: 0, speed: 1, zoom: 0.85
            )
        ),
        mind: SomaAspectLook(
            identity: SomaColorValue(light: 0x1581A8, dark: 0x0CA7B4),
            orb: SomaOrbPalette(
                stops: [SomaColorValue(0x0A2638), SomaColorValue(0x63D7E3),
                        SomaColorValue(0x183662), SomaColorValue(0xA5E9DB)],
                accent: SomaColorValue(0x88E7F2),
                proportion: 0.46, softness: 1, distortion: 0.14, swirl: 0.6,
                shapeScale: 0.08, rotation: -20, speed: 0.38, zoom: 1.15
            )
        ),
        sleep: SomaAspectLook(
            identity: SomaColorValue(light: 0x7D60BC, dark: 0x9D7EE4),
            orb: SomaOrbPalette(
                stops: [SomaColorValue(0x0F0A2E), SomaColorValue(0xA78EEB),
                        SomaColorValue(0x111B5F), SomaColorValue(0xD6B6ED)],
                accent: SomaColorValue(0xBEA8FA),
                proportion: 0.5, softness: 1, distortion: 0.16, swirl: 0.55,
                shapeScale: 0.06, rotation: 20, speed: 0.28, zoom: 1.45
            )
        ),
        heart: SomaAspectLook(
            identity: SomaColorValue(light: 0xB74C5A, dark: 0xE06877),
            orb: SomaOrbPalette(
                stops: [SomaColorValue(0x49040D), SomaColorValue(0xFA3858),
                        SomaColorValue(0x760A2A), SomaColorValue(0xFF7A66)],
                accent: SomaColorValue(0xFF7083),
                proportion: 0.48, softness: 1, distortion: 0.3, swirl: 0.75,
                shapeScale: 0.09, rotation: 8, speed: 0.9, zoom: 1.2
            )
        ),
        gut: SomaAspectLook(
            identity: SomaColorValue(light: 0x5A8A1C, dark: 0x73A537),
            orb: SomaOrbPalette(
                stops: [SomaColorValue(0x082B1E), SomaColorValue(0x68B143),
                        SomaColorValue(0x104C44), SomaColorValue(0xABCF59)],
                accent: SomaColorValue(0xB3E87D),
                proportion: 0.5, softness: 1, distortion: 0.3, swirl: 0.95,
                shapeScale: 0.12, rotation: 35, speed: 0.7, zoom: 1.25
            )
        ),
        activity: SomaAspectLook(
            identity: SomaColorValue(light: 0x9B6906, dark: 0xC48609),
            orb: SomaOrbPalette(
                stops: [SomaColorValue(0x631903), SomaColorValue(0xFA9129),
                        SomaColorValue(0x92150C), SomaColorValue(0xFABF47)],
                accent: SomaColorValue(0xFFC266),
                proportion: 0.42, softness: 0.85, distortion: 0.36, swirl: 0.9,
                shapeScale: 0.15, rotation: -12, speed: 2.3, zoom: 1.05
            )
        )
    )
}
