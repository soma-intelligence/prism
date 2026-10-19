import Foundation
import SyncCore

/// The record type the foundation tests sync.
public struct TestNote: SyncRecord {
    public static let recordType = RecordType("test_note")

    public var id: RecordID
    public var body: String
    public var rating: Int

    public init(id: RecordID, body: String, rating: Int = 0) {
        self.id = id
        self.body = body
        self.rating = rating
    }
}

public enum TestSchema {
    public static let moduleName = "TestNotes"
    public static let recordTypes = [TestNote.recordType]

    /// Foundation tables followed by the test note table.
    public static let migrations: [Migration] = CoreSchema.migrations + [
        Migration(module: moduleName, version: 1, sql: SyncTable.createStatement(for: TestNote.recordType)),
    ]

    public static func openStore(
        at directory: URL,
        clock: any SyncClock,
        changes: ChangeBroadcaster = ChangeBroadcaster(),
        observer: (any TransactionObserver)? = nil
    ) throws -> LocalStore {
        try LocalStore(directory: directory, migrations: migrations, clock: clock, changes: changes, observer: observer)
    }
}
