//
//  SomaPartSwitcher.swift
//  SomaUI
//

import SwiftUI

/// The parts of a tab, one at a time, handing over with a short cross-fade.
public struct SomaPartSwitcher<Part: Hashable & CaseIterable, Content: View>: View
where Part.AllCases: RandomAccessCollection {
    private let selection: Part
    private let content: (Part) -> Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Part
    @State private var edge: CGFloat = 1

    public init(selection: Part, @ViewBuilder content: @escaping (Part) -> Content) {
        self.selection = selection
        self.content = content
        _shown = State(initialValue: selection)
    }

    public var body: some View {
        let motion = theme.motion

        ZStack {
            content(shown)
                .id(shown)
                .transition(transition(motion))
        }
        .onChange(of: selection) { old, new in
            edge = index(of: new) >= index(of: old) ? 1 : -1
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.2)) {
                shown = new
            }
        }
    }

    /// A plain cross-fade. The slide, blur and shrink it used to carry read
    /// as cards swimming into place; the owner called it garbage (2026-10-03).
    private func transition(_ motion: SomaMotion) -> AnyTransition {
        .opacity
    }

    private func index(of part: Part) -> Int {
        Part.allCases.firstIndex(of: part).map { Part.allCases.distance(from: Part.allCases.startIndex, to: $0) } ?? 0
    }
}

/// Where a page is while it arrives or leaves: a little to one side, blurred,
/// faded and very slightly smaller.
struct SomaArrival: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

public extension View {
    /// A no-op kept so call sites stay put; see ``SomaTabEntrance``.
    func somaTabEntrance(isActive: Bool) -> some View {
        modifier(SomaTabEntrance(isActive: isActive))
    }
}

/// Kept as a seam, drawing nothing: the rise out of a blur on every tab switch
/// read as the page loading twice. The system's own tab switch is the motion.
struct SomaTabEntrance: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
    }
}

public extension View {
    /// A no-op kept so call sites stay put; see ``SomaScrollReveal``.
    func somaScrollReveal() -> some View {
        modifier(SomaScrollReveal())
    }
}

/// Draws nothing now: cards shrinking and fading at the foot of the screen
/// made every page look half loaded. Cards scroll as they are.
struct SomaScrollReveal: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

#Preview("Part switcher") {
    struct Demo: View {
        enum Part: CaseIterable { case a, b, c }
        @State var part = Part.a
        var body: some View {
            VStack {
                Picker("", selection: $part) {
                    Text(verbatim: "A").tag(Part.a)
                    Text(verbatim: "B").tag(Part.b)
                    Text(verbatim: "C").tag(Part.c)
                }
                .pickerStyle(.segmented)
                SomaPartSwitcher(selection: part) { part in
                    SomaCard { Text(verbatim: "\(part)").frame(height: 200) }
                }
            }
            .padding()
        }
    }
    return Demo()
}
