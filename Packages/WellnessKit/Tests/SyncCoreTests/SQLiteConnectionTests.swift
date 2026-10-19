import Foundation
import Testing
@testable import SyncCore
import SyncTesting

@Suite struct SQLiteConnectionTests {
    func open(_ directory: TemporaryDirectory) throws -> SQLiteConnection {
        try SQLiteConnection(path: directory.url.appendingPathComponent("test.sqlite").path)
    }

    @Test func roundTripsEveryValueType() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let db = try open(directory)
        try db.execute("CREATE TABLE t (i INTEGER, r REAL, s TEXT, b BLOB, n TEXT)")
        let changed = try db.run(
            "INSERT INTO t VALUES (?, ?, ?, ?, ?)",
            [.integer(Int64.max), .real(1.5), .text("héllo \u{1F600}"), .blob(Data([0, 1, 2])), .null]
        )
        #expect(changed == 1)
        let row = try #require(try db.query("SELECT * FROM t").first)
        #expect(row["i"] == .integer(Int64.max))
        #expect(row["r"] == .real(1.5))
        #expect(row["s"] == .text("héllo \u{1F600}"))
        #expect(row["b"] == .blob(Data([0, 1, 2])))
        #expect(row["n"] == .null)
        #expect(try row.int64("i") == Int64.max)
        #expect(try row.optionalString("n") == nil)
    }

    @Test func emptyBlobStaysAnEmptyBlob() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let db = try open(directory)
        try db.execute("CREATE TABLE t (b BLOB)")
        try db.run("INSERT INTO t VALUES (?)", [.blob(Data())])
        let row = try #require(try db.query("SELECT b, typeof(b) AS kind FROM t").first)
        #expect(row["kind"] == .text("blob"))
        #expect(try row.optionalData("b") == Data())
    }

    @Test func preparedStatementsAreReusedWithNewBindings() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let db = try open(directory)
        try db.execute("CREATE TABLE t (id INTEGER)")
        for value in 1...5 { try db.run("INSERT INTO t VALUES (?)", [.integer(Int64(value))]) }
        let sum = try db.query("SELECT SUM(id) AS total FROM t").first?["total"].int64Value
        #expect(sum == 15)
    }

    @Test func constraintViolationIsReported() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let db = try open(directory)
        try db.execute("CREATE TABLE t (id TEXT PRIMARY KEY)")
        try db.run("INSERT INTO t VALUES ('a')")
        let error = #expect(throws: SQLiteError.self) { try db.run("INSERT INTO t VALUES ('a')") }
        #expect(error?.isConstraintViolation == true)
        // The statement is usable again after the failure.
        try db.run("INSERT INTO t VALUES ('b')")
    }

    @Test func garbageFileIsReportedAsCorruption() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.url.appendingPathComponent("test.sqlite")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: path)
        let db = try SQLiteConnection(path: path.path)
        let error = #expect(throws: SQLiteError.self) { try db.execute("PRAGMA journal_mode=WAL") }
        #expect(error?.isCorruption == true)
    }

    @Test func closedConnectionThrowsInsteadOfCrashing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let db = try open(directory)
        db.close()
        #expect(throws: SQLiteError.self) { try db.query("SELECT 1") }
    }

    @Test func systemSQLiteProvidesFullTextSearch5() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let db = try open(directory)
        try db.execute("CREATE VIRTUAL TABLE docs USING fts5(body)")
        try db.run("INSERT INTO docs VALUES (?)", [.text("greek yogurt with honey")])
        #expect(try db.query("SELECT body FROM docs WHERE docs MATCH 'yogurt'").count == 1)
    }

    @Test func rowSerializesToJSONForQuarantine() throws {
        let row = Row(columns: ["id", "n", "b"], values: [.text("x"), .null, .blob(Data([255]))])
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(row.jsonString().utf8)) as? [String: Any]
        )
        #expect(object["id"] as? String == "x")
        #expect(object["n"] is NSNull)
        #expect(object["b"] as? String == "/w==")
    }
}
