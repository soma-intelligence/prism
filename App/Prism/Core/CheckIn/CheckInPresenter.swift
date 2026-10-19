//
//  CheckInPresenter.swift
//  Prism
//

import Foundation
import Observation
import UserNotifications

/// One run of "Soma asks": the questions picked when it opened, and how far
/// the person is through them.
@MainActor
@Observable
final class CheckInSession: Identifiable {
    let id = UUID()
    let window: CheckInWindow
    let questions: [CheckInQuestion]
    private(set) var index = 0
    /// What this run answered, in order, for Mind's one check-in at the end.
    @ObservationIgnored private(set) var answered: [(question: CheckInQuestion, answer: CheckInAnswer)] = []

    init(window: CheckInWindow, questions: [CheckInQuestion]) {
        self.window = window
        self.questions = questions
    }

    var current: CheckInQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    /// Past the last question: "Done for today".
    var isDone: Bool { index >= questions.count }

    /// How many are still to come after the current one.
    var waiting: Int { max(questions.count - index - 1, 0) }

    fileprivate func record(_ answer: CheckInAnswer, for question: CheckInQuestion) {
        answered.append((question, answer))
    }

    fileprivate func advance() {
        index = min(index + 1, questions.count)
    }
}

/// The way into "Soma asks", for the app and for any screen.
///
/// The shell opens it by itself once per window when the app becomes active
/// (``presentAutomatically()``), the morning and evening reminders open it
/// when tapped, and any screen may offer it:
///
/// ```swift
/// if CheckInPresenter.shared.hasQuestions {
///     Button("Answer") { CheckInPresenter.shared.present() }
/// }
/// ```
///
/// Nothing is asked outside the morning (05:00 to 12:00) and evening (18:00
/// to midnight) windows, a run never holds more than five questions, an
/// answered question is not asked again the same day, and Later puts the
/// window off for two hours without counting it as done.
@MainActor
@Observable
final class CheckInPresenter {
    static let shared = CheckInPresenter()

    /// The run on screen. The shell's sheet is bound to it.
    var session: CheckInSession?

    let store: CheckInStore
    @ObservationIgnored private weak var health: HealthDashboard?
    @ObservationIgnored private weak var journal: JournalStore?
    @ObservationIgnored private var isAttached = false
    /// Set by the first launch, so this run never opens a question by itself.
    @ObservationIgnored private var isFirstLaunch = false
    /// A reminder was tapped before the shell was on screen.
    @ObservationIgnored private var opensWhenAttached = false
    /// When the app was last opened from a notification: the automatic run
    /// stands aside for it.
    @ObservationIgnored private var openedFromNotificationAt: Date?
    /// Whether the run on screen has written its Mind check-in.
    @ObservationIgnored private var wroteMind = false
    @ObservationIgnored var now: () -> Date = Date.init

    /// How long after a notification was opened the automatic run waits.
    static let notificationQuiet: TimeInterval = 30

    /// - Parameter store: nil is the app's own record; tests pass one kept
    ///   in memory.
    init(store: CheckInStore? = nil) {
        self.store = store ?? .shared
    }

    private var calendar: Calendar { store.calendar }

    private var writer: CheckInWriter {
        CheckInWriter(journal: journal, calendar: calendar)
    }

    // MARK: Entry points

    /// Whether there is anything to ask right now. A screen shows its way in
    /// only when this is true.
    var hasQuestions: Bool { !questions(at: now()).isEmpty }

    /// Opens the run now, whatever the snooze says. Returns false outside the
    /// windows, once the window is done, or with nothing left to ask.
    @discardableResult
    func present() -> Bool {
        guard session == nil else { return true }
        return open(at: now())
    }

    /// The shell's call when the app becomes active: opens the run once per
    /// window, never on the first launch, never right after a notification
    /// opened the app, and not while a Later snooze runs.
    @discardableResult
    func presentAutomatically() -> Bool {
        let now = now()
        guard isAttached, !isFirstLaunch, session == nil else { return false }
        if let opened = openedFromNotificationAt, now.timeIntervalSince(opened) < Self.notificationQuiet { return false }
        guard CheckInEngine.shouldPresentAutomatically(now: now, calendar: calendar, record: store.record(on: now)) else {
            return false
        }
        return open(at: now)
    }

