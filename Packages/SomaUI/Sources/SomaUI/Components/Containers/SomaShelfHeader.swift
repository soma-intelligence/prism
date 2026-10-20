//
//  SomaShelfHeader.swift
//  SomaUI
//

import SwiftUI

/// The head of a section: its name, and on the trailing edge a quiet way to
/// see everything in it ("See all"), when there is more.
public struct SomaShelfHeader: View {
    private let title: String
    private let action: String?
    private let perform: (() -> Void)?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - title: the section's name.
    ///   - action: the trailing link's words; nil draws the name alone.
    public init(_ title: String, action: String? = nil, perform: (() -> Void)? = nil) {
        self.title = title
        self.action = action
        self.perform = perform
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .somaFont(theme.typography.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: metrics.cardSpacing)
            if let action, let perform {
                Button(action: perform) {
                    HStack(spacing: metrics.articleTextSpacing) {
                        Text(action)
                            .somaFont(theme.typography.callout)
                        Image(systemName: "chevron.right")
                            .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(minHeight: metrics.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPress)
                .accessibilityLabel("\(action), \(title)")
            }
        }
    }
}

#Preview("Shelf headers") {
    VStack(alignment: .leading, spacing: 16) {
        SomaShelfHeader("For you")
        SomaShelfHeader("Sleep", action: "See all") {}
    }
    .padding()
}
