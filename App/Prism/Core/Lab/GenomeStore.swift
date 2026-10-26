//
//  GenomeStore.swift
//  Prism
//
//  What a DNA file left behind: the provider, how many genotypes it carried,
//  and the handful of variants Soma reads, as the file wrote them. The rest of
//  the file is never kept, unless the person chose "Keep the file on this
//  iPhone", which copies it into the lab folder with complete file
//  protection. Nothing here leaves the phone.
//

import Foundation
import Observation

nonisolated struct GenomeResult: Codable, Sendable, Equatable {
    var importedAt: Date
    var provider: GenomeProvider
    var build: String?
    var snpsRead: Int
    var noCalls: Int
    /// rsid to the genotype as the file wrote it, only for catalog variants.
    var genotypes: [String: String]
    /// The kept copy's file name in the lab folder, when the person kept it.
    var keptFileName: String?

    init(importedAt: Date, parse: GenomeParse, keptFileName: String? = nil) {
        self.importedAt = importedAt
        provider = parse.provider
        build = parse.build
        snpsRead = parse.snpsRead
        noCalls = parse.noCalls
        genotypes = parse.genotypes
        self.keptFileName = keptFileName
    }

    /// One variant's genotype on the plus strand, sorted, or nil when the file
    /// did not carry it or could not call it.
    func genotype(_ variant: GenomeVariant) -> String? {
        genotypes[variant.id].flatMap(variant.oriented)
    }

    /// The catalog variants the file carried with a call.
    var found: [GenomeVariant] { GenomeCatalog.shown.filter { genotype($0) != nil } }

    var apoe: (type: APOEType, isAmbiguous: Bool)? {
        guard let a = GenomeCatalog.byID["rs429358"].flatMap(genotype),
              let b = GenomeCatalog.byID["rs7412"].flatMap(genotype) else { return nil }
        return APOEType.from(rs429358: a, rs7412: b)
    }
}

@MainActor
@Observable
final class GenomeStore {
    static let shared: GenomeStore = {
        #if DEBUG
        if LabFixtures.isOn {
            let store = GenomeStore(url: nil, folder: nil)
            store.save(LabFixtures.genome)
            return store
        }
        #endif
        return GenomeStore(url: LabFiles.url("genome.json"), folder: LabFiles.folder)
    }()

    private struct Stored: Codable {
        var result: GenomeResult?
        var showsAPOE = false
    }

    private(set) var result: GenomeResult?
    /// The person asked to see APOE, after reading what it is.
    private(set) var showsAPOE: Bool
    private let url: URL?
    private let folder: URL?

    init(url: URL?, folder: URL?) {
        self.url = url
        self.folder = folder
        let stored = LabFiles.load(Stored.self, from: url)
        result = stored?.result
        showsAPOE = stored?.showsAPOE ?? false
    }

    func save(_ result: GenomeResult) {
        if let old = self.result?.keptFileName, old != result.keptFileName { removeKept(old) }
        self.result = result
        persist()
    }

    func setShowsAPOE(_ shows: Bool) {
        showsAPOE = shows
        persist()
    }

    /// The file copied into the lab folder, protected. Returns its name.
    func keep(copyOf source: URL) -> String? {
        guard let folder else { return nil }
        let name = "genome-raw." + (source.pathExtension.isEmpty ? "txt" : source.pathExtension.lowercased())
        let target = folder.appending(path: name)
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            #if os(iOS) || os(visionOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            #endif
            return name
        } catch {
            return nil
        }
    }

    var keptFileURL: URL? {
        guard let name = result?.keptFileName, let folder else { return nil }
        return folder.appending(path: name)
    }

    /// The result, the choice and any kept file, gone.
    func eraseAll() {
        if let name = result?.keptFileName { removeKept(name) }
        result = nil
        showsAPOE = false
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func removeKept(_ name: String) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }

    private func persist() {
        LabFiles.save(Stored(result: result, showsAPOE: showsAPOE), to: url)
    }
}
