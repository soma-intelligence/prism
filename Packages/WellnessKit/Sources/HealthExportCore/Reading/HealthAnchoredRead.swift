//
//  HealthAnchoredRead.swift
//  HealthExportCore
//

import Foundation

/// One sample read with its identity, so an upload can be replayed without
/// storing the same sample twice.
public struct HealthSampleRecord: Sendable, Hashable, Codable {
    /// The platform's identifier for the sample: HealthKit's `HKObject.uuid`.
    /// Stable for the life of the sample, and the key an upload upserts on.
    public let uuid: UUID
    public let reading: HealthReading

    public init(uuid: UUID, reading: HealthReading) {
        self.uuid = uuid
        self.reading = reading
    }
}

/// What changed for one metric since an anchor.
///
/// The anchor is opaque bytes the source hands back. It is only ever passed
/// back to the same source: HealthKit's anchors belong to one Health store, so
/// an anchor from another device means nothing here.
public struct HealthSampleChanges: Sendable, Hashable {
    /// Samples added since the anchor, in the order the store added them.
    public let added: [HealthSampleRecord]
    /// Identifiers of samples deleted since the anchor.
    public let deleted: [UUID]
    /// The anchor to pass next time. Nil only when the source had nothing to
    /// say and kept no position.
    public let anchor: Data?
    /// True when the page was cut at the limit and more changes are waiting.
    public let hasMore: Bool

    public init(added: [HealthSampleRecord], deleted: [UUID], anchor: Data?, hasMore: Bool) {
        self.added = added
        self.deleted = deleted
        self.anchor = anchor
        self.hasMore = hasMore
    }

    public var isEmpty: Bool { added.isEmpty && deleted.isEmpty }
}

/// A source that can say what changed since a position, which is what an
/// incremental upload needs. HealthKit's `HKAnchoredObjectQuery` is the model.
public protocol HealthAnchoredSampleSource: HealthSampleSource {
    /// Samples added and deleted after `anchor`, at most `limit` of them
    /// (`0` means no limit). A nil anchor starts from the beginning of the store.
    func changes(_ metric: HealthMetric, after anchor: Data?, limit: Int) async throws -> HealthSampleChanges
}

public extension HealthSampleSource {
    /// Whether this source can read changes since an anchor. A source that
    /// cannot (a fixture, the empty store) is simply never uploaded from.
    var supportsAnchoredReads: Bool { self is any HealthAnchoredSampleSource }
}
