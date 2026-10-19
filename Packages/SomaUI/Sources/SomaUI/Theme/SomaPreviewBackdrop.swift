//
//  SomaPreviewBackdrop.swift
//  SomaUI
//

import SwiftUI

/// A ground for the previews inside this module.
///
/// `SomaUIPreviewSupport` cannot be used here: it depends on this module, not
/// the other way round. This is the minimum a glass preview needs, which is
/// something behind the glass to refract.
struct SomaPreviewBackdrop: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        ZStack {
            theme.colors.canvas.color
            Circle()
                .fill(.primary.opacity(0.08))
                .frame(width: 220)
                .blur(radius: 34)
        }
        .ignoresSafeArea()
    }
}
