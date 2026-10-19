import CryptoKit
import Foundation
import SyncCore

/// Object storage in memory, with scriptable failures.
public actor InMemoryObjectStore: RemoteObjectStore {
    public private(set) var objects: [String: Data] = [:]
    public private(set) var putCalls: [String] = []
    private var faults: [RemoteError] = []
    private var failingKeys: [String: RemoteError] = [:]

    public init() {}

    public func script(_ faults: [RemoteError]) {
        self.faults.append(contentsOf: faults)
    }

    public func fail(key: String, with error: RemoteError) {
        failingKeys[key] = error
    }

    public func clearFailures() {
        failingKeys.removeAll()
        faults.removeAll()
    }

    public func put(key: String, file: URL, sha256: String, contentType: String, token: AccessToken) async throws(RemoteError) {
        putCalls.append(key)
        if let error = failingKeys[key] { throw error }
        if !faults.isEmpty { throw faults.removeFirst() }
        do {
            objects[key] = try Data(contentsOf: file)
        } catch {
            throw .rejected(status: 0, reason: "cannot read \(file.path)")
        }
    }
}

/// Object storage in a directory, so it survives a process that is killed.
public struct DirectoryObjectStore: RemoteObjectStore {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func put(key: String, file: URL, sha256: String, contentType: String, token: AccessToken) async throws(RemoteError) {
        do {
            let data = try Data(contentsOf: file)
            let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            throw .transient(status: nil, retryAfter: nil)
        }
    }

    public func objectCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).count
    }
}
