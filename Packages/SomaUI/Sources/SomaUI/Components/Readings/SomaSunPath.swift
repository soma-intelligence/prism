//
//  SomaSunPath.swift
//  SomaUI
//

import SwiftUI

/// The sun's day where you are, as one curve over the local day, midnight to
/// midnight: above the horizon it is the day's arc, warm and filled, below it
/// the night, a quiet dashed line. Sunrise and sunset sit on the horizon with
/// their times, the sun stands where it is now, and the line above says how
/// long the daylight lasts and what comes next.
///
/// Without times (no place yet) the curve keeps its shape, flat and grey,
/// with a dash where each number goes.
public struct SomaSunPath: View {
    private let rise: Date?
    private let set: Date?
    private let now: Date

    @Environment(\.somaTheme) private var theme
    @Environment(\.calendar) private var calendar

    /// - Parameters:
    ///   - rise: today's sunrise; nil when unknown.
    ///   - set: today's sunset; nil when unknown.
    ///   - now: the moment the sun is drawn at.
    public init(rise: Date?, set: Date?, now: Date) {
        self.rise = rise
        self.set = set
        self.now = now
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let day = SomaSunGeometry(rise: rise, set: set, dayStart: calendar.startOfDay(for: now))

        VStack(alignment: .leading, spacing: metrics.sunPathSpacing) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: day.map { SomaSunGeometry.duration($0.length) } ?? "-")
                        .somaFont(type.metricCompact)
                        .foregroundStyle(day == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                        .somaRollingNumber(day.map { SomaSunGeometry.duration($0.length) }, holdsWidth: true)
                    Text("of daylight")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Spacer(minLength: 0)
                if let day {
                    Text(day.next(at: now))
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }

            Canvas { context, size in
                draw(day, in: &context, size: size)
            }
            .frame(height: metrics.sunPathHeight)

            GeometryReader { proxy in
                let width = proxy.size.width
                if let day {
                    ForEach([day.sunrise, day.sunset], id: \.self) { moment in
                        Text(moment, format: .dateTime.hour().minute())
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize()
                            .position(x: min(max(width * day.x(moment), metrics.sunPathLabelInset),
                                             width - metrics.sunPathLabelInset),
                                      y: proxy.size.height / 2)
                    }
                } else {
                    HStack {
                        Text(verbatim: "-")
                        Spacer()
                        Text(verbatim: "-")
                    }
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.horizontal, width * 0.22)
                }
            }
            .frame(height: metrics.sunPathLabelHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sun"))
        .accessibilityValue(Text(day.map { accessibilityValue($0) } ?? "-"))
    }

    private func accessibilityValue(_ day: SomaSunGeometry) -> String {
        let rise = day.sunrise.formatted(.dateTime.hour().minute())
        let set = day.sunset.formatted(.dateTime.hour().minute())
        return String(localized: "Sunrise \(rise), sunset \(set), \(SomaSunGeometry.duration(day.length)) of daylight")
    }

    private func draw(_ day: SomaSunGeometry?, in context: inout GraphicsContext, size: CGSize) {
        let metrics = theme.metrics
        let colors = theme.colors
        let sun = metrics.environmentSunDiameter
        let top = sun / 2 + 3
        let horizon = size.height * metrics.sunPathHorizon
        let depth = size.height - horizon - 2
        let warm = SomaEnergyRamp.tone(at: 0.5).color
        let gold = SomaDataScale.daylight.value(at: 120).color.mix(with: warm, by: 0.35)
        let night = SomaHealthHue.sleep.color.mix(with: colors.inkSecondary.color, by: 0.5)
        let ink = colors.inkSecondary.color

        // The horizon.
        var line = Path()
        line.move(to: CGPoint(x: 0, y: horizon))
        line.addLine(to: CGPoint(x: size.width, y: horizon))
        context.stroke(line, with: .color(ink.opacity(0.4)), lineWidth: 0.75)

        let steps = 120
        func point(_ share: Double, _ day: SomaSunGeometry?) -> CGPoint {
            let height = day?.height(atShare: share) ?? -cos(2 * .pi * share) * 0.5
            let y = height >= 0 ? horizon - (horizon - top) * height : horizon - depth * height
            return CGPoint(x: size.width * share, y: y)
        }
        let all = (0...steps).map { point(Double($0) / Double(steps), day) }

        guard let day else {
            var path = Path()
            path.addLines(all)
            context.stroke(path, with: .color(ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [1.5, 4]))
            return
        }

        // The night, before sunrise and after sunset: dashed, below the line.
        let riseShare = day.x(day.sunrise)
        let setShare = day.x(day.sunset)
        for (from, to) in [(0.0, riseShare), (setShare, 1.0)] where to > from {
            var path = Path()
            path.addLines(stride(from: from, through: to, by: (to - from) / 40).map { point($0, day) })
            context.stroke(path, with: .color(night.opacity(0.55)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 4]))
        }

