//
//  SomaBleedNight.swift
//  SomaUI
//

import SwiftUI

/// The night as the earlier app's sleep sheet led with it (owner, 2026-10-27):
/// full bleed, no card, no lane names, no axis. Four lanes, awake at the top
/// and deep at the foot; each stretch a rounded block a little over half its
/// lane tall, ringed in a shade of its own colour sunk into the page, so a
/// minute awake stands as a tall orange pill; a hairline on the seam between
/// two stages that fades out under both blocks; and the night's sky rising
/// behind the plot and fading back into the page at its foot.
///
/// A sideways drag reads the night: a fine cursor in the colour of the stage
/// under the finger, that block lit and the others dimmed back, and the
/// stage with its clock time floating over the plot on glass. A vertical
/// drag is left to the page. The blocks fill in left to right the first
/// time the night shows; under Reduce Motion they are simply there.
///
/// The rims and the sky are the earlier app's own treatment, which the owner
/// asked for on the night pages; the rest of the app keeps its flat marks.
/// Reached through ``SomaHypnogram/init(fullBleed:)``.
struct SomaBleedNight: View {
    let runs: [SomaStageRun]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the finger reads the night, 0 to 1 by time. Nil when not reading.
    @State private var scrub: CGFloat?
    /// Latched once a drag reads as a vertical scroll, so the page keeps it.
    @State private var scrubIsScroll = false
    /// False until the night first shows, so it fills in once.
    @State private var isSwept = false

