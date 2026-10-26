//
//  OnboardingSignIn.swift
//  Prism
//

import SwiftUI
import SomaUI
import AuthenticationServices

// MARK: - Ways in

/// One way to get past the first screen.
enum OnboardingSignInWay: Equatable, Sendable {
    case apple
    case email
    case notNow
}

/// Which ways in the first screen offers.
///
/// Email and password sign in is drawn and wired (``OnboardingEmailView``,
/// ``OnboardingRecoveryView``, the `.email` step) but there is no account
/// service behind it: it can only say "Accounts aren't connected yet". It is
/// off until accounts support it. Turning ``offersEmail`` on brings back the
/// button, the screen and the step together; nothing else changes.
enum OnboardingSignInOptions {
    /// Whether the email and password path is offered. Off: see the type.
    static let offersEmail = false

    /// The ways in, top to bottom. Apple and "Not now" are always there.
    static func ways(offersEmail: Bool = OnboardingSignInOptions.offersEmail) -> [OnboardingSignInWay] {
        [.apple] + (offersEmail ? [.email] : []) + [.notNow]
    }
}

// MARK: - Sign in

/// The first screen: the orb large in the middle, one line under it, and the
/// ways in at the foot. There is no launch screen before it: a pause put in on
/// purpose is time the person waits for nothing.
struct OnboardingSignInView: View {
    let model: OnboardingModel

    @Environment(\.somaTheme) private var theme

    var body: some View {
        // What the app gives, before anything is asked of anyone: the value
        // first, the account second, and "Not now" always there.
        OnboardingPage(title: String(localized: "How you slept, and what today can take."), centred: true) {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing * 2) {
                OnboardingValueLine(symbol: "moon", text: String(localized: "Last night against your own sleep need"))
                OnboardingValueLine(symbol: "heart", text: String(localized: "Your heart overnight: resting rate, HRV, breathing"))
                OnboardingValueLine(symbol: "clock", text: String(localized: "Today's plan: when to focus, last coffee, bedtime"))
            }
            .onboardingArrival(1)
            if let failure = model.signInFailure {
                OnboardingNote(symbol: "info.circle", title: String(localized: "Not signed in"), detail: failure)
                    .onboardingArrival(2)
            }
        }
    }
}

/// One thing Soma reads for you, said in a line with its glyph.
private struct OnboardingValueLine: View {
    let symbol: String
    let text: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.cardHeaderSpacing * 2) {
            Image(systemName: symbol)
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(width: theme.metrics.browseGlyphColumn, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// How to sign in: Apple, or an email, or not now.
///
/// Sign in with Apple is real (AuthenticationServices): it goes through
/// Supabase Auth when the build has a Supabase project, and otherwise keeps
/// the identifier it hands back on this device. The email path is hidden
/// until accounts support it. Google is left out until there is an SDK behind
/// it: a button that does nothing is worse than no button.
struct OnboardingSignInFooter: View {
    let model: OnboardingModel

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let metrics = theme.metrics

        VStack(spacing: theme.metrics.spaceM) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
                AccountSession.shared.prepare(request)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: metrics.minimumTapTarget + 4)
            .clipShape(.capsule)
            .onboardingArrival(1)

            if OnboardingSignInOptions.ways().contains(.email) {
                OnboardingOutlineButton(action: { model.go(to: .email) }) {
                    Label("Continue with email", systemImage: "envelope")
                }
                .onboardingArrival(2)
            }

            OnboardingQuietButton(button: OnboardingButton(String(localized: "Not now")) { model.advance() })
                .onboardingArrival(3)

            Text("By continuing you agree to Soma’s Terms of Use and Privacy Policy.")
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .multilineTextAlignment(.center)
                .onboardingArrival(3)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, theme.metrics.spaceS)
        .padding(.bottom, theme.metrics.spaceM)
        .frame(maxWidth: metrics.pageMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            AccountSession.shared.continueWithApple(authorization)
            model.update { profile in
                profile.appleUserID = credential.user
                // Apple shares the name and email on the first sign in only;
                // a later one leaves what was kept.
                if let given = credential.fullName?.givenName, !given.isEmpty { profile.name = given }
                if let email = credential.email { profile.email = email }
            }
            if let given = credential.fullName?.givenName, !given.isEmpty { model.name = given }
            model.signInFailure = nil
            model.advance()
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            model.signInFailure = String(localized: "Sign in with Apple isn’t set up for this build. Your answers stay on this phone.")
        }
    }
}

