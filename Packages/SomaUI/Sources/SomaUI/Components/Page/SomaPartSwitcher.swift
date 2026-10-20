//
//  SomaPartSwitcher.swift
//  SomaUI
//

import SwiftUI

/// The parts of a tab side by side, one on screen at a time, like the pages
/// of a pager: choosing a segment slides the strip to that part on a spring,
/// timed with the segmented control's pill, and a sideways swipe on the page
/// drags the strip under the finger and lets it go to the part it lands
/// nearest, carrying the finger's speed.
///
/// The chosen part draws alone on the tab's first frame, so it is on screen
/// as soon as it can be; the others join right after it, at low priority,
/// and every part then stays alive: a part never loads while it slides in,
/// keeps its own scroll position, and a part held in a cache (the Longevity
/// snapshot) is simply there. A slide or a swipe that comes before they
/// joined draws them first. Nothing between two parts is ever blank: a jump
/// over a part slides through it. The strip is clipped to its width, so a
/// waiting neighbour never shows under a floating sidebar.
///
/// The parts move whole and stay sharp: no blur, no shrink, no fade on the way
/// (the owner called cards swimming into place garbage, 2026-10-03). Under
/// Reduce Motion the parts cross fade in place, quickly, and the swipe still
/// changes part without the slide.
///
/// The strip is not a paged scroll view: a page's vertical scroll inside a
/// horizontal one hides it from the tab bar, which then stops minimizing
/// (tried on 2026-10-20). The swipe is a pan that only begins when the finger
/// moves sideways, and gives way to anything on the page that reads a
/// sideways drag itself (`somaClaimsSwipe()`).
public struct SomaPartSwitcher<Part: Hashable & CaseIterable, Content: View>: View
where Part.AllCases: RandomAccessCollection {
    private let selection: Part
    private let select: ((Part) -> Void)?
    private let content: (Part) -> Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The strip's place, in parts: 1.5 is halfway from the second to the third.
    @State private var position: Double
    /// How far a finger has dragged the strip, in points.
    @State private var drag: CGFloat = 0
    /// The parts on screen or on the way, by place: the rest hold their own
    /// animations still.
    @State private var showing: Set<Int>
    /// The parts drawn so far, by place: the chosen one on the first frame,
    /// the rest just after it.
    @State private var built: Set<Int>
    @State private var claims = SomaSwipeClaims()

    /// Parts that follow `selection` and can only be changed from outside
    /// (the segmented control): no swipe.
    public init(selection: Part, @ViewBuilder content: @escaping (Part) -> Content) {
        self.init(selection: selection, select: nil, content: content)
    }

    /// Parts that follow `selection` and also change it with a sideways swipe.
    public init(selection: Binding<Part>, @ViewBuilder content: @escaping (Part) -> Content) {
        self.init(selection: selection.wrappedValue, select: { selection.wrappedValue = $0 }, content: content)
    }

    private init(selection: Part, select: ((Part) -> Void)?, content: @escaping (Part) -> Content) {
        self.selection = selection
        self.select = select
        self.content = content
        let index = Self.index(of: selection)
        _position = State(initialValue: Double(index))
        _showing = State(initialValue: [index])
        _built = State(initialValue: [index])
    }

    private var parts: [Part] { Array(Part.allCases) }
    private var current: Int { Self.index(of: selection) }

    public var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            ZStack(alignment: .topLeading) {
                // The chosen part is last in the strip: the tab bar follows the
                // last scroll view in the page, so a part placed after it,
                // even out of sight, would take the bar's minimizing away
                // from the one on screen (2026-10-20).
                ForEach(Self.order(parts.count, current: current).filter(built.contains), id: \.self) { index in
                    let shown = showing.contains(index) || drag != 0
                    content(parts[index])
                        .frame(width: width, height: proxy.size.height)
                        .offset(x: reduceMotion ? 0 : (CGFloat(index) - position) * width + drag)
                        // Out of sight by its place beside the screen, not by
                        // a zero opacity: a view drawn at zero opacity is not
                        // brought up to date until it shows, so its numbers
                        // would roll in as it slides on.
                        .opacity(reduceMotion ? (index == current ? 1 : 0) : 1)
                        .allowsHitTesting(index == current)
                        .accessibilityHidden(index != current)
                        .environment(\.somaPartIsShown, shown && (!reduceMotion || index == current))
                        .environment(\.somaPartIsCurrent, index == current)
                        .zIndex(index == current ? 1 : 0)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
            // The parts beside the screen stay inside the page's width: on a
            // roomy screen the sidebar floats over the content's leading
            // edge, and a neighbour waiting there showed through its glass.
            // Clipped sideways only, so a page still scrolls under the bars
            // and fades there.
            .clipShape(SomaHorizontalClip())
            // Under Reduce Motion the parts cross fade in place.
            .animation(reduceMotion ? .easeInOut(duration: theme.motion.partFadeDuration) : nil, value: current)
            .environment(\.somaSwipeClaims, claims)
#if os(iOS)
            .gesture(SomaPartPan(
                canBegin: { location in select != nil && !claims.contains(location) },
                changed: { translation in dragged(translation, width: width) },
                ended: { translation, velocity in released(translation, velocity: velocity, width: width) }
            ))
#endif
        }
        .onChange(of: selection) { _, new in
            go(to: Self.index(of: new), velocity: 0)
        }
        // The part on screen draws alone on the first frame; the others join
        // right after it, at low priority, so they are there before any slide.
        .task(priority: .low) {
            await Task.yield()
            buildAll()
        }
    }

    /// Draws every part not drawn yet, in one go. They join ahead of the
    /// part on screen in the strip, which stays last, where the bars look
    /// for it (checked on 2026-10-20: the tab bar still minimizes on Today
    /// and Trends once the others joined).
    private func buildAll() {
        let all = Set(parts.indices)
        guard built != all else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { built = all }
    }

    // MARK: - Moving

    /// The strip moving to the part at `target`, from wherever it is now,
    /// with the finger's speed (parts a second) when a swipe let it go.
    private func go(to target: Int, velocity: Double) {
        let from = Int(position.rounded())
        guard Double(target) != position || drag != 0 else { return }
        let passing = Set(min(from, target)...max(from, target))
        buildAll()
        showing.formUnion(passing)
        if reduceMotion {
            position = Double(target)
            drag = 0
            showing = [target]
            return
        }
        let distance = Double(target) - position
        let animation = velocity == 0 || abs(distance) < 0.001
            ? theme.motion.partSwitch
            : theme.motion.partSettle(velocity: max(-8, min(8, velocity / distance)))
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            position = Double(target)
        } completion: {
            // Only once the strip rests on this part; a newer move keeps its own.
            if position == Double(target), drag == 0 { showing = [target] }
        }
    }

    private func dragged(_ translation: CGFloat, width: CGFloat) {
        let count = parts.count
        let index = current
        // Past the first or the last part the strip resists, as a pager does.
        let atEdge = (index == 0 && translation > 0) || (index == count - 1 && translation < 0)
        let moved = atEdge ? SomaPartMath.resisted(translation, width: width) : translation
        buildAll()
        if !reduceMotion {
            showing.formUnion(Self.neighbours(of: index, count: count))
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag = moved }
    }

    private func released(_ translation: CGFloat, velocity: CGFloat, width: CGFloat) {
        let target = SomaPartMath.landing(
            from: current, count: parts.count, translation: translation, velocity: velocity, width: width,
            reach: theme.metrics.partSwipeReach, flick: theme.metrics.partSwipeFlick
        )
        // The strip takes over where the finger left it, then springs on.
        let here = position - Double(drag / width)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position = here
            drag = 0
        }
        if target != current {
            withAnimation(reduceMotion ? nil : theme.motion.selection) {
                select?(parts[target])
            }
        }
        go(to: target, velocity: Double(-velocity / width))
    }

    // MARK: - Arithmetic

    private static func index(of part: Part) -> Int {
        Part.allCases.firstIndex(of: part).map { Part.allCases.distance(from: Part.allCases.startIndex, to: $0) } ?? 0
    }

    /// The parts in the strip, the one on screen last: the bars follow the
    /// last scroll view in the page, so that has to be the current part's.
    private static func order(_ count: Int, current: Int) -> [Int] {
        (0..<count).sorted { ($0 == current ? 1 : 0, $0) < ($1 == current ? 1 : 0, $1) }
    }

    private static func neighbours(of index: Int, count: Int) -> Set<Int> {
        Set([index - 1, index, index + 1].filter { $0 >= 0 && $0 < count })
    }
}

