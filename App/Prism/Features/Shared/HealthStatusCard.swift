//
//  HealthStatusCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Says where the numbers come from, and why they are dashes when they are.
///
/// A dashboard that shows nothing and explains nothing is indistinguishable
/// from a broken one, so the state is always stated.
struct HealthStatusCard: View {
    @Environment(HealthDashboard.self) private var health

    var body: some View {
        switch health.status {
        case .idle, .loading:
            NoteCard(title: "Reading Apple Health", message: "Asking Apple Health for what it holds. This takes a moment the first time.")
        case .ready:
            NoteCard(
                title: "Read from Apple Health",
                message: "A dash means the store holds nothing for that metric: not that the value is zero. Pull down to read again."
            )
        case .unavailable:
            NoteCard(
                title: "No Health store here",
                message: "This device has no Apple Health. The same pages read real values on iPhone and iPad."
            )
        case .failed(let message):
            StateNote(
                symbol: "heart.text.square",
                title: HealthProblemWords.title,
                message: HealthProblemWords.message(detail: message),
                actionTitle: "Try again"
            ) {
                Task { await health.retry() }
            }
        }
    }
}
