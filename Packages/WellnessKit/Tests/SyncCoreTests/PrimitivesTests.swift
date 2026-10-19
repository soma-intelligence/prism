import Foundation
import Testing
@testable import SyncCore
import SyncTesting

@Suite struct PrimitivesTests {
    @Test func uuidV7CarriesTimestampVersionAndVariant() {
        let id = UUIDv7Generator.make(milliseconds: 0x0123_4567_89AB, random: .max, random2: .max)
        #expect(id.count == 36)
        #expect(UUID(uuidString: id) != nil)
        let hex = Array(id.replacingOccurrences(of: "-", with: ""))
        #expect(String(hex[0..<12]) == "0123456789ab")
        #expect(hex[12] == "7")
        #expect(["8", "9", "a", "b"].contains(hex[16]))
    }

    @Test func uuidV7SortsByCreationTime() {
        let earlier = UUIDv7Generator.make(milliseconds: 1_000, random: .max, random2: .max)
        let later = UUIDv7Generator.make(milliseconds: 2_000, random: 0, random2: 0)
        #expect(earlier < later)
    }

    @Test func generatorProducesDistinctLowercaseIDs() {
        let generator = UUIDv7Generator(clock: ManualClock())
        let ids = (0..<100).map { _ in generator.next().rawValue }
        #expect(Set(ids).count == 100)
        #expect(ids.allSatisfy { $0 == $0.lowercased() })
    }

    @Test func instantArithmetic() {
        let start = Instant(millisecondsSinceEpoch: 1_000)
        #expect(start.adding(.seconds(2)).millisecondsSinceEpoch == 3_000)
        #expect(Instant(millisecondsSinceEpoch: 5_500) - start == .milliseconds(4_500))
        #expect(Duration.milliseconds(1_250).wholeMilliseconds == 1_250)
    }

    @Test func recordTypeAcceptsSnakeCaseOnly() {
        #expect(RecordType.isValid("food_log"))
        #expect(RecordType.isValid("a1"))
        #expect(!RecordType.isValid("Food"))
        #expect(!RecordType.isValid("1abc"))
        #expect(!RecordType.isValid("drop table"))
        #expect(!RecordType.isValid(""))
    }

    @Test func manualClockWakesSleepersWhenTimeReachesTheirDeadline() async throws {
        let clock = ManualClock()
        let start = clock.now()
        let sleeper = Task { try await clock.sleep(for: .seconds(10)) }
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .seconds(9))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(1))
        try await sleeper.value
        #expect(clock.now() == start.adding(.seconds(10)))
    }

    @Test func manualClockSleepThrowsWhenCancelled() async {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(10)) }
        #expect(await eventually { clock.sleeperCount == 1 })
        sleeper.cancel()
        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.sleeperCount == 0)
    }

    @Test func seededRandomIsDeterministic() {
        let first = SeededRandom(seed: 42)
        let second = SeededRandom(seed: 42)
        #expect((0..<5).map { _ in first.unitInterval() } == (0..<5).map { _ in second.unitInterval() })
        #expect((0..<100).allSatisfy { _ in (0..<1).contains(first.unitInterval()) })
    }

    @Test func sequentialIDsArePaddedAndOrdered() {
        let ids = SequentialIDs(prefix: "note")
        #expect(ids.next().rawValue == "note-000001")
        #expect(ids.next().rawValue == "note-000002")
    }
}
