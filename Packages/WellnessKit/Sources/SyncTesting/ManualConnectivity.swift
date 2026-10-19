import Foundation
import Synchronization
import SyncCore

/// Reachability a test switches by hand.
public final class ManualConnectivity: ConnectivityMonitor {
    private let continuations = Mutex<[AsyncStream<Bool>.Continuation]>([])

    public init() {}

    public func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        continuations.withLock { $0.append(continuation) }
        return stream
    }

    public func send(_ online: Bool) {
        for continuation in continuations.withLock({ $0 }) {
            continuation.yield(online)
        }
    }
}
