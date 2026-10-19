//
//  AskAndExportTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Ask client and data export")
struct AskAndExportTests {
    @Test("Server-sent events read as deltas, done and errors")
    func events() {
        #expect(AskClient.event(#"data: {"delta":"You slept "}"#) == .delta("You slept "))
        #expect(AskClient.event(#"data: {"done":true,"conversation_id":"x"}"#) == .done)
        #expect(AskClient.event(#"data: {"error":"the answer stopped halfway"}"#) == .error("the answer stopped halfway"))
        #expect(AskClient.event("") == nil)
        #expect(AskClient.event(": keep-alive") == nil)
    }

    @Test("Statuses map to what the screen can say")
    func failures() {
        #expect(AskClient.failure(status: 429, body: Data(#"{"error":"60 this hour"}"#.utf8)) == .rateLimited("60 this hour"))
        #expect(AskClient.failure(status: 401, body: Data()) == .signedOut)
        #expect(AskClient.failure(status: 502, body: Data(#"{"error":"busy"}"#.utf8)) == .refused("busy"))
        #expect(AskClient.failure(status: 500, body: Data()) == .server(500))
    }

    @Test("The request carries the conversation, the context and the key, never a model key")
    func request() throws {
        let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let context = AskContext(day: "2026-10-03", scores: .init(sleep: 82), metrics: [], person: nil)
        let request = try AskClient.request(url: URL(string: "https://qnysyehawitnlcnccyop.supabase.co/functions/v1/ask-soma")!, key: "sb_publishable_x",
                                            messages: [AskWireTurn(role: .user, content: "How did I sleep?")], context: context, conversationID: id)
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_x")
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["conversation_id"] as? String == "11111111-1111-4111-8111-111111111111")
        #expect((body["messages"] as? [[String: Any]])?.first?["role"] as? String == "user")
        #expect(((body["context"] as? [String: Any])?["scores"] as? [String: Any])?["sleep"] as? Int == 82)
    }

    @Test("The context keeps shown numbers, leaves out empty metrics, and rounds")
    func context() throws {
        var insight = Insight.empty(.higher)
        insight.current = 41.26
        insight.usual = 45
        insight.band = 40...50
        insight.position = .within
        insight.direction = .falling
        insight.cue = "3 days falling"
        let built = AskContextBuilder.make(scores: nil, insights: [(.heartRateVariability, insight), (.weight, .empty(.steady))])
        #expect(built.metrics.count == 1)
        let metric = try #require(built.metrics.first)
        #expect(metric.name == "heartRateVariability")
        #expect(metric.current == 41.3)
        #expect(metric.usualLow == 40)
        #expect(metric.direction == "falling")
        #expect(metric.cue == "3 days falling")
    }

    @Test("CRC-32 matches the standard check value")
    func crc() {
        #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test("The ZIP holds each entry once, readable from its central directory")
    func zip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "zip-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let zip = try ZipWriter(url: url)
        try zip.add("README.txt", data: Data("hello".utf8))
        try zip.add("health/HKQuantityTypeIdentifierStepCount.ndjson", data: Data("{\"value\":1}\n".utf8))
        try zip.finish()

        let data = try Data(contentsOf: url)
        func u32(_ at: Int) -> UInt32 { data[at..<at + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func u16(_ at: Int) -> UInt16 { UInt16(data[at]) | UInt16(data[at + 1]) << 8 }
        #expect(u32(0) == 0x0403_4b50)
        let end = data.count - 22
        #expect(u32(end) == 0x0605_4b50)
        #expect(u16(end + 10) == 2)
        let directory = Int(u32(end + 16))
        #expect(u32(directory) == 0x0201_4b50)
        #expect(u32(directory + 16) == ZipWriter.crc32(Data("hello".utf8)))
        let nameLength = Int(u16(directory + 28))
        #expect(String(decoding: data[(directory + 46)..<(directory + 46 + nameLength)], as: UTF8.self) == "README.txt")
    }
}