// MARK: - Email

/// The email route: one screen that would create an account for a new
/// address and sign in a known one.
///
/// There is no account service behind it yet, so Continue says so and nothing
/// is sent or kept: not the address, never the password.
struct OnboardingEmailView: View {
    let model: OnboardingModel

    @Environment(\.somaTheme) private var theme
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isRecovering = false
    @State private var triedToContinue = false
    @FocusState private var focused: Bool

    private var isComplete: Bool {
        email.contains("@") && email.contains(".") && password.count >= 8
    }

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography

        VStack(spacing: 0) {
            OnboardingPage(title: String(localized: "Continue with email")) {
                VStack(spacing: 0) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focused)
#if os(iOS) || os(visionOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
#endif
                        .padding(metrics.cardPadding)
                    Rectangle()
                        .fill(colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity))
                        .frame(height: 0.5)
                        .padding(.horizontal, metrics.cardPadding)
                    HStack {
                        Group {
                            if showsPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        Button(showsPassword ? "Hide" : "Show") { showsPassword.toggle() }
                            .buttonStyle(.plain)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .padding(metrics.cardPadding)
                }
                .somaFont(type.callout)
                .foregroundStyle(colors.inkPrimary.color)
                .background(
                    RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                        .fill(colors.surface.color)
                )
                .onboardingArrival(1)

                HStack {
                    Spacer()
                    Button("Forgot your password?") { isRecovering = true }
                        .buttonStyle(.plain)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                .onboardingArrival(2)

                if triedToContinue {
                    OnboardingNote(
                        symbol: "info.circle",
                        title: String(localized: "Accounts aren’t connected yet."),
                        detail: String(localized: "Nothing was sent. Your answers stay on this phone.")
                    )
                    .transition(.opacity)
                }
            }

            OnboardingFooter(
                primary: triedToContinue
                    ? OnboardingButton(String(localized: "Continue without an account")) { model.advance() }
                    : OnboardingButton(String(localized: "Continue"), isEnabled: isComplete) {
                        password = ""
                        triedToContinue = true
                    }
            )
        }
        .animation(theme.motion.onboardingStep, value: triedToContinue)
        .onAppear { focused = true }
        .onboardingCover(isPresented: $isRecovering) {
            OnboardingRecoveryView(email: email)
        }
    }
}

// MARK: - Password recovery

/// Reset your password: the address the link goes to, and one action.
struct OnboardingRecoveryView: View {
    @State var email: String

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var tried = false

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(spacing: 0) {
            HStack {
                SomaIconButton(symbol: "xmark", accessibilityLabel: "Close") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, metrics.spaceM)
            .padding(.top, theme.metrics.spaceS)

            SomaPageScroll {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Reset your password.")
                        .somaFont(theme.typography.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, metrics.leadSpacing)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
#if os(iOS) || os(visionOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
#endif
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                        .padding(metrics.cardPadding)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                                .fill(colors.surface.color)
                        )
                        .padding(.top, metrics.leadSpacing)

                    if tried {
                        OnboardingNote(
                            symbol: "info.circle",
                            title: String(localized: "No link was sent."),
                            detail: String(localized: "Accounts aren’t connected yet, so there is no password to reset.")
                        )
                        .padding(.top, metrics.leadSpacing)
                    }
                }
                .padding(.horizontal, metrics.pagePadding)
                .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .softScrollEdges()

            OnboardingFooter(
                primary: OnboardingButton(String(localized: "Send the link"), isEnabled: email.contains("@")) { tried = true }
            )
        }
        .background(colors.canvas.color.ignoresSafeArea())
    }
}

extension View {
    /// A full screen cover where the platform has one, a sheet on the Mac,
    /// which has none.
    @ViewBuilder
    func onboardingCover<Cover: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Cover) -> some View {
#if os(macOS)
        sheet(isPresented: isPresented) { content().frame(minWidth: 480, minHeight: 560) }
#else
        fullScreenCover(isPresented: isPresented, content: content)
#endif
    }
}
