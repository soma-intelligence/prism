//
//  ProfilePhotoTests.swift
//  PrismTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Prism

@Suite("Profile photo")
@MainActor
struct ProfilePhotoTests {
    /// A plain PNG of the given size.
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Any photo becomes a centred 512 pixel square JPEG")
    func prepare() throws {
        let prepared = try #require(ProfilePhoto.prepare(png(width: 1600, height: 900)))
        #expect(ProfilePhoto.pixelSize(prepared) == CGSize(width: 512, height: 512))
        let small = try #require(ProfilePhoto.prepare(png(width: 300, height: 200)))
        #expect(ProfilePhoto.pixelSize(small) == CGSize(width: 200, height: 200))
        #expect(ProfilePhoto.prepare(Data("not an image".utf8)) == nil)
    }

    @Test("The photo survives a relaunch and Remove deletes it; the profile JSON is untouched")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "profile.json")

        let store = SomaProfileStore(url: url)
        store.update { $0.name = "Ada" }
        #expect(store.setPhoto(try png(width: 800, height: 1000)))
        #expect(store.photoImage != nil)

        let again = SomaProfileStore(url: url)
        #expect(again.profile.firstName == "Ada")
        #expect(again.photo == store.photo)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(!json.contains("photo"))

        again.setPhoto(nil)
        #expect(again.photo == nil)
        #expect(SomaProfileStore(url: url).photo == nil)
        #expect(!store.setPhoto(Data("x".utf8)))
    }

    @Test("Initials from the first name")
    func initials() {
        #expect(ProfilePhoto.initials("ada lovelace") == "AL")
        #expect(ProfilePhoto.initials("Ada") == "A")
        #expect(ProfilePhoto.initials(nil) == nil)
    }
}
