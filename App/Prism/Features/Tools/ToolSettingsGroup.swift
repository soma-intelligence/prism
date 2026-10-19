//
//  ToolSettingsGroup.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A card of setting rows for a tool's settings sheet: switches, clock times,
/// durations picked from a short list, plain values, and choices ticked.
struct ToolSettingsGroup: View {
    enum Row: Identifiable {
        case toggle(String, Binding<Bool>)
        /// Minutes after midnight.
        case time(String, Binding<Int>)
        /// Minutes, from a short list, written with the suffix.
        case minutes(String, Binding<Int>, [Int], String)
        case value(String, String)
        case choice(String, Bool, () -> Void)
        case date(String, Binding<Date?>)

        var id: String {
            switch self {
            case .toggle(let t, _), .time(let t, _), .minutes(let t, _, _, _), .value(let t, _), .choice(let t, _, _), .date(let t, _): t
            }
        }
    }

    let rows: [Row]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { ToolHairline() }
                    line(row)
                        .frame(minHeight: theme.metrics.minimumTapTarget)
                }
            }
        }
    }

    @ViewBuilder
    private func line(_ row: Row) -> some View {
        let type = theme.typography
        let colors = theme.colors
        switch row {
        case .toggle(let title, let binding):
            Toggle(isOn: binding) { label(title) }
                .tint(colors.accent.color)
        case .time(let title, let binding):
            DatePicker(selection: Binding(get: { Self.date(minutes: binding.wrappedValue) },
                                          set: { binding.wrappedValue = Self.minutes(of: $0) }),
                       displayedComponents: .hourAndMinute) { label(title) }
        case .minutes(let title, let binding, let options, let suffix):
            HStack {
                label(title)
                Spacer()
                Picker(title, selection: binding) {
                    ForEach(options, id: \.self) { Text("\($0) \(suffix)").tag($0) }
                }
                .labelsHidden()
                .tint(colors.inkSecondary.color)
            }
        case .value(let title, let value):
            HStack {
                label(title)
                Spacer()
                Text(value)
                    .somaFont(type.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        case .choice(let title, let isOn, let action):
            Button(action: action) {
                HStack {
                    label(title)
                    Spacer()
                    if isOn {
                        Image(systemName: "checkmark")
                            .foregroundStyle(colors.accent.color)
                            .accessibilityLabel("Chosen")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        case .date(let title, let binding):
            HStack {
                label(title)
                Spacer()
                if binding.wrappedValue == nil {
                    Button("Set") { binding.wrappedValue = Calendar.current.startOfDay(for: Date()) }
                        .tint(colors.accent.color)
                } else {
                    DatePicker(title, selection: Binding(get: { binding.wrappedValue ?? Date() },
                                                         set: { binding.wrappedValue = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .somaFont(theme.typography.body)
            .foregroundStyle(theme.colors.inkPrimary.color)
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
