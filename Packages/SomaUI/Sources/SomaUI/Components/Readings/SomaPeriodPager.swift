//
//  SomaPeriodPager.swift
//  SomaUI
//

import SwiftUI

/// A chart that pages through time one whole period at a time: a week, three
/// weeks, a month, whatever the page reads over.
///
/// Each period is its own page, drawn only when it comes near the screen, in
/// a scroll view that pages. The finger moves the pages directly, so a swipe
/// runs at the display's rate, and the scroll view settles on a whole page:
/// never a stretch between two. A haptic ticks once per period.
///
/// Above the pages: the chevrons, the span on screen (a tap opens a calendar
/// to jump to any day the data holds) and, when the latest period is not on
/// screen, a way back to today. With Reduce Motion on, a swipe or a chevron
/// changes the page without sliding it.
public struct SomaPeriodPager<Page: View, Fixed: View>: View {
    private let pages: [DateInterval]
    @Binding private var selection: Int
    private let readout: Text?
    private let isLocked: Bool
    private let title: (DateInterval) -> String
    private let page: (Int) -> Page
    private let fixed: (Int) -> Fixed

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The page the scroll view rests on. Kept apart from `selection` so a
    /// change made here (a chevron, a date) can choose its own animation.
    @State private var scrolled: Int?
    @State private var choosing = false

    /// - Parameters:
    ///   - pages: the periods, oldest first; the last one is the latest.
    ///   - selection: the index of the period on screen.
    ///   - readout: what replaces the span while a reading is held.
    ///   - isLocked: true while a finger holds a reading, so a drag reads
    ///     the chart instead of paging it.
    ///   - title: the span as written above the pages.
    ///   - page: the chart for one period.
    ///   - fixed: what stays put over the pages while they slide, drawn for
    ///     the period on screen: a chart's value axis, so its numbers never
    ///     travel into the middle with the page leaving (owner, 2026-10-24).
    public init(
        pages: [DateInterval],
        selection: Binding<Int>,
        readout: Text? = nil,
        isLocked: Bool = false,
        title: @escaping (DateInterval) -> String = SomaPeriodPagerTitle.span,
        @ViewBuilder page: @escaping (Int) -> Page,
        @ViewBuilder fixed: @escaping (Int) -> Fixed
    ) {
        self.pages = pages
        _selection = selection
        self.readout = readout
        self.isLocked = isLocked
        self.title = title
        self.page = page
        self.fixed = fixed
    }

