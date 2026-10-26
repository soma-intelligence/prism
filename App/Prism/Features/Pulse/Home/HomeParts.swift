//
//  HomeParts.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - Shells

/// The shape of a sheet Today opens: a stack of its own, an eyebrow and a
/// title at the head of the scroll, and Done.
struct HomeSheet<Content: View>: View {
    let eyebrow: String
    let title: String
    let content: Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    /// The sheet's own stack zooms its pages out of the rows that open them.
    @Namespace private var zoom

    init(eyebrow: String, title: String, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.title = title
        self.content = content()
    }

    var body: some View {
        let metrics = theme.metrics

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                    VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                        HomeEyebrow(eyebrow)
                        Text(title)
                            .somaFont(theme.typography.title)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                            .accessibilityAddTraits(.isHeader)
                    }
                    content
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.pagePadding)
                .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .softScrollEdges()
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: PulseRoute.self) { $0.page.zoomDestination($0) }
            .journeyDestinations()
        }
        .environment(\.zoomNamespace, zoom)
        .presentationBackground(theme.colors.canvas.color)
    }
}

/// The shape of a page Today pushes: one column under the system's back
/// button, its name in the bar.
struct HomePage<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let metrics = theme.metrics

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                content
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, metrics.cardSpacing)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle(Text(title))
        .toolbarTitleDisplayMode(.inline)
    }
}

/// A sheet that asks for one thing: Cancel, a title in the bar, the control,
/// and one button at the foot.
struct HomeInputSheet<Content: View>: View {
    let title: String
    let actionTitle: String
    var isEnabled = true
    let action: () -> Void
    let content: Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        actionTitle: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.isEnabled = isEnabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        let metrics = theme.metrics

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                    content
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.pagePadding)
                .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .softScrollEdges()
#if !os(visionOS)
            // The headset's keyboard floats apart from the window.
            .scrollDismissesKeyboard(.interactively)
#endif
            .safeAreaInset(edge: .bottom) {
                HomePrimaryButton(actionTitle, isEnabled: isEnabled) {
                    action()
                    dismiss()
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.cardSpacing)
                .frame(maxWidth: metrics.pageMaxWidth)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle(Text(title))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(theme.colors.canvas.color)
    }
}

// MARK: - Words

/// A quiet label over a section, in sentence case.
struct HomeEyebrow: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.eyebrow)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A line of grey under a card or a group, saying what fills it or why.
struct HomeNote: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The first sentence of a reason, in ink. The rest is not drawn (owner,
/// 2026-10-03: fewer words); VoiceOver reads it as the hint.
struct HomeReason: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        let colors = theme.colors
        let (claim, rest) = Self.split(text)
        Text(claim)
            .foregroundStyle(colors.inkPrimary.color)
            .somaFont(theme.typography.callout)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHint(rest)
    }

    /// The first sentence, and the rest with its leading space.
    static func split(_ text: String) -> (String, String) {
        guard let end = text.range(of: ". ") else { return (text, "") }
        return (String(text[..<end.lowerBound]) + ".", " " + String(text[end.upperBound...]))
    }
}

/// A number and its unit on one baseline.
struct HomeValue: View {
    let value: String?
    let unit: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
            Text(value ?? "-")
                .somaFont(theme.typography.metric)
                .foregroundStyle(theme.colors.inkPrimary.color)
            if let unit {
                Text(unit)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

/// A card of rows under a header, a hairline between each.
struct HomeRowsCard<Content: View>: View {
    let title: LocalizedStringResource?
    let caption: LocalizedStringResource?
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: LocalizedStringResource? = nil, caption: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                if let title {
                    SomaCardHeader(title, caption: caption)
                } else if let caption {
                    HomeEyebrow(String(localized: caption))
                }
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { HomeHairline() }
                        row
                    }
                }
            }
        }
    }
}

/// The thin line between two rows.
struct HomeHairline: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// A row that names a value: the name on the leading edge, a second line
/// under it, the value on the trailing edge.
struct HomeValueRow: View {
    let name: String
    var detail: String?
    let value: String?
    var isWorse = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(name)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if let detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value ?? "-")
                .somaFont(type.body)
                .foregroundStyle(value == nil ? colors.inkSecondary.color : (isWorse ? colors.danger.color : colors.inkPrimary.color))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One thing to do, with the aspect's mini orb beside it.
struct HomeActionCard: View {
    let eyebrow: String
    let aspect: SomaAspect
    let title: String
    let detail: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaActionCard(eyebrow: eyebrow, title: title, detail: detail, actionTitle: actionTitle, action: action) {
            PulseMiniOrb(aspect: aspect, diameter: theme.metrics.miniOrbDiameter)
        }
    }
}

// MARK: - Controls

/// The screen's one primary action: the accent, full width.
struct HomePrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        let colors = theme.colors

        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(isEnabled ? colors.onAccent.color : colors.inkSecondary.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 8)
                .background(Capsule().fill(isEnabled ? colors.accent.color : colors.surface.color))
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
        .disabled(!isEnabled)
    }
}

/// A quieter action beside the primary one.
struct HomeSecondaryButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 8)
                .background(Capsule().fill(theme.colors.surface.color))
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
    }
}

/// A word to pick. Chosen, it steps up a tone and its label takes the accent.
struct HomeChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors

        // No checkmark: the owner asked for no tick on a chosen chip. The
        // chosen one is the filled pill, ink on the accent, which is the whole
        // signal and keeps the label from shifting sideways when it turns on.
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(isOn ? colors.onAccent.color : colors.inkPrimary.color)
                .padding(.horizontal, theme.metrics.spaceL)
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .background(Capsule().fill(isOn ? colors.accent.color : colors.surface.color))
            .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Chips laid out in lines that wrap.
struct HomeFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// A caption over a run of chips, for the sheets that ask for words.
struct HomeChipGroup: View {
    let title: String
    let options: [String]
    @Binding var chosen: Set<String>
    var single = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            HomeFlow {
                ForEach(options, id: \.self) { option in
                    HomeChip(title: option, isOn: chosen.contains(option)) {
                        if chosen.contains(option) {
                            chosen.remove(option)
                        } else {
                            if single { chosen.removeAll() }
                            chosen.insert(option)
                        }
                    }
                }
            }
        }
    }
}

/// A plain segmented choice over a sheet's content.
struct HomeSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaSegmentedControl(
            segments: options.map { SomaSegment(id: $0.0, title: LocalizedStringResource(stringLiteral: $0.1)) },
            selection: $selection
        )
    }
}
