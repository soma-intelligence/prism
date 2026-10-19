import Foundation
import SyncCore

/// Where a person's objects live. The first folder is always their user id,
/// which is what the bucket policies check.
public enum StoragePath {
    public static let avatarsBucket = "avatars"
    public static let healthUploadsBucket = "health-uploads"

    /// `<uid>/avatar.jpg`.
    public static func avatar(userID: UserID) -> String {
        "\(userID.rawValue.lowercased())/avatar.jpg"
    }

    /// `<uid>/<folder>/<name>`, with anything that is not a plain file name
    /// character in `name` replaced, so a name can never climb out of the folder.
    public static func healthUpload(userID: UserID, folder: String, name: String) -> String {
        "\(userID.rawValue.lowercased())/\(safe(folder))/\(safe(name))"
    }

    static func safe(_ component: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let mapped = String(component.map { allowed.contains($0) ? $0 : "_" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "_" : trimmed
    }
}
