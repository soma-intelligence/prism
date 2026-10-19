//
//  SomaAvatarButton.swift
//  SomaUI
//

import SwiftUI

/// The outline a profile picture is cut to.
public enum SomaAvatarShape: Sendable, Equatable, CaseIterable {
    case circle
    case roundedRect
}

/// A profile picture, tappable, with an honest fallback.
///
/// No picture yet is a state, not an error: the initials stand in, and when
/// there are no initials either a glyph does. Nothing here invents a face.
public struct SomaAvatarButton: View {
    private let image: Image?
    private let initials: String?
    private let shape: SomaAvatarShape
    private let diameterOverride: CGFloat?
    private let accessibilityLabel: LocalizedStringResource
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    public init(
        image: Image? = nil,
        initials: String? = nil,
        shape: SomaAvatarShape = .circle,
        diameter: CGFloat? = nil,
        accessibilityLabel: LocalizedStringResource,
        action: @escaping () -> Void
    ) {
        self.image = image
        self.initials = initials
        self.shape = shape
        self.diameterOverride = diameter
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    private var diameter: CGFloat { diameterOverride ?? theme.metrics.avatarDiameter }

    private var outline: AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .roundedRect: AnyShape(RoundedRectangle(cornerRadius: diameter * 0.28, style: .continuous))
        }
    }

    /// The picture is small, so the tap target is grown around it rather than
    /// the picture being blown up to meet the minimum.
    private var tapTarget: CGFloat {
        max(diameter, theme.metrics.minimumTapTarget)
    }

    public var body: some View {
        Button(action: action) {
            face
                .frame(width: tapTarget, height: tapTarget)
                .contentShape(outline)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var face: some View {
        SomaAvatarFace(image: image, initials: initials, shape: shape, diameter: diameter)
    }
}

/// The picture on its own, without a button around it.
///
/// Split out so a control that brings its own button, or that has to sit inside
/// a linked glass group, can draw the same face instead of copying it.
public struct SomaAvatarFace: View {
    private let image: Image?
    private let initials: String?
    private let shape: SomaAvatarShape
    private let diameterOverride: CGFloat?
    private let fillsPlaceholder: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameter fillsPlaceholder: whether the empty state paints a disc of
    ///   its own. False on a glass surface, where an opaque disc would sit on
    ///   the material instead of in it and break the join with its neighbours.
    public init(
        image: Image? = nil,
        initials: String? = nil,
        shape: SomaAvatarShape = .circle,
        diameter: CGFloat? = nil,
        fillsPlaceholder: Bool = true
    ) {
        self.image = image
        self.initials = initials
        self.shape = shape
        self.diameterOverride = diameter
        self.fillsPlaceholder = fillsPlaceholder
    }

    /// A face with nothing behind it draws no outline either: there is no edge
    /// between a glyph and the material it sits on.
    private var hasSurface: Bool { image != nil || hasInitials || fillsPlaceholder }

    private var hasInitials: Bool { !(initials ?? "").isEmpty }

    private var diameter: CGFloat { diameterOverride ?? theme.metrics.avatarDiameter }

    private var outline: AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .roundedRect: AnyShape(RoundedRectangle(cornerRadius: diameter * 0.28, style: .continuous))
        }
    }

    public var body: some View {
        content
            .frame(width: diameter, height: diameter)
            .clipShape(outline)
            .overlay {
                if hasSurface {
                    outline.stroke(
                        theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity),
                        lineWidth: 0.5
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            image.resizable().scaledToFill()
        } else if hasInitials, let initials {
            // A soft wash from the card's tone to the recessed one: the
            // letters carry the identity, not a colour.
            ZStack {
                LinearGradient(
                    colors: [theme.colors.surface.color, theme.colors.surfaceRecessed.color],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Text(initials)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(theme.colors.inkPrimary.color)
            }
        } else if fillsPlaceholder {
            ZStack {
                theme.colors.surfaceRecessed.color
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.5))
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: diameter * 0.62))
                .foregroundStyle(theme.colors.inkPrimary.color)
        }
    }
}

#Preview("Avatar Button") {
    ZStack {
        SomaPreviewBackdrop()

        HStack(spacing: 16) {
            SomaAvatarButton(accessibilityLabel: "Profile") {}
            SomaAvatarButton(initials: "QC", accessibilityLabel: "Profile") {}
        }
    }
}
