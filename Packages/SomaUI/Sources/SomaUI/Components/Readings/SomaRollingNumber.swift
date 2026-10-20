//
//  SomaRollingNumber.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// A number that rolls digit by digit to its new value, on the theme's
    /// ``SomaMotion/numberRoll`` spring, whenever `text` changes: a kept
    /// value giving way to a fresh read, or a refresh. Digits roll up when
    /// the number grew and down when it fell. A dash becoming a number rolls
    /// in the same way.
    ///
    /// Every number that changes in place goes through this one modifier,
    /// the stat rows, tiles and rows here and the app's own cards, so they
    /// all move alike. Under Reduce Motion the number simply changes.
    ///
    /// A number with its unit or words after it holds its width through
    /// the roll: a number losing a digit (105 to 98) keeps its room until
    /// the digits have rolled, then gives it back on the same spring, so
    /// the outgoing digits never run over the unit and the unit glides
    /// rather than jumps.
    ///
    /// - Parameters:
    ///   - text: what the number reads, as shown; nil for a dash.
    ///   - holdsWidth: true when something sits after the number on its
    ///     line. Leave it off for a number at the end of a line, where a
    ///     held width would only nudge it.
    func somaRollingNumber(_ text: String?, holdsWidth: Bool = false) -> some View {
        modifier(SomaRollingNumber(text: text, holdsWidth: holdsWidth))
    }
}

/// The roll behind `somaRollingNumber(_:holdsWidth:)`.
struct SomaRollingNumber: ViewModifier {
    let text: String?
    let holdsWidth: Bool

    /// The text the held width was measured on: the last one to finish
    /// rolling.
    @State private var settled: String?
    /// The width of the settled text.
    @State private var width: CGFloat?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: String?, holdsWidth: Bool) {
        self.text = text
        self.holdsWidth = holdsWidth
        _settled = State(initialValue: text)
    }

    func body(content: Content) -> some View {
        let holding = holdsWidth && !reduceMotion && text != settled
        content
            .contentTransition(transition)
            .animation(reduceMotion ? nil : theme.motion.numberRoll, value: text)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured in
                if text == settled { width = measured }
            }
            .frame(minWidth: holding ? width : nil, alignment: .leading)
            .task(id: text) {
                guard holdsWidth, text != settled else { return }
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(theme.motion.numberRollHold))
                    guard !Task.isCancelled else { return }
                }
                withAnimation(reduceMotion ? nil : theme.motion.numberRoll) { settled = text }
            }
    }

    private var transition: ContentTransition {
        if reduceMotion { return .identity }
        guard let value = Self.value(in: text) else { return .numericText() }
        return .numericText(value: value)
    }

    /// The number a formatted reading carries, for the direction of the
    /// roll: "1,204" is 1204, "36.6" is 36.6, "-0.4" is minus 0.4. Nil for a
    /// dash or for words with no digit in them. A range ("40 to 85") reads
    /// as its first number.
    nonisolated static func value(in text: String?) -> Double? {
        guard let text else { return nil }
        var digits = ""
        var started = false
        for character in text {
            if character.isASCII, character.isNumber {
                digits.append(character)
                started = true
            } else if character == "." || character == "," {
                // A separator between digits: a decimal point when one or
                // two digits follow it, else grouping. Decided below.
                if started { digits.append(character) }
            } else if character == "-" || character == "\u{2212}" {
                if !started { digits = "-" }
            } else if started, character != "\u{202F}", character != "\u{00A0}" {
                break
            }
        }
        // Grouping separators are those followed by exactly three digits.
        let parts = digits.split(separator: ",", omittingEmptySubsequences: false)
        var cleaned = digits
        if parts.count > 1, parts.dropFirst().allSatisfy({ $0.count == 3 }) {
            cleaned = parts.joined()
        } else {
            cleaned = digits.replacingOccurrences(of: ",", with: ".")
        }
        while cleaned.hasSuffix(".") { cleaned.removeLast() }
        return Double(cleaned)
    }
}

#Preview("Rolling number") {
    @Previewable @State var value = 58.0
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaStatRow([
                SomaStat("HRV", value: value.formatted(.number.precision(.fractionLength(0))), unit: "ms"),
                SomaStat("Resting HR", value: (value - 4).formatted(.number.precision(.fractionLength(0))), unit: "bpm"),
                SomaStat("VO2 max", value: (value / 1.3).formatted(.number.precision(.fractionLength(1)))),
            ])
            Button("Change") { value = Double(Int.random(in: 40...90)) }
        }
        .padding()
    }
}
