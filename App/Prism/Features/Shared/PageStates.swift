//
//  PageStates.swift
//  Prism
//

import SwiftUI
import SomaUI

// The states every page passes through on its way to its numbers: reading,
// nothing there, something went wrong, and done. Each is drawn in the page's
// own shapes rather than as a stock spinner or a picture, so a page that is
// still reading already looks like the page it is about to be.
//
// These sit next to `NoteCard` until SomaUI moves into this repository; they
// read only existing tokens, so they move across unchanged.

// MARK: - Reading

extension View {
    /// Draws this view as its own placeholder while `isActive`: the real
    /// layout, its text blocked out, breathing slowly.
    ///
    /// The layout is the one the values will land in, so nothing jumps when
    /// they arrive. A placeholder is never a dash: the dash says the store
    /// holds nothing, and this says the answer is on its way.
    func readingPlaceholder(_ isActive: Bool) -> some View {
        modifier(ReadingPlaceholder(isActive: isActive))
    }
}

private struct ReadingPlaceholder: ViewModifier {
    let isActive: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExhaling = false

    func body(content: Content) -> some View {
        // A breath, not a shimmer: a sweep of light reads as a template, a
        // slow fade reads as the page waiting with you. Under Reduce Motion
        // it holds at the lighter step.
        let low = theme.metrics.glowOpacityRange.lowerBound
        content
            .redacted(reason: isActive ? .placeholder : [])
            .opacity(isActive && (isExhaling || reduceMotion) ? 1 - low : 1)
            .allowsHitTesting(!isActive)
            .accessibilityHidden(isActive)
            .onChange(of: isActive, initial: true) { _, active in
                guard active, !reduceMotion else {
                    isExhaling = false
                    return
                }
                withAnimation(.easeInOut(duration: theme.motion.breathDuration).repeatForever(autoreverses: true)) {
                    isExhaling = true
                }
            }
    }
}

/// A list still being read: rows in the shape of the real ones, breathing.
///
/// Stands in for a `SomaBrowseGroup` while its rows are read, where a spinner
/// in the middle of an empty page said nothing about what was coming.
struct ReadingRows: View {
    /// How many rows to hold the place of.
    var count = 4

    var body: some View {
        // Titles of a few lengths, so the block reads as a list and not as a
        // stack of identical bars. Redacted, the words never show.
        let titles = ["Resting heart rate", "Steps", "Heart rate variability", "Sleep"]
        let rows = (0..<count).map { PlaceholderRow(id: $0, title: titles[$0 % titles.count]) }

        SomaBrowseGroup(rows, hasGlyphs: false) { row in
            SomaBrowseRow(title: row.title, opensSomething: false)
        }
        .readingPlaceholder(true)
        .accessibilityElement()
        .accessibilityLabel(Text("Reading"))
    }

    private struct PlaceholderRow: Identifiable {
        let id: Int
        let title: String
    }
}

// MARK: - Nothing there, or something wrong

/// A page or a part with nothing to draw, saying why and what to do.
///
/// Quieter than a card of content: no surface of its own, a small glyph in the
/// secondary ink, the words, and at most one action. The accent appears only
/// on that action, which is the one thing it is for.
struct StateNote: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
            Image(systemName: symbol)
                .font(.system(size: metrics.browseGlyphSize))
                .foregroundStyle(colors.inkSecondary.color)
                .accessibilityHidden(true)

            Text(title)
                .somaFont(type.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.accent.color)
                        .frame(minHeight: metrics.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(SomaGlassPressStyle(scales: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, metrics.cardPadding)
        .accessibilityElement(children: .contain)
    }
}

/// Words for a Health read that failed, in a person's terms.
///
/// The error itself is for a developer: it names a domain and a code, which
/// tells someone holding a phone nothing they can act on. A Debug build still
/// prints it under the words.
enum HealthProblemWords {
    static let title = "Apple Health didn't answer"
    static let message = "Soma couldn't read your data just now. Try again, or check that Soma is allowed in Settings, Health, Data Access & Devices."

