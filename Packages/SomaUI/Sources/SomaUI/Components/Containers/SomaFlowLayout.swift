//
//  SomaFlowLayout.swift
//  SomaUI
//

import SwiftUI

/// Items laid out in lines that wrap, for chips and short pills: what does
/// not fit goes to the next line instead of a row that scrolls sideways.
///
/// No item is offered more than the width there is, so a chip longer than
/// the line wraps its own text rather than pushing the page wider.
public struct SomaFlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat? = nil) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing ?? spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let placed = Self.frames(for: subviews.map { $0.sizeThatFits(Self.offer(width)) },
                                 width: width, spacing: spacing, lineSpacing: lineSpacing)
        let used = placed.map(\.maxX).max() ?? 0
        let height = placed.map(\.maxY).max() ?? 0
        return CGSize(width: width.isFinite ? min(used, width) : used, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(Self.offer(bounds.width)) }
        let placed = Self.frames(for: sizes, width: bounds.width, spacing: spacing, lineSpacing: lineSpacing)
        for (subview, frame) in zip(subviews, placed) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private static func offer(_ width: CGFloat) -> ProposedViewSize {
        width.isFinite ? ProposedViewSize(width: width, height: nil) : .unspecified
    }

    /// Where each item goes, line by line, every item kept within `width`.
    static func frames(for sizes: [CGSize], width: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for size in sizes {
            let item = CGSize(width: min(size.width, width), height: size.height)
            if x > 0, x + item.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: item))
            x += item.width + spacing
            line = max(line, item.height)
        }
        return frames
    }
}

#Preview("SomaFlowLayout") {
    SomaFlowLayout {
        ForEach(["All", "Sleep", "Heart", "Mind", "Movement", "Food", "Longevity", "Environment"], id: \.self) { title in
            Text(title)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.quaternary))
        }
    }
    .frame(width: 260)
    .padding()
    .somaTheme(.standard)
}
