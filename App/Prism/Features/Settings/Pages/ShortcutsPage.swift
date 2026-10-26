//
//  ShortcutsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the plus in Ask's composer offers, in which order, and which are off.
///
/// The Shortcuts page. Asking is never one of them: it is always
/// there, in the field. A row is moved from its context menu, which a long
/// press opens; the order is what the log hub shows.
struct ShortcutsPage: View {
    @Environment(\.somaTheme) private var theme

    @State private var settings = GlobalSettings.shared

    var body: some View {
        ListScaffold(eyebrow: "Shortcuts", title: "What the plus offers") {
            SomaBrowseGroup(settings.shortcuts.fullOrder) { shortcut in
                row(shortcut)
            }
        }
    }

    private func row(_ shortcut: LogShortcut) -> some View {
        HStack(spacing: theme.metrics.browseRowSpacing) {
            LogShortcutGlyph(shortcut: shortcut)
                .frame(width: theme.metrics.browseGlyphColumn)
            SettingsLine(shortcut.title, detail: shortcut.summary) {
                SettingsSwitch(title: shortcut.title, isOn: Binding(
                    get: { !settings.shortcuts.hidden.contains(shortcut) },
                    set: { isOn in
                        if isOn { settings.shortcuts.hidden.remove(shortcut) } else { settings.shortcuts.hidden.insert(shortcut) }
                    }
                ))
            }
            .padding(.leading, -theme.metrics.browseRowPadding)
        }
        .padding(.leading, theme.metrics.browseRowPadding)
        .contentShape(.rect)
        .contextMenu {
            Button("Move up", systemImage: "arrow.up") { move(shortcut, by: -1) }
                .disabled(settings.shortcuts.fullOrder.first == shortcut)
            Button("Move down", systemImage: "arrow.down") { move(shortcut, by: 1) }
                .disabled(settings.shortcuts.fullOrder.last == shortcut)
        }
        .accessibilityAction(named: "Move up") { move(shortcut, by: -1) }
        .accessibilityAction(named: "Move down") { move(shortcut, by: 1) }
    }

    private func move(_ shortcut: LogShortcut, by step: Int) {
        var order = settings.shortcuts.fullOrder
        guard let index = order.firstIndex(of: shortcut) else { return }
        let target = index + step
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        settings.shortcuts.order = order
    }
}

/// A shortcut's orb, or the record's glyph: what the hub and this page share.
struct LogShortcutGlyph: View {
    let shortcut: LogShortcut

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let side = theme.metrics.miniOrbDiameter * 0.7
        Group {
            if let aspect = shortcut.aspect {
                SomaObjectIcon(aspect: aspect, size: .row)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: theme.metrics.browseGlyphSize))
                    .foregroundStyle(theme.colors.inkPrimary.color)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

#Preview("Shortcuts") {
    NavigationStack { ShortcutsPage() }
}
