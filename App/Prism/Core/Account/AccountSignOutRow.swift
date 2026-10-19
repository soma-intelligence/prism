//
//  AccountSignOutRow.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Sign out, for the account page. Shows only while someone is signed in,
/// asks once, and leaves everything on the phone where it is.
struct AccountSignOutRow: View {
    @Environment(\.somaTheme) private var theme
    @State private var account = AccountSession.shared
    @State private var confirming = false

    var body: some View {
        if let user = account.state.user {
            VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
                if let email = user.email {
                    Text(email)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                Button("Sign out", role: .destructive) { confirming = true }
                    .buttonStyle(.plain)
                    .somaFont(theme.typography.body)
                    .frame(minHeight: theme.metrics.minimumTapTarget)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .confirmationDialog("Sign out of Soma?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await account.signOut() }
                }
            } message: {
                Text("What you logged stays on this phone. It syncs again when you sign back in.")
            }
        }
    }
}