    var body: some View {
        let metrics = theme.metrics
        let height = metrics.hypnogramBleedLaneHeight * CGFloat(SomaSleepStage.allCases.count)
        let read = scrub.flatMap { reading(at: $0) }

        GeometryReader { proxy in
            let width = proxy.size.width
            let layout = Layout(runs: runs, width: width, metrics: metrics)

            ZStack(alignment: .topLeading) {
                plot(layout, lit: read?.run)
                    .frame(width: width, height: height)
                    // The sweep: the night shows up to a front that runs
                    // from bed to wake.
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: isSwept || reduceMotion ? width : 0)
                    }

                if let scrub, let read {
                    let inset = metrics.hypnogramBleedRimWidth
                    let x = inset + scrub * max(width - inset * 2, 1)
                    cursor(read.stage.color(theme), height: height)
                        .offset(x: x - metrics.hypnogramBleedCursorWidth / 2)
                    reading(read)
                        .frame(width: metrics.hypnogramBleedReadingWidth)
                        .offset(x: min(max(0, x - metrics.hypnogramBleedReadingWidth / 2),
                                       max(0, width - metrics.hypnogramBleedReadingWidth)))
                }
            }
            .contentShape(.rect)
            .simultaneousGesture(scrubGesture(width: width))
        }
        .frame(height: height)
        .padding(.bottom, metrics.hypnogramBleedFoot)
        .background { sky }
        .somaClaimsSwipe()
        .sensoryFeedback(.selection, trigger: read?.run)
        .onAppear {
            guard !isSwept else { return }
            withAnimation(reduceMotion ? nil : theme.motion.nightSweep) { isSwept = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages"))
        .accessibilityValue(Text(accessibilityValue(read)))
    }

    // MARK: The sky

    /// The page at the top, the night's sky where the deep lane sits, and the
    /// page again at the foot: the earlier app's hero melting into its sheet.
    /// It runs past the column to the screen's edges.
    private var sky: some View {
        let metrics = theme.metrics
        let sky = theme.colors.sleepStages.sky.color
        return LinearGradient(stops: [
            .init(color: sky.opacity(0), location: 0),
            .init(color: sky.opacity(0), location: 0.3),
            .init(color: sky.opacity(metrics.hypnogramBleedSkyRise), location: 0.62),
            .init(color: sky, location: 0.8),
            .init(color: sky.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .padding(.horizontal, -metrics.pagePadding)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: The plot

    /// Threads first, under everything, then each block's rim and fill in
    /// time order: a block's rim laps the one before it, which sets a fine
    /// dark seam between two stretches of one stage, as the earlier app drew it.
    private func plot(_ layout: Layout, lit: Int?) -> some View {
        let metrics = theme.metrics
        let ground = theme.colors.canvas.color
        let fills = Dictionary(uniqueKeysWithValues: SomaSleepStage.allCases.map { ($0, $0.color(theme)) })
        let fallback = theme.colors.inkSecondary.color
        func fill(_ stage: SomaSleepStage) -> Color { fills[stage, default: fallback] }
        func rim(_ stage: SomaSleepStage) -> Color { fill(stage).mix(with: ground, by: metrics.hypnogramBleedRimShade) }
        func thread(_ stage: SomaSleepStage) -> Color { fill(stage).mix(with: ground, by: metrics.hypnogramBleedThreadShade) }
        let dimmed = metrics.hypnogramBleedDimmed
        let ring = metrics.hypnogramBleedRimWidth

        return Canvas { context, _ in
            for link in layout.links {
                let isLit = lit == nil || lit == link.from || lit == link.to
                let alpha = isLit ? 1 : dimmed
                var line = Path()
                line.move(to: CGPoint(x: link.x, y: link.top))
                line.addLine(to: CGPoint(x: link.x, y: link.bottom))
                // The line is at full strength by the time it clears a block
                // and fades to nothing under each, so it never reads as a
                // stick propped between two phases.
                let edge = min(0.4, Double(layout.blockHeight / 2 / max(1, link.bottom - link.top)))
                let upper = thread(link.upper), lower = thread(link.lower)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: [
                        .init(color: upper.opacity(0), location: 0),
                        .init(color: upper.opacity(alpha), location: edge),
                        .init(color: upper.opacity(alpha), location: 0.46),
                        .init(color: lower.opacity(alpha), location: 0.54),
                        .init(color: lower.opacity(alpha), location: 1 - edge),
                        .init(color: lower.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: link.x, y: link.top),
                    endPoint: CGPoint(x: link.x, y: link.bottom))
                context.stroke(line, with: shading,
                               style: StrokeStyle(lineWidth: metrics.hypnogramBleedThreadWidth, lineCap: .round))
            }

            for block in layout.blocks {
                let isLit = lit == nil || lit == block.index
                let corner = min(metrics.hypnogramBleedBlockRadius, block.rect.width / 2, block.rect.height / 2)
                let outer = block.rect.insetBy(dx: -ring, dy: -ring)
                context.fill(Path(roundedRect: outer, cornerRadius: corner + ring, style: .continuous),
                             with: .color(rim(block.stage).opacity(isLit ? 1 : dimmed)))
                context.fill(Path(roundedRect: block.rect, cornerRadius: corner, style: .continuous),
                             with: .color(fill(block.stage).opacity(isLit ? 1 : dimmed)))
            }
        }
        .animation(reduceMotion ? nil : theme.motion.nightEmphasis, value: lit)
        .allowsHitTesting(false)
    }

    /// Where everything on the plot sits, by time across the width.
    struct Layout {
        struct Block {
            let index: Int
            let stage: SomaSleepStage
            let rect: CGRect
        }

        /// A stage change: a vertical line on the seam, from the middle of
        /// the upper block to the middle of the lower one.
        struct Link {
            let from: Int
            let to: Int
            let upper: SomaSleepStage
            let lower: SomaSleepStage
            let x: CGFloat
            let top: CGFloat
            let bottom: CGFloat
        }

        let blockHeight: CGFloat
        let blocks: [Block]
        let links: [Link]

        init(runs: [SomaStageRun], width: CGFloat, metrics: SomaMetrics) {
            let lane = metrics.hypnogramBleedLaneHeight
            blockHeight = lane * metrics.hypnogramBleedBlockShare
            guard let first = runs.first?.start, let last = runs.map(\.end).max() else {
                blocks = []; links = []
                return
            }
            let span = max(last.timeIntervalSince(first), 1)
            // In from each side by a rim, so the first and last blocks keep
            // theirs inside the plot.
            let inset = metrics.hypnogramBleedRimWidth
            let room = max(width - inset * 2, 1)
            func x(_ date: Date) -> CGFloat { inset + room * CGFloat(date.timeIntervalSince(first) / span) }
            func mid(_ stage: SomaSleepStage) -> CGFloat { lane * (CGFloat(stage.rawValue) + 0.5) }
            let height = blockHeight

            blocks = runs.enumerated().map { index, run in
                let x0 = x(run.start)
                return Block(index: index, stage: run.stage,
                             rect: CGRect(x: x0, y: mid(run.stage) - height / 2,
                                          width: max(metrics.hypnogramBleedMinBlockWidth, x(run.end) - x0),
                                          height: height))
            }
            var links: [Link] = []
            for index in runs.indices.dropFirst() {
                let previous = runs[index - 1], next = runs[index]
                // A stretch with nothing recorded before it starts afresh:
                // no line across the hole.
                guard previous.stage != next.stage, next.start.timeIntervalSince(previous.end) < 120 else { continue }
                let goingDown = next.stage.rawValue > previous.stage.rawValue
                links.append(Link(from: index - 1, to: index,
                                  upper: goingDown ? previous.stage : next.stage,
                                  lower: goingDown ? next.stage : previous.stage,
                                  x: blocks[index].rect.minX,
                                  top: mid(goingDown ? previous.stage : next.stage),
                                  bottom: mid(goingDown ? next.stage : previous.stage)))
            }
            self.links = links
        }
    }

    // MARK: Reading the night

    /// A fine rule in the stage's colour, fading at both ends so it reads as
    /// a cursor rather than a hard line.
    private func cursor(_ color: Color, height: CGFloat) -> some View {
        let metrics = theme.metrics
        let ends = color.opacity(metrics.hypnogramBleedCursorEnds)
        return Rectangle()
            .fill(LinearGradient(colors: [ends, color.opacity(metrics.hypnogramBleedCursorPeak), ends],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: metrics.hypnogramBleedCursorWidth, height: height)
            .allowsHitTesting(false)
    }

    /// The stage under the finger and its clock time, on glass over the plot.
    private func reading(_ read: Reading) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let hue = read.stage.color(theme)

        return HStack(spacing: metrics.spaceS) {
            Circle().fill(hue).frame(width: metrics.hypnogramBleedReadingDot, height: metrics.hypnogramBleedReadingDot)
            VStack(alignment: .leading, spacing: 0) {
                Text(read.stage.title)
                    .somaFont(type.headerTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(verbatim: SomaHypnogram.clock(read.date))
                    .somaFont(type.captionValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .fixedSize()
        .padding(.horizontal, metrics.spaceM)
        .padding(.vertical, metrics.spaceS)
        .somaGlass(in: Capsule())
        .allowsHitTesting(false)
    }

    /// The stretch, stage and moment under the finger.
    private struct Reading: Equatable {
        let run: Int
        let stage: SomaSleepStage
        let date: Date
    }

    private func reading(at share: CGFloat) -> Reading? {
        guard let first = runs.first?.start, let last = runs.map(\.end).max() else { return nil }
        let date = first.addingTimeInterval(last.timeIntervalSince(first) * Double(min(max(share, 0), 1)))
        guard let index = runs.lastIndex(where: { $0.start <= date }) else { return nil }
        return Reading(run: index, stage: runs[index].stage, date: date)
    }

    /// Only a sideways drag reads; a drag that starts vertical is the page's.
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !scrubIsScroll else { return }
                if scrub == nil, abs(value.translation.height) > abs(value.translation.width) {
                    scrubIsScroll = true
                    return
                }
                let inset = theme.metrics.hypnogramBleedRimWidth
                scrub = min(max((value.location.x - inset) / max(width - inset * 2, 1), 0), 1)
            }
            .onEnded { _ in
                scrub = nil
                scrubIsScroll = false
            }
    }

    /// The stage and time under the finger while reading; the night's span
    /// and the time in each stage at rest.
    private func accessibilityValue(_ read: Reading?) -> String {
        if let read {
            return "\(String(localized: read.stage.title)), \(SomaHypnogram.clock(read.date))"
        }
        guard let first = runs.first?.start, let last = runs.map(\.end).max() else { return SomaFormat.notMeasured }
        var seconds: [SomaSleepStage: TimeInterval] = [:]
        for run in runs { seconds[run.stage, default: 0] += run.end.timeIntervalSince(run.start) }
        let stages = SomaSleepStage.allCases.compactMap { stage in
            seconds[stage].map { "\(String(localized: stage.title)) \(SomaFormat.duration($0))" }
        }
        return "\(SomaHypnogram.clock(first)) to \(SomaHypnogram.clock(last)). " + stages.joined(separator: ", ")
    }
}

#Preview("Full bleed night") {
    // A broken night, the kind the earlier app's picture shows: long core and
    // REM stretches, two dips into deep, and a handful of short wakings.
    let start = Date(timeIntervalSince1970: 1_790_033_640)
    let stretches: [(SomaSleepStage, Double)] = [
        (.awake, 3), (.core, 16), (.deep, 24), (.core, 8), (.rem, 14), (.core, 22), (.awake, 1), (.rem, 6),
        (.core, 26), (.awake, 1), (.core, 14), (.rem, 18), (.core, 30), (.awake, 2), (.core, 20), (.deep, 11),
        (.core, 24), (.rem, 14), (.awake, 1), (.rem, 6), (.core, 28), (.awake, 2), (.rem, 22), (.core, 18),
        (.awake, 1), (.core, 16), (.rem, 14), (.awake, 2), (.core, 22), (.awake, 1),
    ]
    var at = start
    let runs = stretches.map { stage, minutes in
        defer { at = at.addingTimeInterval(minutes * 60) }
        return SomaStageRun(stage: stage, start: at, end: at.addingTimeInterval(minutes * 60))
    }
    return ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            SomaHypnogram(fullBleed: runs)
                .padding(.horizontal, SomaMetrics.standard.pagePadding)
                .padding(.top, SomaMetrics.standard.heroTopPadding)
        }
    }
}
