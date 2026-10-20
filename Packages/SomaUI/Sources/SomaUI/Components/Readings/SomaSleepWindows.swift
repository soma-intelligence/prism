//
//  SomaSleepWindows.swift
//  SomaUI
//

import SwiftUI

/// One night's window, from bed to waking, as clock hours (22.5 is half past
/// ten at night, 6.25 a quarter past six in the morning).
public struct SomaSleepWindow: Identifiable, Equatable, Sendable {
    public var id: Int
    /// The label under the night's column, such as the weekday's letter.
    public var label: String?
    public var bed: Double?
    public var wake: Double?

    public init(id: Int, label: String? = nil, bed: Double?, wake: Double?) {
        self.id = id
        self.label = label
        self.bed = bed
        self.wake = wake
    }
}

/// How regular the nights were: each night a soft column from bedtime down to
/// waking on one clock, evening at the top and morning at the foot, over a
/// quiet band where the person's usual window sits. Columns that line up are
/// a steady rhythm at a glance; a late night sticks out without a word.
///
/// The columns grow down from bedtime once when the card arrives; under
/// Reduce Motion they are drawn at once. A night with nothing recorded keeps
/// its place and draws nothing.
public struct SomaSleepWindows: View {
    private let nights: [SomaSleepWindow]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    public init(_ nights: [SomaSleepWindow]) {
        self.nights = nights
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.sleep].identity.color
        let scale = SomaSleepWindowScale(nights)
        let usual = scale.usual
        let shown = isDrawn || reduceMotion

        VStack(spacing: metrics.metricHeroSpacing) {
            HStack(alignment: .top, spacing: metrics.metricHeroSpacing * 2) {
                GeometryReader { proxy in
                    let height = proxy.size.height
                    let slot = proxy.size.width / CGFloat(max(1, nights.count))
                    let width = min(metrics.metricChartBarMaxWidth, slot * metrics.metricChartBarShare)
                    ZStack(alignment: .topLeading) {
                        if let usual {
                            Rectangle()
                                .fill(colors.inkPrimary.color.opacity(metrics.metricChartBandOpacity))
                                .frame(height: max(1, height * (scale.y(pastNoon: usual.wake) - scale.y(pastNoon: usual.bed))))
                                .offset(y: height * scale.y(pastNoon: usual.bed))
                        }
                        ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
                            if let bed = night.bed, let wake = night.wake {
                                let top = scale.y(clock: bed)
                                let length = max(0.02, scale.y(clock: wake) - top)
                                Capsule()
                                    .fill(hue.opacity(index == nights.count - 1 ? 1 : metrics.metricChartContextOpacity))
                                    .frame(width: width, height: height * length * (shown ? 1 : 0.02))
                                    .offset(x: slot * CGFloat(index) + (slot - width) / 2, y: height * top)
                            }
                        }
                    }
                }
                .frame(height: metrics.sleepWindowsHeight)

                VStack(alignment: .trailing) {
                    Text(SomaSleepWindowScale.clock(scale.top))
                    Spacer()
                    Text(SomaSleepWindowScale.clock(scale.bottom))
                }
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(width: metrics.metricChartGutter, height: metrics.sleepWindowsHeight, alignment: .trailing)
            }

            HStack(spacing: 0) {
                ForEach(nights) { night in
                    Text(night.label ?? "")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: metrics.metricChartGutter + metrics.metricHeroSpacing * 2, height: 1)
            }
        }
        .onAppear {
            guard !isDrawn else { return }
            if reduceMotion { isDrawn = true } else { withAnimation(theme.motion.chartDraw) { isDrawn = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bedtimes and wake times"))
        .accessibilityValue(Text(scale.summary))
    }
}

/// The clock the windows are drawn on, from an hour before the earliest
/// bedtime to an hour after the latest waking, kept apart so it is tested.
struct SomaSleepWindowScale: Equatable {
    /// Hours past noon at the top and at the foot.
    let top: Double
    let bottom: Double
    /// The middle bedtime and the middle waking, past noon.
    let usual: (bed: Double, wake: Double)?

    static func == (a: Self, b: Self) -> Bool {
        a.top == b.top && a.bottom == b.bottom && a.usual?.bed == b.usual?.bed && a.usual?.wake == b.usual?.wake
    }

    init(_ nights: [SomaSleepWindow]) {
        let beds = nights.compactMap { $0.bed.map(Self.pastNoon) }
        let wakes = nights.compactMap { $0.wake.map(Self.pastNoon) }
        let earliest = (beds.min() ?? 10).rounded(.down) - 1
        let latest = (wakes.max() ?? 19).rounded(.up) + 1
        top = max(4, earliest)
        bottom = min(24, max(top + 4, latest))
        if beds.count >= 3, wakes.count >= 3 {
            usual = (Self.median(beds), Self.median(wakes))
        } else {
            usual = nil
        }
    }

    /// A clock hour as hours past noon, so a night reads in one run: 22:00
    /// is 10, 02:00 is 14, 06:00 is 18.
    static func pastNoon(_ hour: Double) -> Double {
        let h = hour.truncatingRemainder(dividingBy: 24)
        return h >= 12 ? h - 12 : h + 12
    }

    /// Where a clock hour sits, 0 at the top and 1 at the foot.
    func y(clock hour: Double) -> Double {
        y(pastNoon: Self.pastNoon(hour))
    }

    /// Where an hour past noon sits, 0 at the top and 1 at the foot.
    func y(pastNoon value: Double) -> Double {
        min(1, max(0, (value - top) / max(0.001, bottom - top)))
    }

    /// Hours past noon written as a clock, "22:00".
    static func clock(_ pastNoon: Double) -> String {
        let hour = (Int(pastNoon.rounded()) + 12) % 24
        return String(format: "%02d:00", hour)
    }

    var summary: String {
        guard let usual else { return "Too few nights" }
        return "Usually \(Self.clock(usual.bed)) to \(Self.clock(usual.wake))"
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

#Preview("Sleep windows") {
    let letters = ["M", "T", "W", "T", "F", "S", "S", "M", "T", "W", "T", "F", "S", "S"]
    let beds: [Double?] = [22.6, 23.1, 22.8, nil, 23.4, 0.6, 23.9, 22.7, 22.9, 23.0, 22.5, 23.6, 0.2, 22.8]
    let wakes: [Double?] = [6.3, 6.5, 6.4, nil, 6.6, 8.4, 7.9, 6.2, 6.4, 6.5, 6.3, 7.0, 8.6, 6.2]
    return SomaCard {
        SomaSleepWindows(letters.indices.map { SomaSleepWindow(id: $0, label: letters[$0], bed: beds[$0], wake: wakes[$0]) })
    }
    .padding()
}
