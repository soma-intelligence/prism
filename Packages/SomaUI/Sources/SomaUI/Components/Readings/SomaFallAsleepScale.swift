//
//  SomaFallAsleepScale.swift
//  SomaUI
//

import SwiftUI

/// How quickly sleep came, read as the earlier app read it: fifteen minutes
/// or less is fast, twenty five or less average, longer late, and the scale
/// is full at half an hour.
public enum SomaFallAsleepBand: Int, CaseIterable, Sendable {
    case fast, average, late

    public var title: LocalizedStringResource {
        switch self {
        case .fast: "Fast"
        case .average: "Average"
        case .late: "Late"
        }
    }

    /// The minutes each band reaches, the last one up to the end of the scale.
    nonisolated static let upperMinutes: [SomaFallAsleepBand: Double] = [.fast: 15, .average: 25, .late: 30]

    /// The minutes the scale spans.
    nonisolated static let fullMinutes: Double = 30

    /// The band for a latency of `minutes`, whole minutes as the card prints
    /// them.
    public nonisolated static func band(minutes: Int) -> SomaFallAsleepBand {
        switch minutes {
        case ...15: .fast
        case ...25: .average
        default: .late
        }
    }

    /// Whole minutes for a latency, never under one: a night that fell asleep
    /// in twenty seconds still reads as a minute, never as zero.
    public nonisolated static func minutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((max(0, seconds) / 60).rounded()))
    }

    /// Where a latency sits along the scale, 0 to 1: full at half an hour,
    /// and a little in from the start so a very fast night still shows its
    /// marker on the track.
    public nonisolated static func position(_ seconds: TimeInterval) -> Double {
        min(1, max(0.05, seconds / (fullMinutes * 60)))
    }

    /// Each band's share of the track, in order: the minutes it covers over
    /// the scale's half hour.
    nonisolated static var shares: [Double] {
        var lower = 0.0
        return allCases.map { band in
            let upper = upperMinutes[band] ?? fullMinutes
            defer { lower = upper }
            return (upper - lower) / fullMinutes
        }
    }
}

/// The time it took to fall asleep: the band in a word, what it counts, the
/// minutes set large, and a track cut into the three bands with a marker
/// where the night fell. The band the night fell in carries the sleep colour;
/// the others stay neutral.
///
/// With no latency (bed not recorded, or the night began asleep) it draws a
/// dash and an empty track; a page that has none should leave it out.
public struct SomaFallAsleepScale: View {
    private let latency: TimeInterval?

    @Environment(\.somaTheme) private var theme

    /// - Parameter latency: seconds awake in bed before the first stage of
    ///   sleep, or nil when the night did not record it.
    public init(latency: TimeInterval?) {
        self.latency = latency
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let minutes = latency.map(SomaFallAsleepBand.minutes)
        let band = minutes.map(SomaFallAsleepBand.band(minutes:))

        VStack(alignment: .leading, spacing: metrics.cardPadding) {
            HStack(alignment: .center, spacing: metrics.spaceS) {
                VStack(alignment: .leading, spacing: metrics.spaceXS) {
                    if let band {
                        Text(band.title)
                            .somaFont(type.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                    } else {
                        SomaMissingValue(type.cardTitle)
                    }
                    Text("Awake in bed before falling asleep")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: metrics.spaceS)
                SomaNumber(minutes.map { "\($0)" }, type.metric, unit: "min", unitSpec: type.callout)
                    .foregroundStyle(colors.inkPrimary.color)
            }
            .accessibilityElement(children: .combine)

            track(band: band, position: latency.map(SomaFallAsleepBand.position))
                .accessibilityHidden(true)
        }
    }

    private func track(band: SomaFallAsleepBand?, position: Double?) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.sleep].identity.color
        let shares = SomaFallAsleepBand.shares
        let gap = metrics.sleepStageBarGap

        return VStack(spacing: metrics.spaceS) {
            GeometryReader { proxy in
                let room = max(0, proxy.size.width - gap * CGFloat(shares.count - 1))
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(SomaFallAsleepBand.allCases, id: \.self) { each in
                            Capsule()
                                .fill(each == band ? hue.opacity(metrics.fallAsleepBandOpacity) : colors.surfaceRecessed.color)
                                .frame(width: room * shares[each.rawValue], height: metrics.fallAsleepTrackHeight)
                        }
                    }
                    if let position {
                        Circle()
                            .fill(hue)
                            .overlay { Circle().strokeBorder(colors.surface.color, lineWidth: metrics.fallAsleepMarkerRing) }
                            .frame(width: metrics.fallAsleepMarker, height: metrics.fallAsleepMarker)
                            .offset(x: (proxy.size.width - metrics.fallAsleepMarker) * position)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: metrics.fallAsleepMarker)

            GeometryReader { proxy in
                let room = max(0, proxy.size.width - gap * CGFloat(shares.count - 1))
                HStack(spacing: gap) {
                    ForEach(SomaFallAsleepBand.allCases, id: \.self) { each in
                        Text(each.title)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(each == band ? colors.inkPrimary.color : colors.inkSecondary.color)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: room * shares[each.rawValue], alignment: .leading)
                    }
                }
            }
            .frame(height: theme.metrics.sleepStageShareHeight)
        }
    }
}

#Preview("Fall asleep scale") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: SomaMetrics.standard.cardSpacing) {
            SomaCard { SomaFallAsleepScale(latency: 9 * 60) }
            SomaCard { SomaFallAsleepScale(latency: 22 * 60) }
            SomaCard { SomaFallAsleepScale(latency: 41 * 60) }
            SomaCard { SomaFallAsleepScale(latency: nil) }
        }
        .padding()
    }
}
