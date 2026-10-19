//
//  SomaProfileStore.swift
//  Prism
//

import Foundation
import Observation
import SwiftUI

/// The person's profile, kept on the device.
///
/// One JSON file in Application Support, beside the Journal's. Any page reads
/// it from the environment (`@Environment(SomaProfileStore.self)`) or, outside
/// a view, through ``shared``. Nothing here leaves the phone: an account sync,
/// when there is one, reads it through this type.
@MainActor
@Observable
final class SomaProfileStore {
    /// The one store the app runs on.
    static let shared = SomaProfileStore()

    private(set) var profile: SomaProfile

    /// The profile picture: a 512 pixel square JPEG in its own file beside the
    /// profile, so the profile's JSON (and every stored copy of it) is
    /// unchanged. Nil when there is none.
    private(set) var photo: Data? {
        didSet { photoImage = ProfilePhoto.image(photo) }
    }

    /// The photo, decoded once.
    private(set) var photoImage: Image?

    private let url: URL?

    private var photoURL: URL? {
        url?.deletingLastPathComponent().appending(path: "profile-photo.jpg")
    }

    /// - Parameter url: where the profile lives. Nil keeps it in memory only,
    ///   which is what previews and tests use.
    init(url: URL? = SomaProfileStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(SomaProfile.self, from: data) {
            profile = stored
        } else {
            profile = SomaProfile()
        }
        photo = photoURL.flatMap { try? Data(contentsOf: $0) }
        photoImage = ProfilePhoto.image(photo)
    }

    /// Takes any photo, keeps its centred square at 512 pixels, and writes it.
    /// Returns false when the data is not an image. Nil removes the photo.
    @discardableResult
    func setPhoto(_ data: Data?) -> Bool {
        guard let data else {
            photo = nil
            if let photoURL { try? FileManager.default.removeItem(at: photoURL) }
            return true
        }
        guard let prepared = ProfilePhoto.prepare(data) else { return false }
        photo = prepared
        if let photoURL {
            try? FileManager.default.createDirectory(at: photoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? prepared.write(to: photoURL, options: SomaFileStorage.protectedAtomicOptions)
        }
        return true
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "profile.json")
    }

    /// Changes the profile and writes it straight away.
    func update(_ change: (inout SomaProfile) -> Void) {
        var next = profile
        change(&next)
        guard next != profile else { return }
        profile = next
        save()
    }

    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // A profile that failed to write is still right in memory for this
            // run; the next change tries the write again.
        }
    }
}
