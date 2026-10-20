//
//  ScoreRoute.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The score pages: recovery, strain, stress, sleep, energy, weather and the peak window.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
enum ScoreRoute: Hashable {
    case recovery
    case strain
    case stress
    case sleep
    case energy
    case weather
    case peakWindow

    /// The score page an aspect of the Today page stands for.
    static func aspect(_ aspect: SomaAspect) -> ScoreRoute? {
        switch aspect {
        case .sleep: .sleep
        case .mind: .recovery
        case .activity: .strain
        case .heart, .gut, .body: nil
        }
    }

    var page: some View {
        content.notesVisit(topic)
    }

    /// What Explore reads this page as interest in, if anything.
    private var topic: ArticleTopic? {
        switch self {
        case .recovery, .energy: .recovery
        case .strain: .movement
        case .stress: .mind
        case .sleep: .sleep
        case .weather, .peakWindow: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self {
        case .recovery: RecoveryPage()
        case .strain: StrainPage()
        case .stress: StressPage()
        case .sleep: SleepPage()
        case .energy: EnergyPage()
        case .weather: WeatherPage()
        case .peakWindow: PeakWindowPage()
        }
    }
}

/// Reads the score pages' inputs when a page opens and on pull to refresh:
/// the scores through `HealthDashboard`, and the page's own parts alongside.
struct ScoreInputsLoader: ViewModifier {
    let parts: Set<ScoreDetailInputs.Part>
    @Binding var inputs: ScoreDetailInputs?

    @Environment(HealthDashboard.self) private var health

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Shown from the last read before anything is asked of
                // Health: the second visit to a page draws at once.
                if inputs == nil { inputs = ScoreInputsCache.shared.value(for: parts) }
            }
            .task { await load(force: false) }
            .refreshable { await load(force: true) }
    }

    private func load(force: Bool) async {
        if !force, ScoreInputsCache.shared.isFresh(parts) { return }
        async let scores: Void = health.loadScores(force: force)
        guard let source = await health.prepare(ScoreDetailInputs.metrics(for: parts)) else {
            await scores
            return
        }
        let read = await ScoreDetailInputs.read(parts, from: source, now: Date(), calendar: .current)
        await scores
        inputs = read
        ScoreInputsCache.shared.store(read, for: parts)
    }
}

/// The last read of each set of score inputs, kept for the life of the app.
///
/// A score page reads weeks of samples when it opens. The first visit may
/// take a moment; every later one draws the last read at once and only goes
/// back to Health once the read is older than ``freshFor``, or on a pull to
/// refresh.
@MainActor
final class ScoreInputsCache {
    static let shared = ScoreInputsCache()

    /// How long a read stands before a visit reads again in the background.
    static let freshFor: TimeInterval = 5 * 60

    private var entries: [Set<ScoreDetailInputs.Part>: (inputs: ScoreDetailInputs, read: Date)] = [:]

    func value(for parts: Set<ScoreDetailInputs.Part>) -> ScoreDetailInputs? {
        entries[parts]?.inputs
    }

    func isFresh(_ parts: Set<ScoreDetailInputs.Part>, now: Date = Date()) -> Bool {
        guard let read = entries[parts]?.read else { return false }
        return now.timeIntervalSince(read) < Self.freshFor
    }

    func store(_ inputs: ScoreDetailInputs, for parts: Set<ScoreDetailInputs.Part>, now: Date = Date()) {
        entries[parts] = (inputs, now)
    }
}

extension View {
    /// Reads `parts` into `inputs` when the page opens and on refresh.
    func scoreInputs(_ parts: Set<ScoreDetailInputs.Part>, into inputs: Binding<ScoreDetailInputs?>) -> some View {
        modifier(ScoreInputsLoader(parts: parts, inputs: inputs))
    }
}
