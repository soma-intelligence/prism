import Foundation
import Testing
import SyncCore
import SyncTesting

@Suite struct PerformanceTests {
    @Test func reopeningASessionTakesLessThanFiftyMilliseconds() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        func environment() -> WellnessEnvironment {
            WellnessEnvironment(
                userID: UserID("user-a"),
                tokens: ScriptedTokenProvider(userID: UserID("user-a")),
                records: ScriptedRecordServer(),
                objects: InMemoryObjectStore(),
                clock: ManualClock(),
                random: FixedRandom(0.5),
                connectivity: ManualConnectivity(),
                rootDirectory: root.url
            )
        }
        let seeded = try await WellnessSession.open(environment(), modules: [WellnessSessionTests.notesModule])
        try await seeded.repository(for: TestNote.self).save((0..<500).map { TestNote(id: RecordID("n\($0)"), body: "note \($0)") })
        await seeded.close()

        var samples: [Duration] = []
        for _ in 0..<5 {
            let started = ContinuousClock.now
            let session = try await WellnessSession.open(environment(), modules: [WellnessSessionTests.notesModule])
            samples.append(ContinuousClock.now - started)
            await session.close()
        }

        let median = samples.sorted()[samples.count / 2]
        #expect(median < .milliseconds(50), "median \(median), samples \(samples)")
    }
}
