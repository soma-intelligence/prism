//
//  ProfileCloud.swift
//  Prism
//

import CryptoKit
import Foundation
import SyncCore
import SyncSupabase

/// One row of `public.profiles` as the app writes it.
nonisolated struct ProfileRow: Codable, Equatable, Sendable {
    var id: String
    var firstName: String?
    /// `yyyy-MM-dd`.
    var birthDate: String?
    var sex: String?
    var focus: [String]
    var chronotype: RMEQAnswers?
    var timeZone: String?
    var avatarPath: String?
    var onboardedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sex, focus, chronotype
        case firstName = "first_name"
        case birthDate = "birth_date"
        case timeZone = "time_zone"
        case avatarPath = "avatar_path"
        case onboardedAt = "onboarded_at"
    }

    /// Every key, nulls included: an upsert updates only the columns it is
    /// sent, so a cleared field has to arrive as null to clear the column.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(sex, forKey: .sex)
        try container.encode(focus, forKey: .focus)
        try container.encode(chronotype, forKey: .chronotype)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(avatarPath, forKey: .avatarPath)
        try container.encode(onboardedAt, forKey: .onboardedAt)
    }

    /// The row for a local profile. The birthday is read as a day in the
    /// calendar it was picked in.
    static func make(userID: String, profile: SomaProfile, avatarPath: String?, calendar: Calendar = .current) -> ProfileRow {
        ProfileRow(
            id: userID.lowercased(),
            firstName: profile.firstName,
            birthDate: profile.birthday.map { CloudSnapshots.dayKey($0, calendar: calendar) },
            sex: profile.sex?.rawValue,
            focus: profile.focus.map(\.rawValue),
            chronotype: profile.chronotype,
            timeZone: calendar.timeZone.identifier,
            avatarPath: avatarPath,
            onboardedAt: profile.onboardedAt
        )
    }
}

/// One row of `public.devices`.
nonisolated struct DeviceRow: Codable, Equatable, Sendable {
    var userID: String
    var installationID: String
    var platform: String
    var model: String?
    var osVersion: String
    var appVersion: String?
    var timeZone: String
    var lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case platform, model
        case userID = "user_id"
        case installationID = "installation_id"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case timeZone = "time_zone"
        case lastSeenAt = "last_seen_at"
    }

    static func current(userID: String) -> DeviceRow {
        #if os(visionOS)
        let platform = "visionos"
        #elseif os(macOS)
        let platform = "macos"
        #else
        let platform = "ios"
        #endif
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceRow(
            userID: userID.lowercased(),
            installationID: InstallationID.current(),
            platform: platform,
            model: machine.isEmpty ? nil : machine,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            timeZone: TimeZone.current.identifier,
            lastSeenAt: Date()
        )
    }
}

/// The profile, its photo and this phone, kept in step with the server.
///
/// The phone is the source of truth for what the person typed. On a phone
/// that knows nothing yet (a new install), what the server holds fills the
/// gaps, the photo included; nothing typed on this phone is overwritten.
actor ProfileCloud {
    private let userID: UserID
    private let services: SupabaseServices
    private let stateURL: URL

    /// What was last confirmed by the server, so an unchanged profile costs
    /// no request.
    private struct Sent: Codable {
        var row: ProfileRow?
        var photoHash: String?
        var restored = false
    }
    private var sent: Sent

    init(userID: UserID, services: SupabaseServices, directory: URL) {
        self.userID = userID
        self.services = services
        self.stateURL = directory.appending(path: "profile-sent.json")
        if let data = FileManager.default.contents(atPath: stateURL.path), let decoded = try? JSONDecoder().decode(Sent.self, from: data) {
            sent = decoded
        } else {
            sent = Sent()
        }
    }

    nonisolated static func photoHash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// On the first pass on this phone: reads the server's row and photo, and
    /// hands back what the local profile may lack.
    func restore(hasPhoto: Bool) async throws -> (fields: ProfileRow?, photo: Data?) {
        guard !sent.restored else { return (nil, nil) }
        let rows = try await services.select(ProfileRow.self, from: "profiles",
                                             columns: "id,first_name,birth_date,sex,focus,chronotype,time_zone,avatar_path,onboarded_at",
                                             where: "id", equals: userID.rawValue.lowercased())
        var photo: Data?
        if !hasPhoto, let path = rows.first?.avatarPath {
            photo = try await services.download(bucket: StoragePath.avatarsBucket, path: path)
            if let photo { sent.photoHash = Self.photoHash(photo) }
        }
        sent.restored = true
        try save()
        return (rows.first, photo)
    }

    /// Uploads the photo when it changed, removes it when it went, and
    /// upserts the profile row with the photo's path.
    func push(profile: SomaProfile, photo: Data?) async throws {
        let path = StoragePath.avatar(userID: userID)
        let hash = photo.map(Self.photoHash)
        if let photo, hash != sent.photoHash {
            try await services.upload(photo, bucket: StoragePath.avatarsBucket, path: path, contentType: "image/jpeg")
            sent.photoHash = hash
            try save()
        } else if photo == nil, sent.photoHash != nil {
            try await services.remove(bucket: StoragePath.avatarsBucket, paths: [path])
            sent.photoHash = nil
            try save()
        }

        let row = ProfileRow.make(userID: userID.rawValue, profile: profile, avatarPath: photo == nil ? nil : path)
        guard row != sent.row else { return }
        try await services.upsert([row], into: "profiles", onConflict: "id")
        sent.row = row
        try save()
    }

    func registerDevice() async throws {
        try await services.upsert([DeviceRow.current(userID: userID.rawValue)], into: "devices", onConflict: "user_id,installation_id")
    }

    private func save() throws {
        try JSONEncoder().encode(sent).write(to: stateURL, options: CloudFiles.writeOptions)
    }
}
