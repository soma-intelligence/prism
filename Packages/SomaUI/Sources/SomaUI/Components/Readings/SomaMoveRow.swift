//
//  SomaMoveRow.swift
//  SomaUI
//

import SwiftUI

/// The title of a card that carries a list, with a caption under it. A caption
/// Soma wrote itself is signed with the mark.
public struct SomaCardHeader: View {
    private let title: LocalizedStringResource
    private let caption: LocalizedStringResource?
    private let isSigned: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - title: what the card is about: Tonight, Today.
    ///   - caption: set small under it.
    ///   - isSigned: whether the caption is Soma speaking, which sets the mark
    ///     before it.
    public init(_ title: LocalizedStringResource, caption: LocalizedStringResource? = nil, isSigned: Bool = false) {
        self.title = title
        self.caption = caption
        self.isSigned = isSigned
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
            Text(title)
                .somaFont(type.cardTitle)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)

            if let caption {
                HStack(spacing: metrics.identityDotSpacing) {
                    if isSigned {
                        SomaMark(accessibilityLabel: "Soma", role: .caption)
                    }
                    Text(caption)
                        .somaFont(type.eyebrow)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One next move: the object of the aspect it serves, the
/// move itself as the hero (a time set large under the few words that lead
/// to it: "In bed by" over "11:00 PM"), and a slim check that fills with the
/// aspect's colour once it is done.
///
/// Done dims the words rather than striking them through, and the check
/// carries the state.
public struct SomaMoveRow: View {
    private let aspect: SomaAspect
    private let lead: String?
    private let title: String
    private let reason: String?
    private let isDone: Bool
    private let toggle: () -> Void

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - lead: the words before the hero, set small above it ("In bed
    ///     by"). Nil sets the title alone.
    ///   - title: the move, or with a lead the part that matters ("11:00 PM").
    public init(aspect: SomaAspect, lead: String? = nil, title: String, reason: String?, isDone: Bool, toggle: @escaping () -> Void) {
        self.aspect = aspect
        self.lead = lead
        self.title = title
        self.reason = reason
        self.isDone = isDone
        self.toggle = toggle
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .center, spacing: metrics.moveRowGap) {
            SomaObjectIcon(aspect, size: .row)

            VStack(alignment: .leading, spacing: 0) {
                if let lead {
                    Text(lead)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Text(title)
                    .somaFont(lead == nil ? type.callout : type.metricCompact)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let reason {
                    Text(reason)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isDone ? theme.motion.dimOpacity : 1)

            Button(action: toggle) {
                SomaCheck(isDone: isDone, aspect: aspect)
                    .frame(width: metrics.minimumTapTarget, height: metrics.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text([lead, title].compactMap { $0 }.joined(separator: " ")))
            .accessibilityValue(Text(isDone ? "Done" : "Not done"))
            .accessibilityHint(Text(isDone ? "Marks it not done." : "Marks it done."))
        }
    }
}

/// The ring at the end of a move: a slim outline, filled once it is done
/// with the aspect's colour, or the accent without one.
public struct SomaCheck: View {
    private let isDone: Bool
    private let aspect: SomaAspect?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isDone: Bool, aspect: SomaAspect? = nil) {
        self.isDone = isDone
        self.aspect = aspect
    }

    public var body: some View {
        let side = theme.metrics.checkDiameter
        let fill = aspect.map { theme.aspects[$0].identity.color } ?? theme.colors.accent.color
        ZStack {
            Circle()
                .strokeBorder(theme.colors.inkSecondary.color.opacity(0.6), lineWidth: 1)
                .opacity(isDone ? 0 : 1)
            Circle()
                .fill(fill)
                .opacity(isDone ? 1 : 0)
            SomaCheckGlyph()
                .stroke(theme.colors.onAccent.color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .padding(side * 0.28)
                .opacity(isDone ? 1 : 0)
        }
        .frame(width: side, height: side)
        .animation(reduceMotion ? nil : theme.motion.quick, value: isDone)
        .accessibilityHidden(true)
    }
}

/// A check mark drawn as a path, so it scales with the ring it sits in.
struct SomaCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return path
    }
}

#Preview("Moves") {
    @Previewable @State var done: Set<Int> = [1]
    ZStack {
        SomaPreviewBackdrop()
        SomaCard {
            VStack(alignment: .leading, spacing: SomaMetrics.standard.spaceM) {
                Text("Tonight")
                ForEach(0..<2) { index in
                    SomaMoveRow(
                        aspect: index == 0 ? .mind : .sleep,
                        lead: index == 0 ? nil : "In bed by",
                        title: index == 0 ? "Breathe for 10 minutes" : "23:00",
                        reason: nil,
                        isDone: done.contains(index)
                    ) {
                        if done.contains(index) { done.remove(index) } else { done.insert(index) }
                    }
                }
            }
        }
        .padding()
    }
}