    /// A notification was opened. A check-in reminder opens the run; any
    /// notification keeps the automatic run from stacking on top of what it
    /// opened.
    func openFromNotification(identifier: String) {
        openedFromNotificationAt = now()
        guard Self.opens(identifier) else { return }
        if isAttached { present() } else { opensWhenAttached = true }
    }

    static func opens(_ identifier: String) -> Bool {
        identifier == ReminderPlan.Identifier.morning
            || identifier == ReminderPlan.Identifier.evening
            || identifier == CheckInReminder.identifier
    }

    /// Hands the presenter what it reads: the shell calls this once it is on
    /// screen.
    func attach(health: HealthDashboard?, journal: JournalStore?) {
        self.health = health
        self.journal = journal
        if !isAttached {
            isAttached = true
            isFirstLaunch = store.noteLaunch()
        }
        if opensWhenAttached {
            opensWhenAttached = false
            present()
        }
    }

    // MARK: Answering

    func answer(_ answer: CheckInAnswer) {
        guard let session, let question = session.current else { return }
        let now = now()
        store.update(on: now) { $0.answer(question, with: answer) }
        session.record(answer, for: question)
        writer.write(question, answer, answers: store.record(on: now).answers, now: now)
        session.advance()
        settleIfDone(session, now: now)
    }

    func skip() {
        guard let session, let question = session.current else { return }
        let now = now()
        store.update(on: now) { $0.skip(question) }
        session.advance()
        settleIfDone(session, now: now)
    }

    /// Puts the window off for two hours. Nothing is marked done: the run
    /// comes back on the first activation after the snooze, and a reminder
    /// brings it back if the window is still open by then.
    func later() {
        guard let session else { return }
        let now = now()
        store.update(on: now) { $0.snooze(session.window, at: now) }
        if let when = CheckInEngine.reminderDate(after: now, calendar: calendar), let next = session.current {
            Task { await CheckInReminder.schedule(at: when, asking: next.text) }
        }
        close()
    }

    /// The run is over or was put away: Mind gets its one check-in and the
    /// sheet goes.
    func close() {
        if let session, !wroteMind {
            wroteMind = true
            writer.writeMind(session.answered, now: now())
        }
        session = nil
    }

    // MARK: Picking

    func questions(at now: Date) -> [CheckInQuestion] {
        CheckInEngine.questions(
            now: now, calendar: calendar, record: store.record(on: now),
            signals: .from(health?.today), context: context(at: now)
        )
    }

    func context(at now: Date) -> CheckInContext {
        var context = CheckInContext()
        if let journal {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            context.offeredTags = Set(journal.offeredTags.map(\.id))
            context.tagsToday = journal.day(now).tags
            context.tagsYesterday = journal.day(yesterday).tags
            context.hasFeeling = journal.day(now).feeling != nil
        } else {
            // No Journal to write to: its feeling is not asked either.
            context.hasFeeling = true
        }
        context.hasWakeRating = TrackLogStore.shared.wakeRating(on: now) != nil
        let record = store.record(on: now)
        let answeredHomeHere = CheckInCatalog.all.contains { question in
            [.homeEnergy, .homeStress, .homeBody].contains(question.destination) && record.answers[question.id] != nil
        }
        context.homeCheckInElsewhere = HomeLog.shared.checkIn(on: now) != nil && !answeredHomeHere
        context.mindAvailable = MindStore.shared.consent.isGiven
        return context
    }

    private func open(at now: Date) -> Bool {
        guard let window = CheckInWindow.at(now, calendar: calendar) else { return false }
        let run = questions(at: now)
        guard !run.isEmpty else { return false }
        store.update(on: now) { $0.markPresented(window) }
        Task { await CheckInReminder.cancel() }
        wroteMind = false
        session = CheckInSession(window: window, questions: run)
        return true
    }

    private func settleIfDone(_ session: CheckInSession, now: Date) {
        guard session.isDone else { return }
        store.update(on: now) { $0.finish(session.window) }
    }
}

/// The one reminder Later leaves behind: the next question, two hours on.
enum CheckInReminder {
    static let identifier = "soma.checkin.later"

    static func schedule(at date: Date, asking question: String) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Soma asks")
        content.body = question
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 60), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Hears which notification opened the app and hands it to the presenter.
/// Installed at launch, before a cold start delivers the tap.
final class CheckInNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CheckInNotificationRouter()

    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            CheckInPresenter.shared.openFromNotification(identifier: identifier)
        }
    }

    /// While the app is open nothing is shown, as before there was a
    /// delegate: the reminders are for when it is not.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