/// A clip to the view's width that leaves its height open: what draws above
/// or below (a page under the bars) stays, what stands beside goes.
struct SomaHorizontalClip: Shape {
    /// Far enough above and below to cover any page.
    static let reach: CGFloat = 100_000

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - Self.reach, width: rect.width, height: rect.height + Self.reach * 2))
    }
}

/// The arithmetic of a swipe between parts, kept apart so it is tested.
public enum SomaPartMath {
    /// Where a swipe lands: the next part when it was dragged past `reach`
    /// of the width or flicked faster than `flick` points a second that way,
    /// else back where it started.
    public static func landing(
        from index: Int, count: Int, translation: CGFloat, velocity: CGFloat,
        width: CGFloat, reach: CGFloat, flick: CGFloat
    ) -> Int {
        let share = translation / max(1, width)
        var target = index
        if share < -reach || velocity < -flick { target = index + 1 }
        if share > reach || velocity > flick { target = index - 1 }
        // A flick against the drag cancels it.
        if translation < 0, velocity > flick { target = index }
        if translation > 0, velocity < -flick { target = index }
        return min(max(0, target), count - 1)
    }

    /// A drag past the first or the last part, damped: the further the
    /// finger goes, the less the strip follows.
    public static func resisted(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let limit = max(1, width) * 0.18
        let x = abs(translation)
        let damped = limit * (1 - 1 / (x / limit * 0.55 + 1))
        return translation < 0 ? -damped : damped
    }
}

