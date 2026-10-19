//
//  SomaTabBar.swift
//  SomaUI
//

import SwiftUI

/// One entry of ``SomaTabBar``.
public struct SomaTabItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: String
    public let title: LocalizedStringResource

    public init(id: String, symbol: String, title: LocalizedStringResource) {
        self.id = id
        self.symbol = symbol
        self.title = title
    }
}

public extension EnvironmentValues {
    /// Whether the tab bar is folded down to the current tab.
    ///
    /// A `Binding` because the signal travels the wrong way for an ordinary
    /// environment value: the page knows about the scroll and the bar is its
    /// sibling, not its child.
    @Entry var somaTabBarFolded: Binding<Bool> = .constant(false)
}

/// The tab capsule and its trailing control, laid out together.
///
/// Together is the point. A control placed beside the bar by an overlay has to
/// be aligned by hand against numbers measured off a screenshot, and those
/// numbers are wrong on the next screen size, the next label, the next text
/// size. Here both pieces are cells of one `HStack` inside one
/// `GlassEffectContainer`: they cannot be misaligned, they are the same
/// material, and one animation moves them.
public struct SomaTabBar<Accessory: View>: View {
    private let items: [SomaTabItem]
    @Binding private var selection: SomaTabItem.ID
    private let accessory: Accessory

    @Environment(\.somaTheme) private var theme
    @Environment(\.somaTabBarFolded) private var folded
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var selectionNamespace

    public init(
        items: [SomaTabItem],
        selection: Binding<SomaTabItem.ID>,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.items = items
        self._selection = selection
        self.accessory = accessory()
    }

    /// Folded, the capsule shows the current tab alone: the bar gets out of the
    /// way without getting lost, and a tap on it unfolds.
    private var isFolded: Bool { folded.wrappedValue && items.count > 1 }

    private var visibleItems: [SomaTabItem] {
        isFolded ? items.filter { $0.id == selection } : items
    }

    public var body: some View {
        // The container's spacing is a merge threshold, not a gap. Set equal to
        // the layout gap the two shapes sit inside each other's reach and blend
        // continuously, which softens both rims and washes the material out.
        // Kept well under it, each keeps its own crisp edge.
        SomaGlassContainer(spacing: theme.metrics.barPieceSpacing - 4) {
            HStack(spacing: theme.metrics.barPieceSpacing) {
                capsule
                accessory
            }
        }
        .animation(theme.motion.fold, value: isFolded)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var capsule: some View {
        HStack(spacing: 2) {
            ForEach(visibleItems) { item in
                SomaTabButton(
                    item: item,
                    isSelected: item.id == selection,
                    showsLabel: !isFolded,
                    namespace: selectionNamespace
                ) {
                    if isFolded {
                        withAnimation(theme.motion.fold) { folded.wrappedValue = false }
                        return
                    }
                    guard item.id != selection else { return }
                    withAnimation(theme.motion.selection) { selection = item.id }
                }
            }
        }
        .padding(theme.metrics.barPadding)
        // The system bar is a wide capsule with a small margin each side, not a
        // tight hug around its labels. Measured against a stock `TabView` on the
        // same screen: it spans about 87 percent of the width with four tabs.
        .frame(maxWidth: .infinity)
        .somaGlass(.regular, in: .capsule)
    }
}

public extension SomaTabBar where Accessory == EmptyView {
    init(items: [SomaTabItem], selection: Binding<SomaTabItem.ID>) {
        self.init(items: items, selection: selection) { EmptyView() }
    }
}

// MARK: - One tab

private struct SomaTabButton: View {
    let item: SomaTabItem
    let isSelected: Bool
    let showsLabel: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility sizes the label would push the bar past the screen, so
    /// the bar drops to glyphs and grows them, the trade the system bar makes.
    private var rendersLabel: Bool { showsLabel && !typeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(
                        size: rendersLabel
                            ? theme.metrics.tabGlyphSize
                            : theme.metrics.tabGlyphSizeAccessible,
                        weight: .medium
                    ))
                    .symbolVariant(isSelected ? .fill : .none)

                if rendersLabel {
                    Text(item.title)
                        .somaFont(theme.typography.tabLabel)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(
                isSelected ? theme.colors.accent.color : theme.colors.inkSecondary.color
            )
            .padding(.horizontal, 6)
            .frame(
                minWidth: theme.metrics.tabMinWidth,
                maxWidth: .infinity,
                minHeight: max(theme.metrics.tabHeight, theme.metrics.minimumTapTarget)
            )
            .modifier(SomaSelectionBubble(isSelected: isSelected, namespace: namespace))
            .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - The selection bubble

/// The mark behind the current tab.
///
/// A glass shape carrying a `glassEffectID`, not a tinted fill moved by
/// `matchedGeometryEffect`. The distinction is the whole effect: a fill slides
/// from one tab to the next, while a glass shape that leaves one position and
/// appears at another under the same id is morphed by the container, so it
/// stretches and settles the way the system's own indicator does.
///
/// This is glass inside glass, which the house rule otherwise forbids. It is
/// warranted here for the same reason the system does it: the indicator is not
/// decoration laid over content, it is the bar telling you where you are.
private struct SomaSelectionBubble: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    @Environment(\.somaTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content
                .somaGlass(
                    .regular.tint(theme.colors.accent.color.opacity(theme.metrics.selectionFillOpacity)),
                    in: .capsule
                )
                .somaGlassID("selection", in: namespace)
                // Without this the shape materialises at the new tab and fades
                // from the old one. `.matchedGeometry` is what makes it travel
                // and stretch between the two, which is the effect.
                .somaGlassTransition(.matchedGeometry)
        } else {
            content
        }
    }
}
