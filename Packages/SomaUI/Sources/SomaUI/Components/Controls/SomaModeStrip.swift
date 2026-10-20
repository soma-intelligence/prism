//
//  SomaModeStrip.swift
//  SomaUI
//

import SwiftUI

/// A camera's mode strip: labels in capitals on one line, the selected ones in
/// the accent.
///
/// One selection (the Camera app's modes) or several (conditions marked during
/// a recording). Centred while it fits the width; scrolling past its edges when
/// it does not, so a label cut by the edge says there are more. An optional
/// trailing label, in secondary ink, is an action rather than a mode.
public struct SomaModeStrip<ID: Hashable>: View {
    public struct Item: Identifiable {
        public let id: ID
        public let title: String

        public init(id: ID, title: String) {
            self.id = id
            self.title = title
        }
    }

    private let items: [Item]
    private let selected: Set<ID>
    private let trailing: String?
    private let onSelect: (ID) -> Void
    private let onTrailing: (() -> Void)?

    @Environment(\.somaTheme) private var theme

    public init(items: [Item], selected: Set<ID>, trailing: String? = nil,
                onSelect: @escaping (ID) -> Void, onTrailing: (() -> Void)? = nil) {
        self.items = items
        self.selected = selected
        self.trailing = trailing
        self.onSelect = onSelect
        self.onTrailing = onTrailing
    }

    public var body: some View {
        // One line when it fits, else lines that wrap: never a row that
        // scrolls sideways.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { buttons }
            SomaFlowLayout(spacing: 0) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(items) { item in
            let on = selected.contains(item.id)
            Button {
                onSelect(item.id)
            } label: {
                label(item.title, color: on ? theme.colors.accent.color : theme.colors.inkPrimary.color)
            }
            .buttonStyle(.somaGlassPress)
            .accessibilityAddTraits(on ? .isSelected : [])
        }

        if let trailing, let onTrailing {
            Button(action: onTrailing) {
                label(trailing, color: theme.colors.inkSecondary.color)
            }
            .buttonStyle(.somaGlassPress)
        }
    }

    private func label(_ title: String, color: Color) -> some View {
        Text(title)
            .somaFont(theme.typography.segment)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, theme.metrics.modeStripSpacing / 2)
            .frame(minHeight: theme.metrics.minimumTapTarget)
            .contentShape(.rect)
    }
}

extension SomaModeStrip.Item: Sendable where ID: Sendable {}

#Preview("Mode Strip") {
    @Previewable @State var mode = "knock"

    ZStack {
        SomaPreviewBackdrop()

        VStack(spacing: 24) {
            SomaModeStrip(items: [.init(id: "knock", title: "Knock"), .init(id: "jumps", title: "Jumps")],
                          selected: [mode], onSelect: { mode = $0 })

            SomaModeStrip(items: [.init(id: "rest", title: "rest"), .init(id: "talking", title: "talking"),
                                  .init(id: "head_motion", title: "head motion"), .init(id: "low_light", title: "low light")],
                          selected: ["rest"], trailing: "+ note", onSelect: { _ in }, onTrailing: {})
        }
    }
    .environment(\.colorScheme, .dark)
}
