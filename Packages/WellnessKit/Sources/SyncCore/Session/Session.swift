import CryptoKit
import Foundation
import os
import Synchronization

/// What a kit brings to a session: its migrations, its record types and their conflict rules.
public struct SchemaModule: Sendable {
    public let name: String
    public let migrations: [Migration]
    public let recordTypes: [RecordType]
    public let conflictRules: [RecordType: any ConflictRule]

    public init(name: String, migrations: [Migration], recordTypes: [RecordType], conflictRules: [RecordType: any ConflictRule] = [:]) {
        self.name = name
        self.migrations = migrations
        self.recordTypes = recordTypes
        self.conflictRules = conflictRules
    }
}

public struct WellnessEnvironment: Sendable {
    public var userID: UserID
    public var tokens: any AccessTokenProvider
    public var records: any RemoteRecordStore
    public var objects: any RemoteObjectStore
    public var clock: any SyncClock
    public var ids: any IDGenerator
    public var random: any RandomSource
    public var connectivity: any ConnectivityMonitor
    public var rootDirectory: URL
    public var logSubsystem: String
    public var retryPolicy: RetryPolicy
    public var uploadCapBytes: Int64
    public var syncDebounce: Duration
    public var transactionObserver: (any TransactionObserver)?

    public init(
        userID: UserID,
        tokens: any AccessTokenProvider,
        records: any RemoteRecordStore,
        objects: any RemoteObjectStore,
        clock: any SyncClock = SystemClock(),
        ids: any IDGenerator = UUIDv7Generator(),
        random: any RandomSource = SystemRandomSource(),
        connectivity: any ConnectivityMonitor = NetworkPathMonitor(),
        rootDirectory: URL = WellnessEnvironment.defaultRootDirectory,
        logSubsystem: String = "WellnessKit",
        retryPolicy: RetryPolicy = .standard,
        uploadCapBytes: Int64 = 200_000_000,
        syncDebounce: Duration = .seconds(2),
        transactionObserver: (any TransactionObserver)? = nil
    ) {
        self.userID = userID
        self.tokens = tokens
        self.records = records
        self.objects = objects
        self.clock = clock
        self.ids = ids
        self.random = random
        self.connectivity = connectivity
        self.rootDirectory = rootDirectory
        self.logSubsystem = logSubsystem
        self.retryPolicy = retryPolicy
        self.uploadCapBytes = uploadCapBytes
        self.syncDebounce = syncDebounce
        self.transactionObserver = transactionObserver
    }

    public static var defaultRootDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "WellnessKit", directoryHint: .isDirectory)
    }
}

public enum SessionError: Error, Sendable, Hashable {
    case alreadyOpen(userID: UserID)
    case cannotLock(path: String, code: Int32)
    case storeUnavailable(StoreError)
}

public struct SessionSyncReport: Sendable, Hashable {
    public var records: SyncReport
    public var uploads: UploadReport

    public init(records: SyncReport, uploads: UploadReport) {
        self.records = records
        self.uploads = uploads
    }
}

/// An exclusive lock on a user's directory, held for the life of a session.
final class SessionLock: Sendable {
    private let descriptor: Int32
    private let released = Atomic<Bool>(false)

    init(directory: URL, userID: UserID) throws(SessionError) {
        let path = directory.appendingPathComponent("session.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .cannotLock(path: path, code: errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw .alreadyOpen(userID: userID)
        }
        self.descriptor = descriptor
    }

    func release() {
        guard released.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).exchanged else { return }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

extension Change {
    var isRecordChange: Bool {
        switch self {
        case .recordSaved, .recordDeleted: return true
        default: return false
        }
    }
}

/// Everything one signed-in user needs: one database, one sync agent, one upload journal.
public final class WellnessSession: Sendable {
    public let userID: UserID
    public let environment: WellnessEnvironment
    public let directory: URL
    public let store: LocalStore
    public let agent: SyncAgent
    public let uploads: UploadJournal
    public let scheduler: SyncScheduler
    private let broadcaster: ChangeBroadcaster
    private let lock: SessionLock
    private let observers = Mutex<[Task<Void, Never>]>([])

    private init(
        environment: WellnessEnvironment,
        directory: URL,
        store: LocalStore,
        agent: SyncAgent,
        uploads: UploadJournal,
        scheduler: SyncScheduler,
        broadcaster: ChangeBroadcaster,
        lock: SessionLock
    ) {
        self.userID = environment.userID
        self.environment = environment
        self.directory = directory
        self.store = store
        self.agent = agent
        self.uploads = uploads
        self.scheduler = scheduler
        self.broadcaster = broadcaster
        self.lock = lock
    }

