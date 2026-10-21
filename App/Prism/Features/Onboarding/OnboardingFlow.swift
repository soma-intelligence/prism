//
//  OnboardingFlow.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The screens of the first run, in order.
///
/// Five screens (owner, 2026-10-03: "super tight, fast, with all the info,
/// and with as little text as possible"): sign in, focus, the profile on one
/// screen, every permission on one screen, and the hand over to Today. Email
/// is a branch of sign in, not a screen of its own in the count, and is hidden
/// until accounts support it (``OnboardingSignInOptions/offersEmail``).
enum OnboardingStep: Int, CaseIterable, Comparable {
    case signIn
    case email
    case focus
    case about
    case connect
    case ready

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The screens the progress bar counts.
    static let screens: [OnboardingStep] = [.signIn, .focus, .about, .connect, .ready]

    /// Where the bar stands on this step. Email counts as sign in.
    var progressIndex: Int {
        Self.screens.firstIndex(of: self == .email ? .signIn : self) ?? 0
    }
}

/// Moves the first run along and keeps what it has been told.
///
/// The answers being given live here, not in the screens, because the one
/// Continue at the foot belongs to the whole run: it reads them to know
/// whether it is awake. Each answer is written to ``SomaProfileStore`` the
/// moment its screen is left, so a run abandoned half way keeps what it had,
/// and a replay from Developer tools starts from the answers already given.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep = .signIn

    /// The focus areas, in the order they were picked.
    var focus: [FocusArea]
    var name: String
    var birthday: Date
    /// Whether the birthday was given rather than left on the starting date,
    /// which is a guess and is never saved as an answer.
    var hasBirthday: Bool
    var sex: BiologicalSex?
    /// Why Sign in with Apple did not go through, shown under the title.
    var signInFailure: String?

    let store: SomaProfileStore
    private let finish: () -> Void

    init(store: SomaProfileStore, finish: @escaping () -> Void) {
        self.store = store
        self.finish = finish
        let profile = store.profile
        focus = profile.focus
        name = profile.name ?? ""
        birthday = profile.birthday ?? Self.startingBirthday
        hasBirthday = profile.birthday != nil
        sex = profile.sex
#if DEBUG
        // `-onboarding.step about` opens the run on one screen, for checking
        // it without walking the ones before. Debug builds only.
        if let name = UserDefaults.standard.string(forKey: "onboarding.step"),
           let start = OnboardingStep.allCases.first(where: { "\($0)" == name }),
           start != .email || OnboardingSignInOptions.offersEmail {
            step = start
        }
#endif
    }

    /// Where the date wheel rests before it is touched: thirty five years back.
    static var startingBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -35, to: .now) ?? .now
    }

    var profile: SomaProfile { store.profile }

    func update(_ change: (inout SomaProfile) -> Void) {
        store.update(change)
    }

    /// Whether the one Continue at the foot can be pressed on this screen.
    var canContinue: Bool {
        switch step {
        case .focus: !focus.isEmpty
        case .about: hasBirthday && sex != nil
        default: true
        }
    }

    /// Keeps the answers of the screen being left, then moves on.
    func advance() {
        save()
        switch step {
        case .signIn, .email: go(to: .focus)
        case .focus: go(to: .about)
        case .about: go(to: .connect)
        case .connect: go(to: .ready)
        case .ready:
            update { $0.onboardedAt = Date() }
            finish()
        }
    }

    func back() {
        save()
        switch step {
        case .signIn: return
        case .email, .focus: go(to: .signIn)
        case .about: go(to: .focus)
        case .connect: go(to: .about)
        case .ready: go(to: .connect)
        }
    }

    /// Moves to a step. The email step is skipped while the email path is
    /// hidden (``OnboardingSignInOptions/offersEmail``), so nothing can land
    /// on it, a replay from Developer tools included.
    func go(to next: OnboardingStep) {
        guard next != .email || OnboardingSignInOptions.offersEmail else { return }
        step = next
    }

    /// Whether a back chevron is drawn: sign in is the first screen.
    var canGoBack: Bool { step != .signIn }

    private func save() {
        switch step {
        case .focus:
            let picked = focus
            update { $0.focus = picked }
        case .about:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let born = hasBirthday ? birthday : nil
            let picked = sex
            update {
                $0.name = trimmed.isEmpty ? $0.name : trimmed
                if let born { $0.birthday = born }
                if let picked { $0.sex = picked }
            }
        default:
            break
        }
    }
}