        // The day's arc: filled softly to the horizon, the stretch already
        // travelled drawn full, what is left of it lighter.
        let arc = stride(from: riseShare, through: setShare, by: (setShare - riseShare) / 80).map { point($0, day) }
        var area = Path()
        area.addLines(arc)
        area.addLine(to: CGPoint(x: size.width * setShare, y: horizon))
        area.addLine(to: CGPoint(x: size.width * riseShare, y: horizon))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(
            Gradient(colors: [gold.opacity(metrics.sunPathFillOpacity), gold.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: horizon)
        ))
        var whole = Path()
        whole.addLines(arc)
        context.stroke(whole, with: .color(gold.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        let nowShare = day.x(now)
        if nowShare > riseShare {
            let end = min(nowShare, setShare)
            var travelled = Path()
            travelled.addLines(stride(from: riseShare, through: end, by: max((end - riseShare) / 60, 0.0005)).map { point($0, day) })
            context.stroke(travelled, with: .color(gold), style: StrokeStyle(lineWidth: 2.25, lineCap: .round))
        }

        // Sunrise and sunset on the horizon.
        for share in [riseShare, setShare] {
            let at = CGPoint(x: size.width * share, y: horizon)
            let dot = metrics.sunPathTick
            context.fill(Path(ellipseIn: CGRect(x: at.x - dot / 2, y: at.y - dot / 2, width: dot, height: dot)), with: .color(gold))
        }

        // The sun now: lit with a soft halo above the horizon, a hollow disc
        // below it.
        let at = point(min(max(nowShare, 0), 1), day)
        let disc = CGRect(x: at.x - sun / 2, y: at.y - sun / 2, width: sun, height: sun)
        if day.isUp(at: now) {
            let halo = disc.insetBy(dx: -sun * 0.7, dy: -sun * 0.7)
            context.fill(Path(ellipseIn: halo), with: .radialGradient(
                Gradient(colors: [gold.opacity(0.4), gold.opacity(0)]),
                center: at, startRadius: 0, endRadius: halo.width / 2))
            context.fill(Path(ellipseIn: disc), with: .color(gold))
            context.stroke(Path(ellipseIn: disc), with: .color(colors.surface.color), lineWidth: 2)
        } else {
            context.fill(Path(ellipseIn: disc), with: .color(colors.surface.color))
            context.stroke(Path(ellipseIn: disc.insetBy(dx: 0.75, dy: 0.75)), with: .color(night), lineWidth: 1.5)
        }
    }
}

/// The sun's day as plain numbers: where a moment sits across the local day,
/// how high the sun stands at it, and the words for what comes next. Pure,
/// so it is tested without drawing.
public struct SomaSunGeometry: Equatable, Sendable {
    public let sunrise: Date
    public let sunset: Date
    public let dayStart: Date

    /// Nil unless both times are known and the sun sets after it rises.
    public init?(rise: Date?, set: Date?, dayStart: Date) {
        guard let rise, let set, set > rise else { return nil }
        self.sunrise = rise
        self.sunset = set
        self.dayStart = dayStart
    }

    static let dayLength: TimeInterval = 86_400

    /// How long the sun is up.
    public var length: TimeInterval { sunset.timeIntervalSince(sunrise) }

    /// A moment as a share of the local day, 0 at midnight, held inside it.
    public func x(_ moment: Date) -> Double {
        min(1, max(0, moment.timeIntervalSince(dayStart) / Self.dayLength))
    }

    public func isUp(at moment: Date) -> Bool { moment >= sunrise && moment < sunset }

    /// How high the sun stands at a share of the day: 1 at solar noon, 0 on
    /// the horizon at sunrise and sunset, down to -1 at solar midnight. A
    /// cosine through the day, scaled on each side of the horizon so the
    /// arc always fills its height.
    public func height(atShare share: Double) -> Double {
        let noon = x(sunrise) + (x(sunset) - x(sunrise)) / 2
        let half = (x(sunset) - x(sunrise)) / 2
        let angle = 2 * .pi * (share - noon)
        let edge = cos(2 * .pi * half)
        let raw = cos(angle) - edge
        return raw >= 0 ? raw / max(1 - edge, 0.0001) : raw / max(1 + edge, 0.0001)
    }

    /// What comes next, in a few words: "Sunset in 2h 10m".
    public func next(at moment: Date) -> LocalizedStringResource {
        if moment < sunrise { return "Sunrise in \(Self.duration(sunrise.timeIntervalSince(moment)))" }
        if moment < sunset { return "Sunset in \(Self.duration(sunset.timeIntervalSince(moment)))" }
        return "Sun set \(Self.duration(moment.timeIntervalSince(sunset))) ago"
    }

    /// A span as hours and minutes: "11h 6m", "45m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

#Preview("Sun path") {
    let start = Calendar.current.startOfDay(for: .now)
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaSunPath(rise: start.addingTimeInterval(7.3 * 3_600), set: start.addingTimeInterval(18.4 * 3_600),
                        now: start.addingTimeInterval(15.2 * 3_600))
            SomaSunPath(rise: start.addingTimeInterval(7.3 * 3_600), set: start.addingTimeInterval(18.4 * 3_600),
                        now: start.addingTimeInterval(21 * 3_600))
            SomaSunPath(rise: nil, set: nil, now: .now)
        }
        .padding()
    }
}