/// Where on the screen something reads a sideways drag of its own (a chart
/// a finger scrubs, a ruler, a week strip): a swipe between parts that
/// starts there is left to it.
@MainActor
final class SomaSwipeClaims {
    private var frames: [UUID: CGRect] = [:]

    func set(_ frame: CGRect?, for id: UUID) {
        frames[id] = frame
    }

    func contains(_ point: CGPoint) -> Bool {
        frames.values.contains { $0.contains(point) }
    }
}

extension EnvironmentValues {
    @Entry var somaSwipeClaims: SomaSwipeClaims?
}

public extension EnvironmentValues {
    /// False for a tab's part that is kept alive but not on screen: what it
    /// animates on its own (an orb's weather, a backdrop's drift) holds still.
    @Entry var somaPartIsShown: Bool = true
    /// True for the part a tab has chosen, false for the others it keeps
    /// alive, even while they slide across the screen.
    @Entry var somaPartIsCurrent: Bool = true
}

public extension View {
    /// Marks this view as reading sideways drags itself, so a swipe between
    /// a tab's parts that starts on it is left to it. Harmless outside a
    /// ``SomaPartSwitcher``.
    func somaClaimsSwipe() -> some View {
        modifier(SomaSwipeClaim())
    }
}

private struct SomaSwipeClaim: ViewModifier {
    @Environment(\.somaSwipeClaims) private var claims
    @Environment(\.somaPartIsShown) private var isShown
    @State private var id = UUID()

    func body(content: Content) -> some View {
        if let claims {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    claims.set(isShown ? frame : nil, for: id)
                }
                .onChange(of: isShown) { _, shown in
                    if !shown { claims.set(nil, for: id) }
                }
                .onDisappear { claims.set(nil, for: id) }
        } else {
            content
        }
    }
}

#if os(iOS)
/// A pan that begins only when the finger moves sideways, so the page's own
/// vertical scroll keeps every upright drag, and that the page's scroll waits
/// on for the instant it takes to decide.
struct SomaPartPan: UIGestureRecognizerRepresentable {
    /// Whether a swipe starting at this point (in the window) may begin.
    var canBegin: @MainActor (CGPoint) -> Bool
    var changed: @MainActor (CGFloat) -> Void
    var ended: @MainActor (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(canBegin: canBegin)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            changed(translation)
        case .ended:
            ended(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            ended(translation, 0)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: @MainActor (CGPoint) -> Bool

        init(canBegin: @escaping @MainActor (CGPoint) -> Bool) {
            self.canBegin = canBegin
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * 1.4 else { return false }
            // Where the finger first came down, in the window.
            let now = pan.location(in: nil)
            let moved = pan.translation(in: nil)
            return canBegin(CGPoint(x: now.x - moved.x, y: now.y - moved.y))
        }

        /// The page's vertical scroll waits for this pan to fail, which it
        /// does at once for an upright drag.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView && other is UIPanGestureRecognizer
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
#endif

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
                SomaSegmentedControl(
                    segments: [
                        SomaSegment(id: Part.a, title: "Today"),
                        SomaSegment(id: Part.b, title: "Trends"),
                        SomaSegment(id: Part.c, title: "Explore"),
                    ],
                    selection: $part
                )
                SomaPartSwitcher(selection: part) { part in
                    SomaCard { Text(verbatim: "\(part)").frame(maxWidth: .infinity, minHeight: 200) }
                        .padding()
                }
            }
            .padding(.vertical)
        }
    }
    return Demo()
}
