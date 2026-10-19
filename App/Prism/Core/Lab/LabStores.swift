//
//  LabStores.swift
//  Prism
//
//  What a person enters on the Body lab pages, kept on the device: blood
//  panels, the four answers the risk model needs, and tape measurements.
//
//  Each is one JSON file in Application Support/lab, written atomically with
//  complete file protection: blood values are the most sensitive thing the
//  app holds. Nothing here leaves the phone; a sync, when there is one,
//  reads through these types.
//

import Foundation
import Observation

/// Where the lab files live. Nil in previews and tests, which keep memory only.
nonisolated enum LabFiles {
    static func url(_ name: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appending(path: "lab", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.lab.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder.lab.encode(value) else { return }
        #if os(iOS) || os(visionOS)
        try? data.write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        #else
        try? data.write(to: url, options: .atomic)
        #endif
    }
}

extension JSONEncoder {
    nonisolated static var lab: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var lab: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Blood panels

@MainActor
@Observable
final class BloodPanelStore {
    static let shared = BloodPanelStore(url: LabFiles.url("blood-panels.json"))

    /// Newest first, by the day the blood was drawn.
    private(set) var panels: [BloodPanel]
    private let url: URL?

    init(url: URL?) {
        self.url = url
        panels = (LabFiles.load([BloodPanel].self, from: url) ?? []).sorted { $0.date > $1.date }
    }

    var latest: BloodPanel? { panels.first }

    func save(_ panel: BloodPanel) {
        panels.removeAll { $0.id == panel.id }
        panels.append(panel)
        panels.sort { $0.date > $1.date }
        LabFiles.save(panels, to: url)
    }

    func delete(_ panel: BloodPanel) {
        panels.removeAll { $0.id == panel.id }
        LabFiles.save(panels, to: url)
    }

    /// Every reading of one marker, oldest first.
    func history(of key: String) -> [(date: Date, value: BloodMarkerValue)] {
        panels.compactMap { panel in panel.value(key).map { (panel.date, $0) } }.sorted { $0.date < $1.date }
    }

    /// The reading before the latest one, for "91 in March".
    func previous(of key: String) -> (date: Date, value: BloodMarkerValue)? {
        let all = history(of: key)
        return all.count >= 2 ? all[all.count - 2] : nil
    }
}

// MARK: - The risk answers

@MainActor
@Observable
final class CardiometabolicProfileStore {
    static let shared = CardiometabolicProfileStore(url: LabFiles.url("risk-profile.json"))

    private(set) var profile: CardiometabolicProfile
    private let url: URL?

    init(url: URL?) {
        self.url = url
        profile = LabFiles.load(CardiometabolicProfile.self, from: url) ?? CardiometabolicProfile()
    }

    func answer(_ question: CardiometabolicProfile.Question, _ value: Bool?) {
        profile.set(question, value)
        LabFiles.save(profile, to: url)
    }

    func setSex(_ sex: LabSex?) {
        profile.sex = sex
        LabFiles.save(profile, to: url)
    }
}

// MARK: - Tape measurements

/// The five places Soma measures, in the order the capture walks them.
nonisolated enum BodyMeasurementKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case waist, hips, chest, arm, thigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waist: "Waist"
        case .hips: "Hips"
        case .chest: "Chest"
        case .arm: "Arm"
        case .thigh: "Thigh"
        }
    }

    /// Where the tape goes.
    var howTo: String {
        switch self {
        case .waist: "At the narrowest point, just above the navel. Tape level, breathe out, don’t pull in."
        case .hips: "Around the widest part of the hips, feet together, tape level."
        case .chest: "At nipple height, arms relaxed at your sides, after a normal breath out."
        case .arm: "Arm bent and held level, around the fullest part of the biceps."
        case .thigh: "Standing on both legs, around the widest part, just below the fold."
        }
    }

    /// Where the dial starts before anything has been measured, in cm.
    var startingValue: Double {
        switch self {
        case .waist: 85
        case .hips: 98
        case .chest: 98
        case .arm: 31
        case .thigh: 55
        }
    }

    /// Health keeps waist circumference; the other four stay in Soma.
    var isInHealth: Bool { self == .waist }
}

/// One session of measurements.
nonisolated struct BodyMeasurementEntry: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var date: Date
    /// Centimetres by place. A skipped place is absent.
    var values: [BodyMeasurementKind: Double]
    var place: Place = .home

    enum Place: String, Codable, Sendable {
        case home, studio

        var title: String { self == .home ? "at home" : "studio" }
    }
}

@MainActor
@Observable
final class BodyMeasurementStore {
    static let shared = BodyMeasurementStore(url: LabFiles.url("body-measurements.json"))

    /// Newest first.
    private(set) var entries: [BodyMeasurementEntry]
    private let url: URL?

    init(url: URL?) {
        self.url = url
        entries = (LabFiles.load([BodyMeasurementEntry].self, from: url) ?? []).sorted { $0.date > $1.date }
    }

    func save(_ entry: BodyMeasurementEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort { $0.date > $1.date }
        LabFiles.save(entries, to: url)
    }

    func delete(_ entry: BodyMeasurementEntry) {
        entries.removeAll { $0.id == entry.id }
        LabFiles.save(entries, to: url)
    }

    /// The latest value of one place, and the first on record.
    func span(_ kind: BodyMeasurementKind) -> (first: (Date, Double), latest: (Date, Double))? {
        let dated = entries.compactMap { entry in entry.values[kind].map { (entry.date, $0) } }.sorted { $0.0 < $1.0 }
        guard let first = dated.first, let latest = dated.last else { return nil }
        return (first, latest)
    }
}
