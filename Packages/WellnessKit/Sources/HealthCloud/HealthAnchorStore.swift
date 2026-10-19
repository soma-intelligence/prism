import Foundation
import SyncCore

/// How far one metric's upload has gone on this device.
public struct HealthMetricUploadState: Codable, Sendable, Hashable {
    /// The source's anchor after the last page the server confirmed.
    public var anchor: Data?
    /// Days whose samples changed but whose daily row is not confirmed yet,
    /// as `yyyy-MM-dd`. Kept so a failure between the samples and the daily
    /// row loses nothing.
    public var pendingDays: Set<String>
    /// Samples confirmed so far, every run counted.
    public var uploaded: Int
    public var lastSampleEnd: Date?
    public var lastError: String?

    public init(anchor: Data? = nil, pendingDays: Set<String> = [], uploaded: Int = 0, lastSampleEnd: Date? = nil, lastError: String? = nil) {
        self.anchor = anchor
        self.pendingDays = pendingDays
        self.uploaded = uploaded
        self.lastSampleEnd = lastSampleEnd
        self.lastError = lastError
    }
}

/// The pause after a failed run. Persisted, so a relaunch does not hammer a
/// server that just answered 503.
public struct HealthUploadBackoff: Codable, Sendable, Hashable {
    public var attempts: Int
    public var nextAttemptAt: Date?

    public init(attempts: Int = 0, nextAttemptAt: Date? = nil) {
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
    }
}

/// Where the anchors live. Written after every confirmed page.
public protocol HealthAnchorStore: Sendable {
    func state(for metric: String) async -> HealthMetricUploadState
    func save(_ state: HealthMetricUploadState, for metric: String) async throws
    func backoff() async -> HealthUploadBackoff
    func setBackoff(_ backoff: HealthUploadBackoff) async throws
    /// Forgets everything, for a sign out.
    func reset() async throws
}

/// Anchors in memory, for tests and previews.
public actor MemoryHealthAnchorStore: HealthAnchorStore {
    private var states: [String: HealthMetricUploadState] = [:]
    private var pause = HealthUploadBackoff()

    public init() {}

    public func state(for metric: String) -> HealthMetricUploadState { states[metric] ?? HealthMetricUploadState() }
    public func save(_ state: HealthMetricUploadState, for metric: String) { states[metric] = state }
    public func backoff() -> HealthUploadBackoff { pause }
    public func setBackoff(_ backoff: HealthUploadBackoff) { pause = backoff }
    public func reset() {
        states = [:]
        pause = HealthUploadBackoff()
    }
}

/// Anchors in one JSON file, written atomically with complete file protection
/// where the platform has it. One file per user: a second account on the
/// same phone starts from nothing.
public actor FileHealthAnchorStore: HealthAnchorStore {
    private struct Stored: Codable {
        var states: [String: HealthMetricUploadState] = [:]
        var backoff = HealthUploadBackoff()
    }

    public nonisolated let url: URL
    private var stored: Stored

    /// Reads `url` if it holds a store. A file that does not decode starts
    /// over: the uploads it describes are idempotent, so the cost is a resend.
    public init(url: URL) {
        self.url = url
        if let data = FileManager.default.contents(atPath: url.path) {
            do {
                stored = try JSONDecoder().decode(Stored.self, from: data)
            } catch {
                stored = Stored()
            }
        } else {
            stored = Stored()
        }
    }

    public func state(for metric: String) -> HealthMetricUploadState { stored.states[metric] ?? HealthMetricUploadState() }

    public func save(_ state: HealthMetricUploadState, for metric: String) throws {
        stored.states[metric] = state
        try write()
    }

    public func backoff() -> HealthUploadBackoff { stored.backoff }

    public func setBackoff(_ backoff: HealthUploadBackoff) throws {
        stored.backoff = backoff
        try write()
    }

    public func reset() throws {
        stored = Stored()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func write() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(stored)
        #if os(macOS)
        try data.write(to: url, options: .atomic)
        #else
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #endif
    }
}
