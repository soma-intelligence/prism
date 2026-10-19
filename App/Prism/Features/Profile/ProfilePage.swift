//
//  ProfilePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the profile picture opens.
///
/// The form a sheet presents, stack and Done button included. The settings
/// sheet pushes ``ProfileContent`` from its account row instead, for the reason
/// ``NotWiredPage`` gives: a stack inside a stack traps SwiftUI.
struct ProfilePage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProfileContent()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// ``ProfilePage`` without the stack and the Done button: the form a
/// navigation stack pushes.
struct ProfileContent: View {
    var body: some View {
        PageScaffold(eyebrow: "Profile", title: "You") {
            NoteCard(
                title: "No account yet",
                message: "There is nothing to show because nothing is signed in. The picture stays a glyph until there is a real one to put there."
            )
        }
    }
}

#Preview("Profile") {
    ProfilePage()
}
