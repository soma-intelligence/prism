//
//  SomaMotionGate.swift
//  SomaUI
//

import SwiftUI
import Observation

/// Whether the device is saving power, kept current while the app runs.
///
/// A looping animation that nobody asked for (the orb's weather, a page's
/// drifting backdrop) holds still in Low Power Mode, the way it holds still
/// with Reduce Motion on: the frames cost battery and carry no information.
@MainActor
@Observable
public final class SomaPowerState {
    /// The one reader, shared by every animated view.
    public static let shared = SomaPowerState()

    /// True while Low Power Mode is on.
    public private(set) var isLowPower: Bool

    private init() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        Task { [weak self] in
            let changes = NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange)
            for await _ in changes {
                guard let self else { return }
                let now = ProcessInfo.processInfo.isLowPowerModeEnabled
                if now != self.isLowPower { self.isLowPower = now }
            }
        }
    }
}

public extension View {
    /// Keeps `isOnScreen` true only while this view is in the window and
    /// inside the visible part of the scroll view that holds it.
    ///
    /// For a looping animation to pause on: a hidden tab, a pushed page and a
    /// card scrolled out of sight all stop drawing frames nobody sees.
    func somaOnScreen(_ isOnScreen: Binding<Bool>) -> some View {
        modifier(SomaOnScreen(isOnScreen: isOnScreen))
    }
}

private struct SomaOnScreen: ViewModifier {
    @Binding var isOnScreen: Bool

    @State private var isInWindow = true
    @State private var isInScrollView = true

    func body(content: Content) -> some View {
        content
            .onAppear {
                isInWindow = true
                publish()
            }
            .onDisappear {
                isInWindow = false
                publish()
            }
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                isInScrollView = visible
                publish()
            }
    }

    private func publish() {
        let now = isInWindow && isInScrollView
        if now != isOnScreen { isOnScreen = now }
    }
}