    /// The message, with the underlying error appended in Debug builds.
    static func message(detail: String) -> String {
#if DEBUG
        "\(message)\n\n\(detail)"
#else
        message
#endif
    }
}

// MARK: - Done

/// Says, for a moment, that something a person did has landed.
///
/// A save that only closed its sheet left the person to wonder whether it
/// took. One short line drops in at the top of the window with a success tap,
/// holds for a breath and goes. A save that reached Soma but not Apple Health
/// says that instead, with a warning tap, rather than letting a refused write
/// pass for a good one.
@MainActor
@Observable
final class Confirmations {
    static let shared = Confirmations()

    struct Item: Equatable, Identifiable {
        enum Kind { case done, notice }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    private(set) var current: Item?

    /// Shows `text` as done.
    func done(_ text: String) { show(Item(kind: .done, text: text)) }

    /// Shows `text` as landed with a caveat.
    func notice(_ text: String) { show(Item(kind: .notice, text: text)) }

    /// After a log that is kept in Soma and also written to Apple Health:
    /// done when Health took it, a notice when it did not.
    func logged(_ what: String, reachedHealth: Bool) {
        if reachedHealth || !TrackHealthWriter.isAvailable {
            done("\(what) logged")
        } else {
            notice("\(what) saved in Soma, not in Apple Health.")
        }
    }

    func clear(_ item: Item) {
        if current == item { current = nil }
    }

    private func show(_ item: Item) {
        current = item
        AccessibilityNotification.Announcement(item.text).post()
    }
}

extension View {
    /// Where confirmations appear: once, at the root of a window.
    func confirmationHost() -> some View {
        modifier(ConfirmationHost())
    }
}

private struct ConfirmationHost: ViewModifier {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var confirmations: Confirmations { .shared }

    func body(content: Content) -> some View {
        let current = confirmations.current

        content
            .overlay(alignment: .top) {
                if let current {
                    ConfirmationPill(item: current)
                        .padding(.top, theme.metrics.cardSpacing)
                        .padding(.horizontal, theme.metrics.pagePadding)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .id(current.id)
                        .task(id: current.id) {
                            // Held for one breath, then let go.
                            try? await Task.sleep(for: .seconds(theme.motion.breathDuration))
                            withAnimation(reduceMotion ? nil : theme.motion.fold) { confirmations.clear(current) }
                        }
                        .onTapGesture {
                            withAnimation(reduceMotion ? nil : theme.motion.fold) { confirmations.clear(current) }
                        }
                }
            }
            .animation(reduceMotion ? nil : theme.motion.fold, value: current)
            .sensoryFeedback(trigger: current) { _, new in
                switch new?.kind {
                case .done: .success
                case .notice: .warning
                case nil: nil
                }
            }
    }
}

private struct ConfirmationPill: View {
    let item: Confirmations.Item

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let isDone = item.kind == .done

        HStack(spacing: metrics.moveRowGap) {
            Image(systemName: isDone ? "checkmark" : "exclamationmark")
                .foregroundStyle(isDone ? colors.accent.color : colors.inkSecondary.color)
                .accessibilityHidden(true)
            Text(item.text)
                .somaFont(theme.typography.callout)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(2)
        }
        .padding(.horizontal, metrics.cardPadding)
        .frame(minHeight: metrics.chromeCapsuleHeight)
        .somaGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Page states") {
    SomaPageScroll {
        VStack(alignment: .leading, spacing: 24) {
            ReadingRows(count: 3)
            StateNote(symbol: "heart.text.square", title: HealthProblemWords.title,
                      message: HealthProblemWords.message, actionTitle: "Try again", action: {})
            StateNote(symbol: "tray", title: "No records yet",
                      message: "Readings appear here as soon as Apple Health has some.")
            Button("Confirm") { Confirmations.shared.done("Weight logged") }
            Button("Notice") { Confirmations.shared.logged("Water", reachedHealth: false) }
        }
        .padding()
    }
    .confirmationHost()
    .somaTheme(.standard)
}
#endif