    private var latest: Int { max(0, pages.count - 1) }
    private var shown: Int { min(max(0, selection), latest) }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            header
            pager
                .overlay {
                    fixed(shown)
                        .allowsHitTesting(false)
                        .animation(reduceMotion ? nil : theme.motion.standard, value: shown)
                }
        }
    }

    // MARK: - Header

    private var header: some View {
        let colors = theme.colors

        return HStack(spacing: 0) {
            chevron("chevron.left", label: "Earlier", enabled: shown > 0) { move(to: shown - 1) }
            Spacer(minLength: 0)
            if let readout {
                readout
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
            } else if let span = pages[safe: shown] {
                Button { choosing = true } label: {
                    HStack(spacing: theme.metrics.spaceS / 2) {
                        Text(title(span))
                            .foregroundStyle(colors.inkPrimary.color)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .somaFont(theme.typography.callout)
                    .lineLimit(1)
                    .frame(minHeight: theme.metrics.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Choose a date"))
                .popover(isPresented: $choosing) { calendar }
            }
            Spacer(minLength: 0)
            if shown < latest, readout == nil {
                Button { move(to: latest) } label: {
                    Text("Today")
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(colors.accent.color)
                        .frame(minHeight: theme.metrics.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            chevron("chevron.right", label: "Later", enabled: shown < latest) { move(to: shown + 1) }
        }
        .animation(reduceMotion ? nil : theme.motion.fade, value: shown < latest)
    }

    private func chevron(_ symbol: String, label: LocalizedStringResource, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(enabled ? theme.colors.inkPrimary.color : theme.colors.inkSecondary.color.opacity(0.4))
                .frame(width: theme.metrics.minimumTapTarget, height: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    /// The month calendar in a popover, bounded to the days the pages hold:
    /// a tap on a day moves to the period that holds it.
    private var calendar: some View {
        let first = pages.first?.start ?? .now
        let last = max(first, min(Date.now, (pages.last?.end ?? .now).addingTimeInterval(-1)))
        let current = pages[safe: shown].map { min(max($0.end.addingTimeInterval(-1), first), last) } ?? last

        return DatePicker(
            "Date",
            selection: Binding(get: { current }, set: { date in
                choosing = false
                move(to: index(of: date))
            }),
            in: first...last,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(theme.colors.accent.color)
        // A week of days side by side, each a whole tap target wide: a
        // popover otherwise squeezes the month to the width of its arrow.
        .frame(minWidth: theme.metrics.minimumTapTarget * 7)
        .padding(theme.metrics.cardSpacing)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Pages

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    page(index)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolled)
        .defaultScrollAnchor(.trailing)
        // Under Reduce Motion the pages do not slide: a swipe is read here
        // and the page changes in place.
        .scrollDisabled(isLocked || reduceMotion)
        .simultaneousGesture(stillSwipe, including: reduceMotion && !isLocked ? .all : .subviews)
        // A new set of periods (another span picked) starts over at the
        // latest one.
        .id(PagesKey(pages))
        .onAppear { scrolled = shown }
        .onChange(of: scrolled) { _, now in
            if let now, now != selection { selection = now }
        }
        .onChange(of: selection) { _, now in
            if scrolled != now { scrolled = min(max(0, now), latest) }
        }
        .sensoryFeedback(.selection, trigger: shown)
    }

    private var stillSwipe: some Gesture {
        DragGesture(minimumDistance: theme.metrics.minimumTapTarget / 2)
            .onEnded { value in
                let across = value.translation.width
                guard abs(across) > abs(value.translation.height), abs(across) > theme.metrics.minimumTapTarget else { return }
                move(to: across > 0 ? shown - 1 : shown + 1)
            }
    }

    /// Moves to page `index`, sliding unless Reduce Motion is on.
    private func move(to index: Int) {
        let target = min(max(0, index), latest)
        guard target != shown || scrolled != target else { return }
        withAnimation(reduceMotion ? nil : theme.motion.standard) {
            scrolled = target
        }
        selection = target
    }

    /// The period that holds `date`, clamped to the run.
    private func index(of date: Date) -> Int {
        if let found = pages.lastIndex(where: { $0.start <= date }) { return found }
        return 0
    }

    private struct PagesKey: Hashable {
        var first: Date?
        var last: Date?
        var count: Int

        init(_ pages: [DateInterval]) {
            first = pages.first?.start
            last = pages.last?.end
            count = pages.count
        }
    }
}

/// How a pager writes the span on screen.
public enum SomaPeriodPagerTitle {
    /// "Oct 24" for one day, "Sep 25 to Oct 24" within a year, and the years
    /// written when the span crosses one or is not this year's.
    public static func span(_ interval: DateInterval) -> String {
        let calendar = Calendar.current
        let first = interval.start
        let last = max(first, interval.end.addingTimeInterval(-1))
        let thisYear = calendar.component(.year, from: .now)
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        let showYear = !sameYear || calendar.component(.year, from: last) != thisYear
        let style = showYear ? Date.FormatStyle().month(.abbreviated).day().year() : Date.FormatStyle().month(.abbreviated).day()
        if calendar.isDate(first, inSameDayAs: last) { return first.formatted(style) }
        return "\(first.formatted(style)) to \(last.formatted(style))"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Period pager") {
    @Previewable @State var selection = 3
    let calendar = Calendar.current
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
    let pages = (0..<4).reversed().map { back in
        let close = calendar.date(byAdding: .day, value: -7 * back, to: end) ?? end
        return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: close) ?? close, end: close)
    }
    ZStack {
        SomaPreviewBackdrop()
        SomaPeriodPager(pages: pages, selection: $selection) { index in
            Text(SomaPeriodPagerTitle.span(pages[index]))
                .frame(maxWidth: .infinity, minHeight: 160)
        }
        .padding()
    }
}

public extension SomaPeriodPager where Fixed == EmptyView {
    /// Pages with nothing held still over them.
    init(
        pages: [DateInterval],
        selection: Binding<Int>,
        readout: Text? = nil,
        isLocked: Bool = false,
        title: @escaping (DateInterval) -> String = SomaPeriodPagerTitle.span,
        @ViewBuilder page: @escaping (Int) -> Page
    ) {
        self.init(pages: pages, selection: selection, readout: readout, isLocked: isLocked, title: title,
                  page: page, fixed: { _ in EmptyView() })
    }
}
