import Foundation
import Network

/// Network reachability as a stream. The first value is the current state.
public protocol ConnectivityMonitor: Sendable {
    func updates() -> AsyncStream<Bool>
}

public final class NetworkPathMonitor: ConnectivityMonitor {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "WellnessKit.connectivity"))
        }
    }
}

/// Decides when a session syncs: after local writes (debounced), when the app
/// becomes active, when the network returns, and when backed-off work is due.
public actor SyncScheduler {
    private let agent: SyncAgent
    private let uploads: UploadJournal
    private let store: LocalStore
    private let clock: any SyncClock
    private let debounce: Duration
    private var debounceTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var isShutDown = false
    public private(set) var runs = 0

    public init(agent: SyncAgent, uploads: UploadJournal, store: LocalStore, clock: any SyncClock, debounce: Duration) {
        self.agent = agent
        self.uploads = uploads
        self.store = store
        self.clock = clock
        self.debounce = debounce
    }

    public func localWriteHappened() {
        guard !isShutDown else { return }
        debounceTask?.cancel()
        let clock = self.clock
        let debounce = self.debounce
        debounceTask = Task {
            do {
                try await clock.sleep(for: debounce)
            } catch {
                return
            }
            await self.runNow()
        }
    }

    public func appDidBecomeActive() async {
        await runNow()
    }

    public func connectivityRestored() async {
        await runNow()
    }

    @discardableResult
    public func runNow() async -> SessionSyncReport {
        guard !isShutDown else {
            return SessionSyncReport(records: SyncReport(), uploads: UploadReport())
        }
        runs += 1
        let records = await agent.sync()
        let uploadReport = await uploads.send()
        await scheduleWake()
        return SessionSyncReport(records: records, uploads: uploadReport)
    }

    public func shutdown() {
        isShutDown = true
        debounceTask?.cancel()
        wakeTask?.cancel()
    }

    /// Schedules a run for the earliest backed-off entry that is due in the future.
    private func scheduleWake() async {
        guard !isShutDown else { return }
        let now = clock.now()
        let earliest: Int64?
        do {
            earliest = try store.read { context in
                let outbox = try context.query("SELECT MIN(next_attempt_at) AS due FROM sync_outbox WHERE frozen = 0", []).first?["due"].int64Value
                let journal = try context.query("SELECT MIN(next_attempt_at) AS due FROM upload_journal WHERE state = 'queued'", []).first?["due"].int64Value
                return [outbox, journal].compactMap { $0 }.min()
            }
        } catch {
            // The store reports its own failures to the host; without it there is nothing to wake for.
            return
        }
        guard var due = earliest else { return }
        if let open = await agent.circuitOpenUntil {
            due = max(due, open.millisecondsSinceEpoch)
        }
        guard due > now.millisecondsSinceEpoch else { return }
        wakeTask?.cancel()
        let delay = Duration.milliseconds(due - now.millisecondsSinceEpoch)
        let clock = self.clock
        wakeTask = Task {
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            await self.runNow()
        }
    }
}
