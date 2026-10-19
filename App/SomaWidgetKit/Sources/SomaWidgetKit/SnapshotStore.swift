import Foundation

/// Reads and writes the widget snapshot as `snapshot.json` in a shared directory.
public struct SnapshotStore: Sendable {
    public static let appGroup = "group.Soma.Prism"

    private static let fileName = "snapshot.json"

    private let directory: URL

    /// Tests pass a temp directory.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group container, or nil when it is missing. Always nil off
    /// iOS: widgets ship on iOS only, and on macOS `containerURL` returns a
    /// path even without the entitlement.
    public static var shared: SnapshotStore? {
        #if os(iOS)
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map(SnapshotStore.init(directory:))
        #else
        nil
        #endif
    }

    private var fileURL: URL { directory.appending(path: Self.fileName) }

    public func read() -> SomaWidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SomaWidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: SomaWidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        // The widget reads while the phone is locked.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }
}
