//
//  CloudMirror.swift
//  Prism
//

import Foundation
import SyncCore

/// Saves into SyncCore's outbox whatever changed in a snapshot since the last
/// pass, and deletes what this phone pushed before and no longer holds.
///
/// Saving is by difference: a record equal to the one already in the local
/// sync database is left alone, so a pass over an unchanged store writes
/// nothing and pushes nothing. Deleting is by memory: only ids this phone
/// mirrored itself are ever deleted, so a new phone that pulled a person's
/// history from the server (and holds none of it in its own stores yet)
/// never deletes it.
actor CloudMirror {
    private let session: WellnessSession
    private let knownURL: URL
    private var known: [String: Set<String>]

    init(session: WellnessSession) {
        self.session = session
        self.knownURL = session.directory.appending(path: "mirrored-ids.json")
        if let data = FileManager.default.contents(atPath: knownURL.path),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            known = decoded
        } else {
            known = [:]
        }
    }

    /// Mirrors one record type. Returns how many records were saved or deleted.
    @discardableResult
    func mirror<Record: SyncRecord>(_ records: [Record]) async throws -> Int {
        let repository = session.repository(for: Record.self)
        let stored = try await repository.fetchAll()
        var current: [RecordID: RecordPayload] = [:]
        for record in stored {
            current[record.id] = try RecordPayload(encoding: record)
        }
        var changed: [Record] = []
        var ids = Set<String>()
        for record in records {
            ids.insert(record.id.rawValue)
            let payload = try RecordPayload(encoding: record)
            if current[record.id] != payload { changed.append(record) }
        }
        try await repository.save(changed)

        let type = Record.recordType.rawValue
        let gone = (known[type] ?? []).subtracting(ids)
        for id in gone where current[RecordID(id)] != nil {
            try await repository.delete(RecordID(id))
        }
        known[type] = ids
        try persist()
        return changed.count + gone.count
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(known)
        try data.write(to: knownURL, options: CloudFiles.writeOptions)
    }
}
