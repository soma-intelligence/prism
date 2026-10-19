//
//  DeleteDataPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// "Delete my data": says what goes and what stays, asks once in a
/// destructive dialog, then runs ``AccountDeletion``, which removes the
/// account on the server and signs out. The app then starts over at
/// onboarding.
struct DeleteDataPage: View {
    @Environment(\.somaTheme) private var theme
    @AppStorage(OnboardingFlow.completedKey) private var hasOnboarded = true

    @State private var account = AccountSession.shared
    @State private var confirming = false
    @State private var isDeleting = false
    @State private var failure: String?

    var body: some View {
        ListScaffold(eyebrow: "Delete", title: "Erase what Soma holds") {
            SettingsSection("What goes") {
                SomaBrowseGroup([SettingsItem].items("account", "synced", "photos", "chats")) { item in
                    switch item.id {
                    case "account":
                        SomaBrowseRow(symbol: "person.crop.circle", title: String(localized: "Your Soma account"), opensSomething: false)
                    case "synced":
                        SomaBrowseRow(symbol: "icloud", title: String(localized: "Everything synced to it"),
                                      detail: String(localized: "Journal, logs, scores"), opensSomething: false)
                    case "photos":
                        SomaBrowseRow(symbol: "photo", title: String(localized: "Your photos"), opensSomething: false)
                    default:
                        SomaBrowseRow(symbol: "bubble.left.and.bubble.right", title: String(localized: "Your Ask chats"), opensSomething: false)
                    }
                }
            }

            SettingsSection("What stays") {
                SomaBrowseGroup([SettingsItem].items("health")) { _ in
                    SomaBrowseRow(symbol: "heart.text.square", title: String(localized: "Apple Health"),
                                  detail: String(localized: "Untouched"), opensSomething: false)
                }
                SettingsFootnote("Soma never deletes from Apple Health. Take its access back in the Health app, under your picture, then Apps.")
            }

            if account.isSignedIn {
                Button { confirming = true } label: {
                    Group {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete my data")
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.danger.color)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                    .background(Capsule().strokeBorder(theme.colors.danger.color.opacity(theme.metrics.hairlineOpacity * 2), lineWidth: 1))
                    .contentShape(.capsule)
                }
                .buttonStyle(.somaGlassPress)
                .disabled(isDeleting)
            } else {
                SettingsFootnote("You’re not signed in, so Soma keeps nothing for you online. Deleting the app erases what is on this device.")
            }

            if let failure {
                Text(failure)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger.color)
                    .padding(.horizontal, theme.metrics.browseRowPadding)
            }
        }
        .confirmationDialog(AccountDeletion.confirmationTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete my data", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account, everything synced to it, your photos and your Ask chats are deleted. Apple Health is untouched. This can’t be undone.")
        }
    }

    private func delete() async {
        isDeleting = true
        failure = nil
        do {
            // Signs out once the server confirms.
            try await AccountDeletion.run()
            isDeleting = false
            // Back to the start: the root swaps to onboarding and this sheet
            // goes with the tabs it sat on.
            hasOnboarded = false
        } catch {
            isDeleting = false
            failure = String(localized: "Soma couldn’t delete your account. Nothing was removed. Try again.")
        }
    }
}

#Preview("Delete") {
    NavigationStack { DeleteDataPage() }
}
