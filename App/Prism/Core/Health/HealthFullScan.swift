//
//  HealthFullScan.swift
//  Prism
//

import Foundation
import HealthExportCore

/// Where a full catalog read has got to.
struct HealthFullScan: Equatable, Sendable {
    /// Metrics interrogated so far.
    var scanned: Int = 0
    /// Metrics the store actually held something for.
    var withData: Int = 0
    /// Metrics in the read, which is every quantity and category in the catalog.
    var total: Int
    var isRunning: Bool = true
    /// The identifiers that came back with a value, in catalog order.
    var found: [String] = []

    var fraction: Double {
        total == 0 ? 0 : Double(scanned) / Double(total)
    }
}

extension HealthDashboard {

    /// Every quantity and category in the catalog. Correlations, the workout type
    /// and the characteristics are asked for in the permission sheet but are not
    /// read as a single value, so they are not part of the sweep.
    static var scannableMetrics: [HealthMetric] {
        HealthMetricCatalog.all.filter { $0.kind == .quantity || $0.kind == .category }
    }

    /// Asks for every metric Apple Health can hand over, then reads them all.
    ///
    /// This is the one path allowed to name the sensitive metrics, because a
    /// person pressed a button that says so. The launch sheet still never does.
    func scanEverything() async {
        guard isAvailable else {
            setStatus(.unavailable)
            return
        }

        let metrics = Self.scannableMetrics
        setScan(HealthFullScan(total: metrics.count))

        do {
            try await requestAuthorizationForWholeCatalog()
        } catch {
            setStatus(.failed(String(describing: error)))
            finishScan()
            return
        }

        let reader = reader
        // Bounded fan out. The catalog is large and the store is a cross process
        // call, so a chunk at a time keeps the queries overlapping without
        // opening two hundred of them at once.
        for chunk in metrics.chunks(of: 8) {
            if Task.isCancelled { break }

            let results: [(String, Bool)] = await withTaskGroup(of: (String, Bool).self) { group in
                for metric in chunk {
                    group.addTask {
                        let reading = try? await reader.latest(metric)
                        return (metric.identifier, reading != nil)
                    }
                }
                var collected: [(String, Bool)] = []
                for await result in group { collected.append(result) }
                return collected
            }

            recordChunk(results)
        }

        finishScan()
        setStatus(.ready)
    }
}

extension Array {
    /// Fixed size slices, the last one short.
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
