import Foundation

/// One drink logged from a widget, waiting for Prism to drain it.
public struct LogItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case water, coffee }

    public var id: UUID
    public var kind: Kind
    public var ml: Double
    public var date: Date

    public init(id: UUID = UUID(), kind: Kind, ml: Double, date: Date) {
        self.id = id
        self.kind = kind
        self.ml = ml
        self.date = date
    }
}

/// Small items the widget intents append to `log-inbox.json` in the App Group.
/// `TrackLogStore` lives in the Prism target and cannot be linked into the
/// extension, so Prism drains this file instead.
public struct LogInbox: Sendable {
    /// Default size of one drink, used by the widget buttons.
    public static let defaultMl: Double = 250
    /// Caffeine of one coffee per 250 ml, same rate Prism uses on drain.
    public static let caffeineMgPer250Ml: Double = 80
    /// Volume the caffeine rate refers to. Independent of `defaultMl`.
    public static let caffeineReferenceMl: Double = 250

    private static let fileName = "log-inbox.json"

    private let directory: URL

    /// Tests pass a temp directory.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group container, or nil when it is missing. Always nil off
    /// iOS, like `SnapshotStore.shared`.
    public static var shared: LogInbox? {
        #if os(iOS)
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SnapshotStore.appGroup)
            .map(LogInbox.init(directory:))
        #else
        nil
        #endif
    }

    private var fileURL: URL { directory.appending(path: Self.fileName) }

    public func pending() -> [LogItem] {
        var items: [LogItem] = []
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &error) { url in
            items = (try? Self.load(url)) ?? []
        }
        return items
    }

    public func append(_ item: LogItem) throws {
        try modify { $0.append(item) }
    }

    /// Drops items by id, after Prism drained them.
    public func remove(ids: Set<UUID>) throws {
        try modify { $0.removeAll { ids.contains($0.id) } }
    }

    /// Read, change and write under one coordinated write, so the app and the
    /// extension never interleave.
    private func modify(_ change: (inout [LogItem]) -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            do {
                // Missing file starts empty. A read error throws and leaves
                // the file alone. Content that does not decode (corrupt, or
                // written by a newer build) is set aside under a name of its
                // own, never overwritten, and the inbox starts again: one bad
                // file must not stop logging for good.
                var items: [LogItem]
                do {
                    items = try Self.load(url)
                } catch is DecodingError {
                    try Self.setAside(url)
                    items = []
                }
                change(&items)
                let data = try JSONEncoder().encode(items)
                #if os(iOS)
                // Widgets log while the phone is locked.
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try data.write(to: url, options: [.atomic])
                #endif
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// Moves an undecodable inbox to `log-inbox.corrupt-<milliseconds>.json`
    /// beside it.
    private static func setAside(_ url: URL) throws {
        let stamp = Int((Date().timeIntervalSince1970 * 1000).rounded())
        var target = url.deletingLastPathComponent().appending(path: "log-inbox.corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: target.path) {
            target = url.deletingLastPathComponent().appending(path: "log-inbox.corrupt-\(stamp)-\(UUID().uuidString).json")
        }
        try FileManager.default.moveItem(at: url, to: target)
    }

    /// Missing file is an empty inbox. Any other failure throws.
    private static func load(_ url: URL) throws -> [LogItem] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        return try JSONDecoder().decode([LogItem].self, from: data)
    }
}

public extension SomaWidgetSnapshot.Tally {
    /// The tally the widget shows: the snapshot's own plus pending items of the
    /// same day not yet drained. Items whose id is in `countedIDs` are already
    /// in the counts and are skipped. A tally from another day starts empty and
    /// keeps only its water goal. An item listed twice in the inbox counts
    /// once.
    func adding(_ pending: [LogItem], day: String, calendar: Calendar) -> Self {
        var result = self
        if self.day != day {
            result = .empty(day: day)
            result.waterGoalMl = waterGoalMl
        }
        var seen = result.countedIDs
        for item in pending
            where Self.dayString(item.date, calendar: calendar) == day && seen.insert(item.id).inserted
        {
            switch item.kind {
            case .water:
                result.waterMl += item.ml
            case .coffee:
                // Poured counts as water too, like the app's own total.
                result.waterMl += item.ml
                result.caffeineMg += item.ml / LogInbox.caffeineReferenceMl * LogInbox.caffeineMgPer250Ml
            }
        }
        return result
    }

    /// "yyyy-MM-dd" in the given calendar, the format of `Tally.day`.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
