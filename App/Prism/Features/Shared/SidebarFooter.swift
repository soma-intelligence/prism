//
//  SidebarFooter.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The foot of the sidebar: the app wide actions as bare buttons, and the
/// account under them.
///
/// The buttons carry no label because a sidebar already names everything above
/// them; four words repeated under three tab titles is noise, not guidance. Each
/// one keeps its spoken label, so nothing is lost to VoiceOver.
///
/// They are `plain` rather than glass: this sits inside the sidebar's own
/// material, and glass on glass is decoration.
struct SidebarFooter: View {
    let shareText: String
    var onOpen: (SidebarDestination) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ShareLink(item: shareText) {
                    SomaIconLabel(symbol: "square.and.arrow.up", style: .plain)
                }
                .buttonStyle(.somaGlassPress)
                .accessibilityLabel("Share")

                SomaIconButton(symbol: "magnifyingglass", style: .plain,
                               accessibilityLabel: "Search") { onOpen(.search) }
                SomaIconButton(symbol: "questionmark.circle", style: .plain,
                               accessibilityLabel: "Get help") { onOpen(.help) }
                SomaIconButton(symbol: "gearshape", style: .plain,
                               accessibilityLabel: "Settings") { onOpen(.settings) }
            }

            Divider().opacity(0.4)

            // The person's photo and first name once they are set; until then
            // the row invites one instead of inventing a name and an address. Two words rather than three: the system
            // sidebar sets its own width and truncated the longer label.
            SomaAccountRow(
                image: SomaProfileStore.shared.photoImage,
                initials: ProfilePhoto.initials(SomaProfileStore.shared.profile.firstName),
                name: SomaProfileStore.shared.profile.firstName.map { LocalizedStringResource(stringLiteral: $0) } ?? "Sign in",
                detail: nil,
                accessibilityLabel: "Account",
                action: { onOpen(.profile) }
            ) {
                // The Mac's sidebar is too narrow for the name and a menu
                // that repeats the row and the gear: the name keeps the room.
#if !os(macOS)
                Menu {
                    Button("Profile") { onOpen(.profile) }
                    Button("Settings") { onOpen(.settings) }
                } label: {
                    SomaIconLabel(symbol: "ellipsis", style: .plain)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
#endif
            }
        }
    }
}
