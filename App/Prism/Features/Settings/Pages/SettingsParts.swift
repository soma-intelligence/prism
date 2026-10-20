//
//  SettingsParts.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A kicker over a browse group, the way the settings sheet sets its sections.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .padding(.leading, theme.metrics.browseRowPadding)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// The small print under a group.
struct SettingsFootnote: View {
    let text: LocalizedStringKey

    @Environment(\.somaTheme) private var theme

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, theme.metrics.browseRowPadding)
    }
}

/// A settings line with a title, an optional line under it, and whatever the
/// trailing edge carries: a switch, a value, a menu.
///
/// ``SomaBrowseRow`` holds one line of title; several settings pages need the
/// explanation under each switch, so this lays the two out and keeps
/// the row's padding and height from the theme.
struct SettingsLine<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        let metrics = theme.metrics
        HStack(spacing: metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if let detail {
                    Text(detail)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: metrics.browseRowSpacing)
            trailing
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.browseRowMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The switch every settings line uses: Soma's own, which reads in dark
/// appearance where the system switch in the accent does not.
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SomaSwitch(Text(title), isOn: $isOn)
    }
}

/// A value on the trailing edge that opens a menu of the others.
struct SettingsMenuValue<Value: Hashable>: View {
    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            HStack(spacing: theme.metrics.scoreLabelSpacing) {
                Text(label(selection))
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            .frame(minHeight: theme.metrics.minimumTapTarget)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(label(selection)))
    }
}

/// A time on the trailing edge, set with the system's own picker.
struct SettingsTimeValue: View {
    let title: String
    @Binding var time: ClockTime

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                time = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        )
    }
}

/// One item of a data driven browse group whose rows are built by hand.
struct SettingsItem: Identifiable, Hashable {
    let id: String
}

extension Array where Element == SettingsItem {
    /// `["a", "b"]` as items, for a group whose rows switch on the id.
    static func items(_ ids: String...) -> [SettingsItem] { ids.map(SettingsItem.init) }
}

// MARK: - Glyph rows

/// The glyph a settings row leads with: monochrome ink in the row's glyph
/// column, as Apple's own lists set it. Colour is kept for state (a dot), never
/// for the kind of row.
struct SettingsGlyph: View {
    let symbol: String
    var role: SomaRowRole = .standard
    var scale: CGFloat = 1

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: theme.metrics.settingsGlyphSize * scale, weight: .regular))
            .foregroundStyle(role == .destructive ? theme.colors.danger.color : theme.colors.inkPrimary.color)
            .frame(width: theme.metrics.browseGlyphColumn * scale, height: theme.metrics.browseGlyphColumn * scale)
            .accessibilityHidden(true)
    }
}

/// A small state dot: green when something is on or connected, amber when it
/// is off. The one coloured mark a group carries.
struct SettingsStateDot: View {
    let isOn: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Circle()
            .fill(isOn ? theme.colors.statusNormal.color : theme.colors.statusOut.color)
            .frame(width: theme.metrics.chartDotDiameter, height: theme.metrics.chartDotDiameter)
            .accessibilityHidden(true)
    }
}

/// A settings row: the glyph, the title, the value on the trailing edge, and
/// a chevron when it opens something.
///
/// Laid out exactly like ``SomaBrowseRow`` (same padding, height and glyph
/// column), so it sits in a ``SomaBrowseGroup`` and its hairlines start under
/// the title; unlike it, the glyph is ink rather than the accent, and the
/// trailing edge takes a view (a state dot, the app icon).
struct SettingsTileRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var role: SomaRowRole = .standard
    var opensSomething = true
    let action: (() -> Void)?
    let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    init(
        _ title: String, symbol: String, detail: String? = nil,
        role: SomaRowRole = .standard, opensSomething: Bool = true,
        action: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.role = role
        self.opensSomething = opensSomething
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        if let action {
            Button(action: action) { line }
                .buttonStyle(SettingsRowPressStyle())
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(detail ?? ""))
        } else {
            line
        }
    }

    private var line: some View {
        let metrics = theme.metrics
        return HStack(spacing: metrics.browseRowSpacing) {
            SettingsGlyph(symbol: symbol, role: role)
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(role == .destructive ? theme.colors.danger.color : theme.colors.inkPrimary.color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: metrics.browseRowSpacing)
            trailing
            if let detail {
                Text(detail)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .lineLimit(1)
            }
            if opensSomething {
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: metrics.browseRowMinHeight)
        .contentShape(.rect)
    }
}

extension SettingsTileRow where Trailing == EmptyView {
    init(
        _ title: String, symbol: String, detail: String? = nil,
        role: SomaRowRole = .standard, opensSomething: Bool = true, action: (() -> Void)? = nil
    ) {
        self.init(title, symbol: symbol, detail: detail, role: role,
                  opensSomething: opensSomething, action: action) { EmptyView() }
    }
}

/// A settings line led by a glyph, with a line under the title and whatever
/// the trailing edge carries: the shape of a notifications row.
struct SettingsTileLine<Trailing: View>: View {
    let title: String
    let symbol: String
    let detail: String?
    let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    init(_ title: String, symbol: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        let metrics = theme.metrics
        HStack(spacing: metrics.browseRowSpacing) {
            SettingsGlyph(symbol: symbol)
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if let detail {
                    Text(detail)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: metrics.browseRowSpacing)
            trailing
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.browseRowMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A wash across the whole row under a finger, as a list row highlights.
struct SettingsRowPressStyle: ButtonStyle {
    @Environment(\.somaTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                configuration.isPressed
                    ? theme.colors.inkPrimary.color.opacity(theme.metrics.browsePressOpacity)
                    : Color.clear
            )
    }
}
