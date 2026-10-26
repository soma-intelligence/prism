//
//  SomaAccountRow.swift
//  SomaUI
//

import SwiftUI

/// The account at the foot of a sidebar: a picture, who is signed in, and a
/// slot for whatever acts on them.
///
/// The detail line is a plain `String` rather than a localized resource, because
/// what goes there is an address or a handle: data about the person, not copy
/// about the app, and translating it would be wrong.
public struct SomaAccountRow<Trailing: View>: View {
    private let image: Image?
    private let initials: String?
    private let name: LocalizedStringResource
    private let detail: String?
    private let accessibilityLabel: LocalizedStringResource?
    private let action: () -> Void
    private let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    public init(
        image: Image? = nil,
        initials: String? = nil,
        name: LocalizedStringResource,
        detail: String? = nil,
        accessibilityLabel: LocalizedStringResource? = nil,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.image = image
        self.initials = initials
        self.name = name
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: theme.metrics.spaceM) {
            Button(action: action) {
                HStack(spacing: theme.metrics.spaceM) {
                    SomaAvatarButton(
                        image: image,
                        initials: initials,
                        shape: .roundedRect,
                        accessibilityLabel: name,
                        action: action
                    )
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 1) {
                        // A row's title, not a page's: the sidebar sets its
                        // own width, and the title role cut a first name to
                        // its initial there on the Mac.
                        Text(name)
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                            .lineLimit(1)

                        if let detail {
                            Text(detail)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.somaGlassPress)
            .accessibilityLabel(Text(accessibilityLabel ?? name))

            trailing
        }
    }
}

public extension SomaAccountRow where Trailing == EmptyView {
    /// An account row with nothing acting on it.
    init(
        image: Image? = nil,
        initials: String? = nil,
        name: LocalizedStringResource,
        detail: String? = nil,
        accessibilityLabel: LocalizedStringResource? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            image: image,
            initials: initials,
            name: name,
            detail: detail,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) { EmptyView() }
    }
}

#Preview("Account Row") {
    ZStack {
        SomaPreviewBackdrop()

        VStack(spacing: 16) {
            SomaAccountRow(name: "Not signed in", detail: nil) {}
            SomaAccountRow(initials: "AL", name: "Ada", detail: "ada@example.com") {} trailing: {
                SomaIconButton(symbol: "ellipsis", style: .plain, accessibilityLabel: "More") {}
            }
        }
        .padding(20)
    }
}
