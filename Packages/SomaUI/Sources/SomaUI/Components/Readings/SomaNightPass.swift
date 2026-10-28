//
//  SomaNightPass.swift
//  SomaUI
//

import SwiftUI

/// Last night as Flighty draws a flight: bed on the leading edge and waking on
/// the trailing one, like a departure and an arrival, and between them a track
/// that stands for the same stretch of clock every night, so a short night
/// reads short. The hours asleep are filled in on it, a mark shows where a
/// usual night would have ended, and the totals sit under it.
///
/// Every value arrives as words the app already formatted; a missing one reads
/// as a dash, and with no span the track stays empty rather than inventing one.
public struct SomaNightPass: View {
    private let bed: String?
    private let woke: String?
    private let asleep: String?
    private let usual: String?
    private let span: ClosedRange<Double>?
    private let usualSpan: ClosedRange<Double>?
    private let midnight: Double?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until the pass first appears, so the span fills from bed onward.
    @State private var hasAppeared = false

    /// - Parameters:
    ///   - bed: The clock time the night began.
    ///   - woke: The clock time it ended.
    ///   - asleep: Time actually asleep, as the app prints a duration.
    ///   - usual: A few words against the person's usual ("Usual 7:20").
    ///   - span: Where sleep began and ended on the track, from 0 to 1 of the
    ///     window the app chose. Nil leaves the track empty.
    ///   - usualSpan: The usual night on the same track; its end is marked.
    ///   - midnight: Where midnight falls on the track, marked faintly so the
    ///     fixed scale shows.
    public init(
        bed: String?, woke: String?, asleep: String?, usual: String? = nil,
        span: ClosedRange<Double>?, usualSpan: ClosedRange<Double>? = nil, midnight: Double? = nil
    ) {
        self.bed = bed
        self.woke = woke
        self.asleep = asleep
        self.usual = usual
        self.span = span.map(Self.clamped)
        self.usualSpan = usualSpan.map(Self.clamped)
        self.midnight = midnight.map { min(1, max(0, $0)) }
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.nightPassSpacing) {
            HStack(alignment: .firstTextBaseline) {
                end("Bed", bed, alignment: .leading)
                Spacer(minLength: metrics.nightPassSpacing)
                end("Woke", woke, alignment: .trailing)
            }

            SomaNightTrack(span: span, usualSpan: usualSpan, midnight: midnight, shown: hasAppeared || reduceMotion)

            HStack(alignment: .firstTextBaseline, spacing: metrics.identityDotSpacing) {
                SomaNumber(asleep, type.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
                if asleep != nil {
                    Text("asleep")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Spacer(minLength: metrics.nightPassSpacing)
                if let usual {
                    Text(verbatim: usual)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: theme.motion.pressDuration * 6)) { hasAppeared = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last night"))
        .accessibilityValue(accessibilityValue)
    }

    private func end(_ title: LocalizedStringResource, _ time: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: theme.metrics.cardHeaderSpacing) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            SomaNumber(time, theme.typography.metricCompact)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private static func clamped(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = min(1, max(0, range.lowerBound))
        return lower...max(lower, min(1, range.upperBound))
    }

    private var accessibilityValue: Text {
        let missing = SomaFormat.notMeasured
        let span = "\(bed ?? missing) to \(woke ?? missing)"
        guard let asleep else { return Text(verbatim: span) }
        return Text("\(span), \(asleep) asleep")
    }
}

/// The track: a faint capsule with midnight marked on it, the asleep span
/// filled in the sleep hue with a dot where sleep began, the moon at the
/// waking end, and a mark where a usual night would have ended.
private struct SomaNightTrack: View {
    let span: ClosedRange<Double>?
    let usualSpan: ClosedRange<Double>?
    let midnight: Double?
    /// False before the first appearance: the span is drawn from its start
    /// with no length yet.
    let shown: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[.sleep].identity.color
        let height = metrics.nightPassTrackHeight
        let object = metrics.objectInline
        let dot = metrics.nightPassEndDot

        GeometryReader { proxy in
            let width = proxy.size.width
            let from = (span?.lowerBound ?? 0) * width
            let to = span.map { (shown ? $0.upperBound : $0.lowerBound) * width } ?? from

            ZStack(alignment: .leading) {
                // Ink at a low opacity rather than the recessed surface, which
                // all but vanishes on a dark card.
                Capsule()
                    .fill(theme.colors.inkPrimary.color.opacity(metrics.nightPassTrackOpacity))
                    .frame(height: height)
                if let midnight {
                    tick(at: midnight * width, width: width)
                }
                if span != nil {
                    Capsule()
                        .fill(hue)
                        .frame(width: max(0, to - from), height: height)
                        .offset(x: from)
                    // The dot sits on the span's leading end, so the two read
                    // as one object.
                    Circle()
                        .fill(hue)
                        .frame(width: dot, height: dot)
                        .offset(x: max(0, min(width - dot, from - dot / 2)))
                    SomaObjectIcon(SomaObject.sleep)
                        .offset(x: max(0, min(width - object, to - object / 2)))
                }
                // Where a usual night would have ended: a mark across the
                // track, so it shows whether the night ran short or long.
                if let usualSpan, span != nil {
                    tick(at: usualSpan.upperBound * width, width: width, tall: true)
                }
            }
            .frame(height: object)
        }
        .frame(height: object)
        .accessibilityHidden(true)
    }

    /// A thin upright mark on the track: midnight, or the usual's end.
    private func tick(at x: CGFloat, width: CGFloat, tall: Bool = false) -> some View {
        let metrics = theme.metrics
        let line = metrics.nightPassTickWidth
        return Capsule()
            .fill(theme.colors.inkSecondary.color.opacity(tall ? 1 : metrics.nightPassTrackOpacity * 4))
            .frame(width: line, height: tall ? metrics.objectInline * 0.7 : metrics.nightPassTrackHeight * 2)
            .offset(x: max(0, min(width - line, x - line / 2)))
    }
}

#Preview("Night pass") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaNightPass(bed: "11:04 PM", woke: "6:52 AM", asleep: "7:21", usual: "Usual 7:05", span: 0.22...0.75, usualSpan: 0.22...0.71, midnight: 0.29)
            SomaNightPass(bed: nil, woke: nil, asleep: nil, span: nil)
        }
        .padding()
    }
}
