//
//  OnboardingStage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Where the run's one orb sits on a screen, how strong the ground is, and
/// where the screen's words start.
///
/// The orb is a single view for the whole run, so a screen does not draw it:
/// it names a place, and the orb glides there. The story it tells: large and
/// centred on sign in, up and smaller at the leading edge once questions
/// arrive, parked in the corner while the permissions are asked, then back to
/// full size exactly where Today draws its own.
struct OnboardingStage: Equatable {
    /// The orb's centre, in the flow's own space.
    let orbCenter: CGPoint
    /// The orb's size, as a share of the hero diameter.
    let orbScale: CGFloat
    /// Where the screen's words start, measured down from the top bar.
    let contentTop: CGFloat
    /// How much of the aspect's ground shows: full where the orb is the
    /// subject, quieter where there are fields to read.
    let groundStrength: Double

    init(step: OnboardingStep, size: CGSize, metrics: SomaMetrics) {
        let bar = metrics.onboardingTopBarHeight
        let diameter = metrics.orbDiameter
        let column = min(size.width, metrics.pageMaxWidth)
        let leading = (size.width - column) / 2 + metrics.pagePadding
        let trailing = size.width - (size.width - column) / 2 - metrics.pagePadding

        func atLeading(_ scale: CGFloat) -> (CGPoint, CGFloat) {
            let radius = diameter * scale / 2
            return (CGPoint(x: leading + radius, y: bar + radius + metrics.onboardingOrbGap / 2), scale)
        }

        let place: (CGPoint, CGFloat)
        switch step {
        case .signIn:
            let scale = metrics.onboardingOrbWelcomeScale
            let lowest = bar + metrics.heroTopPadding + diameter * scale / 2
            place = (CGPoint(x: size.width / 2, y: max(lowest, size.height * metrics.onboardingOrbWelcomeHeight)), scale)
        case .email, .about:
            place = atLeading(metrics.onboardingOrbFieldScale)
        case .focus:
            place = atLeading(metrics.onboardingOrbQuestionScale)
        case .connect:
            let scale = metrics.onboardingOrbCornerScale
            place = (CGPoint(x: trailing - diameter * scale / 2, y: bar / 2 + 4), scale)
        case .ready:
            // Today's orb: under a bar of the same height, after the hero's
            // top padding, centred, full size.
            place = (CGPoint(x: size.width / 2, y: bar + metrics.heroTopPadding + diameter / 2), 1)
        }
        orbCenter = place.0
        orbScale = place.1

        let orbBottom = place.0.y + diameter * place.1 / 2
        switch step {
        case .connect:
            contentTop = metrics.onboardingOrbGap
        case .signIn, .ready:
            contentTop = orbBottom - bar + metrics.onboardingOrbGap * 1.5
        default:
            contentTop = orbBottom - bar + metrics.onboardingOrbGap
        }

        switch step {
        case .signIn, .ready: groundStrength = 1
        case .focus: groundStrength = 0.75
        default: groundStrength = 0.5
        }
    }
}

/// The ground under the whole run: the aspect's colour field, or its
/// landscape photograph in the Landscape theme, fading from one aspect to the
/// next instead of each screen painting its own.
struct OnboardingGround: View {
    let aspect: SomaAspect
    let strength: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SomaAspectBackdrop(aspect: aspect)
                    .id(aspect)
                    .transition(.opacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height * 0.62)
            .clipped()
            .opacity(strength)
            .animation(theme.motion.onboardingGround, value: aspect)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The run's one orb, carried to each screen's place.
///
/// With Reduce Motion on it never travels: it fades out of one place and into
/// the next, and the orb itself holds still.
struct OnboardingOrbLayer: View {
    let aspect: SomaAspect
    let label: LocalizedStringResource?
    let stage: OnboardingStage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            placed
                .id(stage.orbCenter.x * 7 + stage.orbCenter.y + stage.orbScale)
                .transition(.opacity)
        } else {
            placed
        }
    }

    private var placed: some View {
        SomaOrb(aspect: aspect, label: label)
            .scaleEffect(stage.orbScale)
            .position(stage.orbCenter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The back chevron and the progress bar, which stay put for the whole run.
struct OnboardingTopBar: View {
    let model: OnboardingModel

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        ZStack {
            OnboardingProgressBar(index: model.step.progressIndex, count: OnboardingStep.screens.count)
            HStack {
                if model.canGoBack {
                    SomaIconButton(symbol: "chevron.left", accessibilityLabel: "Back") { model.back() }
                        .transition(.opacity)
                }
                Spacer()
            }
        }
        .frame(height: metrics.onboardingTopBarHeight)
        .padding(.horizontal, metrics.pagePadding * 0.66)
    }
}

/// A slim bar in segments, one per screen. The segments up to the current
/// one are filled, and a new one fills from its leading edge as the screen
/// changes.
struct OnboardingProgressBar: View {
    let index: Int
    let count: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let ink = theme.colors.inkPrimary.color

        HStack(spacing: metrics.onboardingProgressSpacing) {
            ForEach(0..<count, id: \.self) { segment in
                Capsule()
                    .fill(ink.opacity(metrics.hairlineOpacity * 1.6))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(ink)
                            .scaleEffect(x: segment <= index ? 1 : 0.001, anchor: .leading)
                    }
                    .clipShape(.capsule)
            }
        }
        .frame(maxWidth: metrics.onboardingProgressMaxWidth)
        .frame(height: metrics.onboardingProgressHeight)
        .padding(.horizontal, metrics.iconButtonDiameter + 8)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(index + 1) of \(count)"))
    }
}

extension EnvironmentValues {
    /// True where a screen is drawn already arrived: the render check, which
    /// takes one frame and never runs `onAppear`'s animation.
    @Entry var onboardingArrivalsSettled = false
}

/// A screen's line arriving: a short fade and a rise of a few points, each
/// line a beat after the one before. Nothing blurs and nothing slides in from
/// the side. With Reduce Motion on the line only fades.
private struct OnboardingArrival: ViewModifier {
    let order: Int

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.onboardingArrivalsSettled) private var settled
    @State private var shown = false

    func body(content: Content) -> some View {
        let motion = theme.motion
        let isShown = shown || settled

        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : motion.onboardingArrivalRise)
            .onAppear {
                guard !shown else { return }
                let delay = reduceMotion ? 0 : motion.onboardingArrivalLead + Double(order) * motion.onboardingArrivalStagger
                withAnimation((reduceMotion ? motion.onboardingStepStill : motion.onboardingArrival).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Brings this line of a screen in at its place in the order.
    func onboardingArrival(_ order: Int) -> some View {
        modifier(OnboardingArrival(order: order))
    }
}

/// A screen's words: the short title, then whatever the screen holds, in one
/// column that scrolls only when it has to.
struct OnboardingPage<Content: View>: View {
    let title: String
    var centred = false
    @ViewBuilder var content: () -> Content

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        ScrollView {
            VStack(alignment: centred ? .center : .leading, spacing: metrics.onboardingTitleGap) {
                Text(title)
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .multilineTextAlignment(centred ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .onboardingArrival(0)
                content()
            }
            .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}
