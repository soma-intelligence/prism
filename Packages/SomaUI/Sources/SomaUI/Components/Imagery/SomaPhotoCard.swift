//
//  SomaPhotoCard.swift
//  SomaUI
//

import SwiftUI

/// A card that sits on a photograph instead of the surface: the place the
/// card is about, shaded towards the bottom where its words sit.
///
/// The content is set in the dark appearance whatever the system's, so every
/// role it reads off the theme (primary ink, secondary ink, an aspect's hue)
/// resolves to its light on dark value over the shade. Nothing inside has to
/// know it sits on a photograph. Secondary ink is lifted to a near white
/// there, since the dark appearance's grey sinks into a busy picture.
public struct SomaPhotoCard<Content: View>: View {
    private let photo: SomaPhoto
    private let content: Content

    @Environment(\.somaTheme) private var theme

    public init(_ photo: SomaPhoto, @ViewBuilder content: () -> Content) {
        self.photo = photo
        self.content = content()
    }

    public var body: some View {
        let metrics = theme.metrics
        let scrim = theme.colors.photoScrim.color
        let shape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)

        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.cardPadding)
            .frame(minHeight: metrics.photoCardMinHeight, alignment: .bottomLeading)
            .environment(\.colorScheme, .dark)
            .somaTheme(onPhoto)
            .background {
                Image(photo.assetName, bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [scrim.opacity(metrics.photoScrimTop), scrim.opacity(metrics.photoScrimBottom)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .contentShape(shape)
    }

    /// The theme the content reads on the photograph.
    private var onPhoto: SomaTheme {
        var lifted = theme
        lifted.colors.inkSecondary = theme.colors.photoInkSecondary
        return lifted
    }
}

#Preview("Photo cards") {
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            VStack(spacing: 12) {
                ForEach(SomaPhoto.allCases, id: \.self) { photo in
                    SomaPhotoCard(photo) {
                        SomaMoveRow(aspect: .sleep, lead: "In bed by", title: "22:45", reason: nil, isDone: false) {}
                    }
                }
            }
            .padding()
        }
    }
}
