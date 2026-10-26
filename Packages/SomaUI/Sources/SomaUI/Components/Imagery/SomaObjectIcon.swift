//
//  SomaObjectIcon.swift
//  SomaUI
//

import SwiftUI

/// One of Soma's tactile objects at one of two sizes.
///
/// Decorative: the label beside it already names the aspect, so the object is
/// hidden from VoiceOver rather than read twice.
public struct SomaObjectIcon: View {
    /// How large the object is set.
    public enum Size: Sendable {
        /// Beside a label, at the height of its line.
        case inline
        /// Leading a row.
        case row
    }

    private let object: SomaObject
    private let size: Size

    @Environment(\.somaTheme) private var theme

    public init(_ object: SomaObject, size: Size = .inline) {
        self.object = object
        self.size = size
    }

    public init(_ aspect: SomaAspect, size: Size = .inline) {
        self.init(SomaObject(aspect), size: size)
    }

    /// The aspect's object, labelled so a leading-dot case (`.sleep`) names
    /// the aspect rather than reading as either enum.
    public init(aspect: SomaAspect, size: Size = .inline) {
        self.init(SomaObject(aspect), size: size)
    }

    public var body: some View {
        let side = switch size {
        case .inline: theme.metrics.objectInline
        case .row: theme.metrics.objectRow
        }

        // A quiet line glyph, as Things marks its areas: the clay objects read
        // as decoration and left (owner, 2026-10-23). In a row it sits in a
        // recessed disc so rows keep one leading edge.
        ZStack {
            if size == .row {
                Circle().fill(theme.colors.surfaceRecessed.color)
            }
            Image(systemName: object.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: side * (size == .row ? 0.46 : 0.82), height: side * (size == .row ? 0.46 : 0.82))
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

extension SomaObject {
    /// The line glyph that stands for the object.
    var symbol: String {
        switch self {
        case .sleep: "moon"
        case .heart: "heart"
        case .activity: "figure.walk"
        case .mind: "brain.head.profile"
        case .body: "figure.stand"
        case .gut: "fork.knife"
        case .energy: "bolt"
        case .environment: "sun.max"
        }
    }
}

#Preview("Objects") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(SomaObject.allCases, id: \.self) { SomaObjectIcon($0, size: .row) }
            }
            HStack(spacing: 12) {
                ForEach(SomaObject.allCases, id: \.self) { SomaObjectIcon($0) }
            }
        }
        .padding()
    }
}
