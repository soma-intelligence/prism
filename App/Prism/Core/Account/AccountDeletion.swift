//
//  AccountDeletion.swift
//  Prism
//

import Foundation
import SyncCore
import SyncSupabase

/// "Delete my data": removes the Soma account and everything stored with it
/// on the server, then signs out.
///
/// The work runs in the Edge Function `delete-account` with the service role:
/// it removes the person's folders in both buckets, then deletes the auth
/// user, which cascades to every table. The app only asks, with the person's
/// own session, so nobody can delete anyone else.
///
/// Call it after the person confirmed on screen (the Settings row owns that
/// dialog; ``confirmationTitle`` and ``confirmationMessage`` are its words).
/// On the phone, the local sync database is erased so nothing is pushed
/// again, and so are the files sync never sends (``LocalDataErasure``):
/// sleep places, rituals and the Longevity snapshot. The rest of what is on
/// the phone stays until the app is deleted.
@MainActor
enum AccountDeletion {
    static let functionName = "delete-account"
    static let confirmationTitle = String(localized: "Delete your Soma account?")
    static let confirmationMessage = String(localized: "Everything Soma keeps for you online goes: your profile, photo, journal, logs, scores and Health data. On this phone, your sleep places and rituals go too. This can’t be undone.")

    nonisolated enum Failure: Error, Equatable {
        case notSignedIn
        case server(String)
    }

    static func run() async throws {
        let account = AccountSession.shared
        guard let services = account.services, let user = account.state.user else { throw Failure.notSignedIn }
        do {
            try await services.invoke(functionName)
        } catch {
            throw Failure.server(String(describing: SupabaseServices.remoteError(error)))
        }
        await account.signOut()
        // The numbers Longevity kept to open on, the sleep places and the
        // rituals go with the account: sync never sent them, so only the
        // phone can erase them.
        LocalDataErasure.run()
        do {
            try WellnessSession.eraseLocalData(userID: UserID(user.id))
        } catch {
            // The server copy is gone; a leftover local database is harmless
            // and is replaced on the next sign in.
        }
    }
}
