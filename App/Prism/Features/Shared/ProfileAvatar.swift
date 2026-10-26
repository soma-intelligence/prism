//
//  ProfileAvatar.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The person as every surface draws them: the photo in a circle, or their
/// initials, or the glyph.
struct ProfileAvatar: View {
    var diameter: CGFloat?
    var fillsPlaceholder = true

    @State private var store = SomaProfileStore.shared

    var body: some View {
        SomaAvatarFace(
            image: store.photoImage,
            initials: ProfilePhoto.initials(store.profile.firstName),
            shape: .circle,
            diameter: diameter,
            fillsPlaceholder: fillsPlaceholder
        )
    }
}