    public static func open(_ environment: WellnessEnvironment, modules: [SchemaModule]) async throws -> WellnessSession {
        let directory = environment.rootDirectory.appendingPathComponent(directoryName(for: environment.userID), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: LocalStore.protectionAttributes)
        let lock = try SessionLock(directory: directory, userID: environment.userID)
        do {
            let broadcaster = ChangeBroadcaster()
            let store = try LocalStore(
                directory: directory,
                migrations: CoreSchema.migrations + modules.flatMap(\.migrations),
                clock: environment.clock,
                changes: broadcaster,
                observer: environment.transactionObserver,
                logger: Logger(subsystem: environment.logSubsystem, category: "store")
            )
            if case .failed(let error) = await store.state {
                throw SessionError.storeUnavailable(error)
            }
            let gate = TokenGate(provider: environment.tokens, userID: environment.userID, clock: environment.clock)
            var rules: [RecordType: any ConflictRule] = [:]
            for module in modules {
                rules.merge(module.conflictRules) { first, _ in first }
            }
            let agent = SyncAgent(
                store: store,
                remote: environment.records,
                tokens: gate,
                recordTypes: modules.flatMap(\.recordTypes),
                policy: environment.retryPolicy,
                clock: environment.clock,
                random: environment.random,
                changes: broadcaster,
                conflictRules: rules
            )
            let uploads = try UploadJournal(
                store: store,
                directory: directory.appendingPathComponent("outgoing", isDirectory: true),
                remote: environment.objects,
                tokens: gate,
                policy: environment.retryPolicy,
                clock: environment.clock,
                random: environment.random,
                changes: broadcaster,
                capBytes: environment.uploadCapBytes,
                logger: Logger(subsystem: environment.logSubsystem, category: "uploads")
            )
            _ = try await uploads.removeOrphans()
            let scheduler = SyncScheduler(agent: agent, uploads: uploads, store: store, clock: environment.clock, debounce: environment.syncDebounce)
            let session = WellnessSession(
                environment: environment,
                directory: directory,
                store: store,
                agent: agent,
                uploads: uploads,
                scheduler: scheduler,
                broadcaster: broadcaster,
                lock: lock
            )
            session.startObserving()
            return session
        } catch {
            lock.release()
            throw error
        }
    }

    public var ids: any IDGenerator { environment.ids }

    /// A new stream of every change batch published from now on.
    public var changes: AsyncStream<ChangeBatch> { broadcaster.stream() }

    public func repository<Record: SyncRecord>(for type: Record.Type) -> RecordRepository<Record> {
        RecordRepository(store: store)
    }

    @discardableResult
    public func syncNow() async -> SessionSyncReport {
        await scheduler.runNow()
    }

    public func appDidBecomeActive() async {
        await scheduler.appDidBecomeActive()
    }

    /// Makes every frozen outbox entry due again, for example after an app update.
    public func retryFrozen() async throws {
        try await store.write(label: TransactionLabel.outboxRetryFrozen) { transaction in
            try transaction.run(
                "UPDATE sync_outbox SET frozen = 0, attempts = 0, next_attempt_at = ?, last_error = NULL WHERE frozen = 1",
                [.integer(transaction.now.millisecondsSinceEpoch)]
            )
        }
    }

    public func close() async {
        let tasks = observers.withLock { tasks -> [Task<Void, Never>] in
            let all = tasks
            tasks.removeAll()
            return all
        }
        for task in tasks { task.cancel() }
        await scheduler.shutdown()
        broadcaster.finish()
        await store.close()
        lock.release()
    }

    /// Deletes everything stored locally for `userID`. Refuses while a session is open.
    public static func eraseLocalData(userID: UserID, rootDirectory: URL = WellnessEnvironment.defaultRootDirectory) throws {
        let directory = rootDirectory.appendingPathComponent(directoryName(for: userID), isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let lock = try SessionLock(directory: directory, userID: userID)
        do {
            for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where item.lastPathComponent != "session.lock" {
                try FileManager.default.removeItem(at: item)
            }
        } catch {
            lock.release()
            throw error
        }
        lock.release()
        try FileManager.default.removeItem(at: directory)
    }

    /// The user's directory name: the id itself when it is a plain token, a hash otherwise.
    public static func directoryName(for userID: UserID) -> String {
        let raw = userID.rawValue
        let plain = !raw.isEmpty && raw.count <= 64 && raw.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_"
        }
        if plain { return raw }
        return "u-" + SHA256.hash(data: Data(raw.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func startObserving() {
        let scheduler = self.scheduler
        let localWrites = broadcaster.stream()
        let writes = Task {
            for await batch in localWrites where batch.origin == .local && batch.changes.contains(where: \.isRecordChange) {
                await scheduler.localWriteHappened()
            }
        }
        let connectivityUpdates = environment.connectivity.updates()
        let network = Task {
            var wasOnline = true
            for await online in connectivityUpdates {
                if online && !wasOnline {
                    await scheduler.connectivityRestored()
                }
                wasOnline = online
            }
        }
        observers.withLock { $0 = [writes, network] }
    }
}
