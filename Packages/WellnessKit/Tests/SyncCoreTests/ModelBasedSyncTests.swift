import Foundation
import Testing
import SyncCore
import SyncTesting

/// Two devices of one user edit, delete, sync, crash and meet faults in a seeded
/// random order. After the faults stop and every backoff expires, both devices
/// must hold exactly the server's live records, with empty outboxes.
@Suite struct ModelBasedSyncTests {
    @Test func randomizedSequencesConverge() async throws {
        let environment = ProcessInfo.processInfo.environment
        let count = environment["WELLNESSKIT_MODEL_SEQUENCES"].flatMap { Int($0) } ?? 200
        let baseSeed = environment["WELLNESSKIT_MODEL_SEED"].flatMap { UInt64($0) } ?? 20_260_916
        for index in 0..<count {
            let seed = baseSeed &+ UInt64(index)
            if let failure = try await ModelRun(seed: seed).execute() {
                Issue.record("seed \(seed): \(failure)")
                return
            }
        }
    }
}

struct ModelRun {
    let seed: UInt64

    func execute() async throws -> String? {
        let random = SeededRandom(seed: seed)
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        let ids = (1...4).map { RecordID("n\($0)") }
        let pageSize = 1 + random.int(below: 3)
        let batchSize = 1 + random.int(below: 3)

        func open(_ index: Int) throws -> TestDevice {
            try TestDevice.open(
                directory: root.url.appendingPathComponent("device-\(index)"),
                remote: server,
                clock: clock,
                random: random,
                pushBatchSize: batchSize,
                pullPageSize: pageSize
            )
        }

        var devices = [try open(0), try open(1)]
        var trace: [String] = []
        let faults: [ScriptedRecordServer.Fault] = [
            .fail(.offline),
            .fail(.timeout),
            .fail(.transient(status: 503, retryAfter: nil)),
            .applyThenFail(.timeout),
        ]

        for step in 0..<(5 + random.int(below: 30)) {
            let index = random.int(below: 2)
            let device = devices[index]
            let id = ids[random.int(below: ids.count)]
            switch random.int(below: 10) {
            case 0, 1, 2:
                try await device.notes.save(TestNote(id: id, body: "device \(index) step \(step)", rating: random.int(below: 5)))
                trace.append("save d\(index) \(id)")
            case 3:
                try await device.notes.delete(id)
                trace.append("delete d\(index) \(id)")
            case 4, 5:
                _ = await device.agent.sync()
                trace.append("sync d\(index)")
            case 6:
                let fault = faults[random.int(below: faults.count)]
                await server.script([fault])
                trace.append("fault \(fault)")
            case 7:
                await device.close()
                devices[index] = try open(index)
                trace.append("reopen d\(index)")
            case 8:
                clock.advance(by: .seconds(Int64(random.int(below: 60))))
                trace.append("advance")
            default:
                await server.purgeTombstones(type: TestNote.recordType)
                trace.append("purge")
            }
        }

        await server.clearFaults()
        for _ in 0..<8 {
            clock.advance(by: .seconds(3_600))
            for device in devices {
                _ = await device.agent.sync()
            }
        }

        let serverRows = await server.liveRecords(type: TestNote.recordType)
        for (index, device) in devices.enumerated() {
            if try device.outboxCount() != 0 {
                return "device \(index) still has \(try device.outboxCount()) outbox entries (\(try device.frozenCount()) frozen). Trace: \(trace)"
            }
            if try device.quarantineCount() != 0 {
                return "device \(index) quarantined rows. Trace: \(trace)"
            }
            let rows = try device.liveRows()
            if rows != serverRows {
                return "device \(index) rows \(rows.keys.sorted()) differ from server \(serverRows.keys.sorted()). Trace: \(trace)"
            }
        }
        for device in devices {
            await device.close()
        }
        return nil
    }
}