/// The first run, full screen, over where the tabs will be.
///
/// One stage rather than a stack of pages: the ground, the orb, the progress
/// bar and the one Continue stay put for the whole run and move to each
/// screen's place, and only the words of a screen arrive and leave. The orb
/// ends where Today draws its own, with Today's aspect, so entering the app is
/// the same orb settling into its page.
///
/// Presented by `ContentView` until the `onboarding.completed` flag is set;
/// Developer tools clears the flag to replay it.
struct OnboardingFlow: View {
    /// The `@AppStorage` key the shell reads.
    static let completedKey = "onboarding.completed"

    @State private var model: OnboardingModel

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(store: SomaProfileStore? = nil, finish: @escaping () -> Void) {
        _model = State(initialValue: OnboardingModel(store: store ?? .shared, finish: finish))
    }

    /// For the render check and previews: a run opened on one screen.
    @MainActor
    init(model: OnboardingModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        let motion = theme.motion

        GeometryReader { proxy in
            let stage = OnboardingStage(step: model.step, size: proxy.size, metrics: theme.metrics)

            ZStack(alignment: .top) {
                OnboardingGround(aspect: aspect, strength: stage.groundStrength)

                OnboardingOrbLayer(aspect: aspect, label: orbLabel, stage: stage)

                VStack(spacing: 0) {
                    OnboardingTopBar(model: model)
                    ZStack(alignment: .top) {
                        page
                            .id(model.step)
                            .padding(.top, stage.contentTop)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(motion.onboardingDeparture)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    footer
                }
            }
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .animation(reduceMotion ? motion.onboardingStepStill : motion.onboardingStep, value: model.step)
        .simultaneousGesture(backSwipe, including: model.canGoBack ? .all : .subviews)
    }

    /// The aspect the orb and the ground wear on this screen: the topic the
    /// screen is about, so the colour changes as the subject does.
    private var aspect: SomaAspect {
        switch model.step {
        case .signIn, .email: .mind
        case .focus: model.focus.last?.aspect ?? .mind
        case .about: .body
        case .connect: .heart
        case .ready: todayAction.aspect
        }
    }

    /// On the last screen the orb carries the move Today will open on, so
    /// entering the app changes nothing about it.
    private var orbLabel: LocalizedStringResource? {
        model.step == .ready ? todayAction.label : nil
    }

    private var todayAction: PulseNowAction {
        PulseNowAction.make(today: nil, at: Date())
    }

    @ViewBuilder
    private var page: some View {
        switch model.step {
        case .signIn: OnboardingSignInView(model: model)
        case .email: OnboardingEmailView(model: model)
        case .focus: OnboardingFocusView(model: model)
        case .about: OnboardingAboutView(model: model)
        case .connect: OnboardingConnectView(model: model)
        case .ready: OnboardingReadyView(model: model)
        }
    }

    /// The one Continue, in the same place on every screen. Sign in and the
    /// email branch carry their own choices instead.
    @ViewBuilder
    private var footer: some View {
        switch model.step {
        case .signIn:
            OnboardingSignInFooter(model: model)
        case .email:
            EmptyView()
        default:
            OnboardingFooter(
                primary: OnboardingButton(
                    model.step == .ready ? String(localized: "Enter") : String(localized: "Continue"),
                    isEnabled: model.canContinue
                ) { model.advance() }
            )
        }
    }

    /// A swipe from the leading edge goes back a screen, as a pushed page
    /// would.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let edge = theme.metrics.pagePadding * 2
                guard value.startLocation.x < edge,
                      value.translation.width > theme.metrics.iconButtonDiameter * 1.5,
                      abs(value.translation.height) < value.translation.width else { return }
                model.back()
            }
    }
}

#Preview("Onboarding") {
    OnboardingFlow(store: SomaProfileStore(url: nil)) {}
        .environment(HealthDashboard())
        .environment(AppRouter())
}

/// The one row Developer tools draws to replay the first run.
struct OnboardingReplayRow: Identifiable {
    var id: String { "replay" }
    let title = String(localized: "Replay onboarding")
    let symbol = "arrow.counterclockwise"
}
