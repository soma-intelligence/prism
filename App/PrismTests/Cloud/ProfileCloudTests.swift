//
//  ProfileCloudTests.swift
//  PrismTests
//

import Foundation
import Testing
import SyncSupabase
@testable import Prism

/// The profile and the device are written straight into their tables, not
/// through the outbox, so the database's own checks are the only reviewer. A
/// key the table lacks fails the whole upsert; a value outside a check
/// constraint does too. These hold the rows to
/// `supabase/migrations/20261003120100_profiles_devices.sql`.
@Suite("Profile and device rows")
struct ProfileCloudTests {
    let user = "0F8FAD5B-D9CB-469F-A165-70867728950E"

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// The columns of `table`, read from its `create table` statement.
    static func columns(of table: String) throws -> Set<String> {
        let url = StyleGuardTests.root.appendingPathComponent("supabase/migrations/20261003120100_profiles_devices.sql")
        let sql = try String(contentsOf: url, encoding: .utf8)
        let block = try #require(sql.range(of: "create table public.\(table) (")).upperBound
        let end = try #require(sql.range(of: "\n);", range: block..<sql.endIndex)).lowerBound
        let column = try NSRegularExpression(pattern: #"^    ([a-z_]+) "#, options: [.anchorsMatchLines])
        let text = String(sql[block..<end])
        return Set(column.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    static func keys<Row: Encodable>(_ row: Row) throws -> Set<String> {
        let data = try SupabaseServices.encoder().encode(row)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    var profile: SomaProfile {
        var profile = SomaProfile()
        profile.name = "  Ada "
        profile.birthday = calendar.date(from: DateComponents(year: 1991, month: 4, day: 12, hour: 9))
        profile.sex = .female
        profile.focus = FocusArea.allCases.prefix(2).map { $0 }
        profile.onboardedAt = Date(timeIntervalSince1970: 1_791_028_800)
        return profile
    }

    @Test("Every key of the profile row is a column of profiles")
    func profileKeysAreColumns() throws {
        let row = ProfileRow.make(userID: user, profile: profile, avatarPath: "\(user.lowercased())/avatar.jpg", calendar: calendar)
        let unknown = try Self.keys(row).subtracting(Self.columns(of: "profiles"))
        #expect(unknown.isEmpty, "profiles has no column for \(unknown.sorted())")
    }

    @Test("The profile row reads the person as the table stores them")
    func profileRow() {
        let row = ProfileRow.make(userID: user, profile: profile, avatarPath: nil, calendar: calendar)
        #expect(row.id == user.lowercased())
        #expect(row.firstName == "Ada")
        #expect(row.birthDate == "1991-04-12")
        #expect(row.sex == "female")
        #expect(row.focus == FocusArea.allCases.prefix(2).map(\.rawValue))
        #expect(row.timeZone == "Europe/Paris")
    }

    @Test("Every sex the app offers is one the table accepts")
    func sexesAccepted() {
        #expect(Set(BiologicalSex.allCases.map(\.rawValue)).isSubset(of: ["male", "female", "other"]))
    }

    @Test("Every key of the device row is a column of devices, its platform one the table knows")
    func deviceRow() throws {
        let row = DeviceRow.current(userID: user)
        let unknown = try Self.keys(row).subtracting(Self.columns(of: "devices"))
        #expect(unknown.isEmpty, "devices has no column for \(unknown.sorted())")
        #expect(["ios", "ipados", "macos", "visionos", "watchos"].contains(row.platform))
        #expect(row.userID == user.lowercased())
        #expect((8...64).contains(row.installationID.count))
    }

    @Test("This installation keeps one id")
    func installationID() {
        let first = InstallationID.current()
        #expect(InstallationID.current() == first)
        #expect(UUID(uuidString: first) != nil)
        #expect(first == first.lowercased())
    }

    @Test("A photo's hash is short, stable and changes with the photo")
    func photoHash() {
        let photo = Data("a photo".utf8)
        let hash = ProfileCloud.photoHash(photo)
        #expect(hash.count == 24)
        let isHex = hash.allSatisfy { $0.isHexDigit }
        #expect(isHex)
        #expect(ProfileCloud.photoHash(photo) == hash)
        #expect(ProfileCloud.photoHash(Data("another photo".utf8)) != hash)
    }
}
