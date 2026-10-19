//
//  SomaShortcuts.swift
//  Prism
//

import AppIntents
import SwiftUI

/// The actions Soma offers to Siri, Spotlight and the Shortcuts app.
///
/// Only the simple ones the app wide controls expose: open Ask,
/// open the journal, and set your activity status. Opening a tab is handed to
/// the running shell through ``GlobalIntentInbox``; setting the status writes
/// to ``ActivityStatusStore`` directly and needs no screen.
struct SomaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAskIntent(),
            phrases: ["Ask \(.applicationName)", "Open \(.applicationName) Ask"],
            shortTitle: "Ask Soma",
            systemImageName: "bubble.left"
        )
        AppShortcut(
            intent: OpenJournalIntent(),
            phrases: ["Open my \(.applicationName) journal", "Log my day in \(.applicationName)"],
            shortTitle: "Open my journal",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SetActivityStatusIntent(),
            phrases: ["Set my \(.applicationName) status", "Change my activity status in \(.applicationName)"],
            shortTitle: "Set my activity status",
            systemImageName: "figure.run"
        )
    }
}

struct OpenAskIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Soma"
    static let description = IntentDescription("Opens Ask, ready for a question.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        GlobalIntentInbox.shared.tab = "ask"
        return .result()
    }
}

struct OpenJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Open my journal"
    static let description = IntentDescription("Opens Track, where the journal is kept.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        GlobalIntentInbox.shared.tab = "track"
        return .result()
    }
}

struct SetActivityStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Set my activity status"
    static let description = IntentDescription("Tells Soma how you are: training, resting, travelling or unwell.")

    @Parameter(title: "Status")
    var status: ActivityStatusEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let chosen = ActivityStatus(rawValue: status.rawValue) else { return .result(dialog: "Nothing changed.") }
        ActivityStatusStore.shared.set(chosen)
        return .result(dialog: "Soma now reads your days as \(chosen.title).")
    }
}

/// ``ActivityStatus`` as the Shortcuts app shows it.
enum ActivityStatusEntity: String, AppEnum {
    case training, resting, travelling, unwell

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Activity status"
    static let caseDisplayRepresentations: [ActivityStatusEntity: DisplayRepresentation] = [
        .training: "Training",
        .resting: "Resting",
        .travelling: "Travelling",
        .unwell: "Unwell",
    ]
}

/// A tab an intent asked for, waiting for the shell to show it.
@MainActor
@Observable
final class GlobalIntentInbox {
    static let shared = GlobalIntentInbox()
    var tab: String?
}

extension View {
    /// Lets an intent choose the tab: applied once, on the shell.
    func globalIntentRouting() -> some View {
        modifier(GlobalIntentRouting())
    }
}

private struct GlobalIntentRouting: ViewModifier {
    @Environment(AppRouter.self) private var router
    @State private var inbox = GlobalIntentInbox.shared

    func body(content: Content) -> some View {
        content.onChange(of: inbox.tab, initial: true) { _, tab in
            guard let tab else { return }
            router.selection = tab
            inbox.tab = nil
        }
    }
}
