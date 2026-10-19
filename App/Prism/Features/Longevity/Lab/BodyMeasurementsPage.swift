//
//  BodyMeasurementsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Tape measurements: five places on a figure, each against the first
/// reading on record, the entries, and the guided measure at home.
///
/// Measurements are entered by the person and kept on the phone; the waist
/// is also written to Health, which keeps a waist type and no other.
struct BodyMeasurementsPage: View {
    @State private var store = BodyMeasurementStore.shared
    @State private var isMeasuring = false
    @State private var editing: BodyMeasurementEntry?

    var body: some View {
        let latest = store.entries.first
        TabPartScaffold(
            aspect: nil,
            eyebrow: latest.map { "Last measured · \($0.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))" },
            title: headline,
            reason: reason,
            stats: []
        ) {
            SomaChartCard(
                eyebrow: "Measurements",
                value: latestValue(.waist).flatMap { LabMath.format($0, decimals: 1) },
                unit: waistUnit,
                note: latest == nil ? "Five places, measured the same way each time." : "Five places, measured the same way each time since \(store.entries.last?.date.labDay ?? "")."
            ) {
                MeasurementFigure(values: Dictionary(uniqueKeysWithValues: BodyMeasurementKind.allCases.map { ($0, latestValue($0)) }))
            }
            if latest != nil {
                LabBandCard(title: "Every measurement", eyebrow: store.entries.last.map { "Since \($0.date.labDay)" },
                            items: BodyMeasurementKind.allCases.map(item))
                LabRowGroup(heading: "Entries", rows: store.entries.prefix(8).map { entry in
                    LabRow(entry.date.labDay, detail: "\(entry.values.count) \(entry.values.count == 1 ? "place" : "places"), \(entry.place.title)",
                           action: { editing = entry })
                })
            }
            SomaActionCard(
                eyebrow: "Measure",
                title: "Measure at home",
                detail: "A tape and the guide, before breakfast. Two minutes.",
                actionTitle: "Start",
                action: { isMeasuring = true }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
        }
        .navigationTitle("Body Measurements")
        #if os(iOS)
        .fullScreenCover(isPresented: $isMeasuring) { MeasurementCaptureFlow() }
        #else
        .sheet(isPresented: $isMeasuring) { MeasurementCaptureFlow() }
        #endif
        .sheet(item: $editing) { entry in
            NavigationStack {
                MeasurementReviewView(entry: entry, isNew: false) { editing = nil }
            }
        }
    }

    private var waistUnit: String? {
        guard let span = store.span(.waist) else { return "cm waist" }
        let change = span.latest.1 - span.first.1
        guard abs(change) >= 0.5 else { return "cm waist" }
        return "cm waist, \(change < 0 ? "down" : "up") \(LabMath.format(abs(change), decimals: 1) ?? "")"
    }

    private func latestValue(_ kind: BodyMeasurementKind) -> Double? { store.span(kind)?.latest.1 }

    private func item(_ kind: BodyMeasurementKind) -> LabBandItem {
        guard let span = store.span(kind) else {
            return LabBandItem(id: kind.id, title: kind.title, detail: "not measured yet", value: nil)
        }
        let first = span.first.1, latest = span.latest.1
        let lo = min(first, latest) - 5, hi = max(first, latest) + 5
        func position(_ v: Double) -> Double { (v - lo) / (hi - lo) }
        return LabBandItem(
            id: kind.id, title: kind.title,
            detail: "\(LabMath.format(first, decimals: 1) ?? "-") on \(span.first.0.labDay)",
            value: "\(LabMath.format(latest, decimals: 1) ?? "-") cm",
            band: min(position(first), position(latest))...max(position(first), position(latest)),
            position: position(latest))
    }

    private var headline: String {
        guard let waist = store.span(.waist) else {
            return store.entries.isEmpty ? "No measurements yet." : "Measured, waist to come."
        }
        let change = waist.latest.1 - waist.first.1
        if abs(change) < 0.5 { return "The waist is holding." }
        let amount = LabMath.format(abs(change), decimals: abs(change) >= 2 ? 0 : 1) ?? ""
        return change < 0 ? "The waist came in \(amount) cm." : "The waist went out \(amount) cm."
    }

    private var reason: String {
        guard store.entries.count >= 2 else {
            return "A tape at five places shows a change in shape the scale alone would hide. Measure the same way each time and the lines start with the second entry."
        }
        let grew = BodyMeasurementKind.allCases.filter { kind in store.span(kind).map { $0.latest.1 - $0.first.1 >= 0.5 } ?? false }
        let narrowed = BodyMeasurementKind.allCases.filter { kind in store.span(kind).map { $0.latest.1 - $0.first.1 <= -0.5 } ?? false }
        func names(_ kinds: [BodyMeasurementKind]) -> String { kinds.map { $0.title.lowercased() }.joined(separator: " and ") }
        switch (grew.isEmpty, narrowed.isEmpty) {
        case (false, false): return "The \(names(grew)) grew while the \(names(narrowed)) narrowed. That is a change in shape the scale alone would hide."
        case (false, true): return "The \(names(grew)) grew since the first entry."
        case (true, false): return "The \(names(narrowed)) narrowed since the first entry."
        case (true, true): return "Every place is within half a centimetre of the first entry."
        }
    }
}

/// A figure with the five places labelled around it. The guide draws it
/// dashed with a ring at the place being measured.
struct MeasurementFigure: View {
    var values: [BodyMeasurementKind: Double?] = [:]
    /// Draws the guide: dashed outline, the ring at this place, no labels.
    var guide: BodyMeasurementKind?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let fill = theme.aspects[.body].identity.color.opacity(theme.metrics.chartContextOpacity * 0.5)
        let leader = colors.inkSecondary.color.opacity(0.6)
        GeometryReader { proxy in
            let cx = proxy.size.width / 2
            let s = proxy.size.height / 230
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let head = CGRect(x: cx - 13 * s, y: 0, width: 26 * s, height: 26 * s)
                    let parts: [(CGRect, CGFloat)] = [
                        (CGRect(x: cx - 24 * s, y: 32 * s, width: 48 * s, height: 84 * s), 12 * s),
                        (CGRect(x: cx - 45 * s, y: 36 * s, width: 15 * s, height: 76 * s), 7 * s),
                        (CGRect(x: cx + 30 * s, y: 36 * s, width: 15 * s, height: 76 * s), 7 * s),
                        (CGRect(x: cx - 23 * s, y: 122 * s, width: 21 * s, height: 90 * s), 9 * s),
                        (CGRect(x: cx + 2 * s, y: 122 * s, width: 21 * s, height: 90 * s), 9 * s),
                    ]
                    if guide != nil {
                        let dash = StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                        context.stroke(Path(ellipseIn: head), with: .color(leader), style: dash)
                        for (rect, radius) in parts {
                            context.stroke(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(leader), style: dash)
                        }
                        if let guide {
                            let ring = ringRect(guide, cx: cx, s: s)
                            context.stroke(Path(ellipseIn: ring), with: .color(colors.accent.color), lineWidth: 3)
                        }
                    } else {
                        context.fill(Path(ellipseIn: head), with: .color(fill))
                        for (rect, radius) in parts {
                            context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(fill))
                        }
                        var lines = Path()
                        for kind in BodyMeasurementKind.allCases {
                            let (from, to) = leaderLine(kind, cx: cx, s: s)
                            lines.move(to: from)
                            lines.addLine(to: to)
                        }
                        context.stroke(lines, with: .color(leader), lineWidth: 1)
                    }
                }
                if guide == nil {
                    ForEach(BodyMeasurementKind.allCases) { kind in
                        let (_, end) = leaderLine(kind, cx: cx, s: s)
                        let text = "\(kind.title) \(values[kind].flatMap { $0 }.flatMap { LabMath.format($0, decimals: 1) }.map { "\($0) cm" } ?? "-")"
                        Text(verbatim: text)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize()
                            .frame(width: end.x < cx ? end.x - 4 : nil, alignment: .trailing)
                            .offset(x: end.x < cx ? 0 : end.x + 4, y: end.y - 8)
                    }
                }
            }
        }
        .frame(height: guide == nil ? theme.metrics.bodyMapHeight : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(guide.map { "Guide: measure the \($0.title.lowercased())" } ?? "Measurements on a figure"))
    }

    private func leaderLine(_ kind: BodyMeasurementKind, cx: CGFloat, s: CGFloat) -> (CGPoint, CGPoint) {
        switch kind {
        case .chest: (CGPoint(x: cx + 20 * s, y: 44 * s), CGPoint(x: cx + 62 * s, y: 44 * s))
        case .waist: (CGPoint(x: cx + 24 * s, y: 84 * s), CGPoint(x: cx + 62 * s, y: 84 * s))
        case .hips: (CGPoint(x: cx + 24 * s, y: 112 * s), CGPoint(x: cx + 62 * s, y: 112 * s))
        case .arm: (CGPoint(x: cx - 45 * s, y: 60 * s), CGPoint(x: cx - 62 * s, y: 60 * s))
        case .thigh: (CGPoint(x: cx - 23 * s, y: 150 * s), CGPoint(x: cx - 62 * s, y: 150 * s))
        }
    }

    private func ringRect(_ kind: BodyMeasurementKind, cx: CGFloat, s: CGFloat) -> CGRect {
        switch kind {
        case .chest: CGRect(x: cx - 34 * s, y: 40 * s, width: 68 * s, height: 12 * s)
        case .waist: CGRect(x: cx - 34 * s, y: 78 * s, width: 68 * s, height: 12 * s)
        case .hips: CGRect(x: cx - 34 * s, y: 110 * s, width: 68 * s, height: 12 * s)
        case .arm: CGRect(x: cx - 50 * s, y: 54 * s, width: 25 * s, height: 8 * s)
        case .thigh: CGRect(x: cx - 28 * s, y: 146 * s, width: 31 * s, height: 9 * s)
        }
    }
}

// MARK: - Capture

/// The guided measure: one place at a time, the guide showing where the
/// tape goes, the value set on a ruler, Skip or Next, then the review.
struct MeasurementCaptureFlow: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = BodyMeasurementStore.shared
    @State private var index = 0
    @State private var values: [BodyMeasurementKind: Double] = [:]
    @State private var current: Double = BodyMeasurementKind.waist.startingValue
    @State private var isReviewing = false

    private let kinds = BodyMeasurementKind.allCases

    var body: some View {
        NavigationStack {
            let kind = kinds[index]
            VStack(spacing: theme.metrics.cardSpacing) {
                LabEyebrow("\(kind.title) · \(index + 1) of \(kinds.count)")
                SomaCard {
                    MeasurementFigure(guide: kind)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical)
                }
                .frame(maxHeight: .infinity)
                Text(kind.howTo)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(LabMath.format(current, decimals: 1) ?? "-")
                        .somaFont(theme.typography.metric)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    Text("cm")
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                LabRuler(value: $current, range: 20...200, step: 0.5, labelEvery: 1)
                HStack(spacing: theme.metrics.cardSpacing) {
                    LabSecondaryButton(title: "Skip") { advance(saving: false) }
                        .frame(maxWidth: 140)
                    LabPrimaryButton(title: index == kinds.count - 1 ? "Review" : "Next") { advance(saving: true) }
                }
            }
            .padding(theme.metrics.pagePadding)
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle("Measure")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isReviewing) {
                MeasurementReviewView(
                    entry: BodyMeasurementEntry(date: .now, values: values),
                    isNew: true
                ) { dismiss() }
            }
            .onAppear { current = start(for: kinds[index]) }
        }
    }

    private func start(for kind: BodyMeasurementKind) -> Double {
        values[kind] ?? store.span(kind)?.latest.1 ?? kind.startingValue
    }

    private func advance(saving: Bool) {
        let kind = kinds[index]
        if saving { values[kind] = current } else { values[kind] = nil }
        if index < kinds.count - 1 {
            index += 1
            current = start(for: kinds[index])
        } else {
            isReviewing = true
        }
    }
}

/// Review before saving: each place with its value or a dash, the date, and
/// the save, which also writes the waist to Health.
struct MeasurementReviewView: View {
    @State var entry: BodyMeasurementEntry
    let isNew: Bool
    let onDone: () -> Void

    @Environment(\.somaTheme) private var theme
    @State private var store = BodyMeasurementStore.shared
    @State private var status: String?

    var body: some View {
        let measured = entry.values.count
        let skipped = BodyMeasurementKind.allCases.filter { entry.values[$0] == nil }
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                SomaPageHero(
                    eyebrow: "\(Calendar.current.isDateInToday(entry.date) ? "Today" : entry.date.labDay) · \(measured) of five places",
                    title: skipped.isEmpty ? "All five measured." : "\(measured) measured, \(skipped.count) skipped.",
                    reason: skipped.isEmpty
                        ? "Save and they land beside your earlier entries."
                        : "The \(skipped.map { $0.title.lowercased() }.joined(separator: " and ")) \(skipped.count == 1 ? "was" : "were") skipped: leave \(skipped.count == 1 ? "it" : "them") blank, or measure again."
                )
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    SomaBrowseGroup(BodyMeasurementKind.allCases, hasGlyphs: false) { kind in
                        SomaBrowseRow(title: kind.title,
                                      detail: entry.values[kind].flatMap { LabMath.format($0, decimals: 1) }.map { "\($0) cm" } ?? "-",
                                      opensSomething: false)
                    }
                    DatePicker("Date", selection: $entry.date, in: ...Date(), displayedComponents: .date)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .padding(.horizontal, theme.metrics.browseRowPadding)
                        .frame(minHeight: theme.metrics.browseRowMinHeight)
                        .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                            .fill(theme.colors.surface.color))
                    LabFootnote(status ?? "Waist also saved to Health.")
                    LabPrimaryButton(title: "Save", isEnabled: measured > 0) {
                        Task { await save() }
                    }
                    if !isNew {
                        LabSecondaryButton(title: "Delete this entry") {
                            store.delete(entry)
                            onDone()
                        }
                    }
                }
            }
            .padding(.horizontal, theme.metrics.pagePadding)
            .padding(.bottom, theme.metrics.pagePadding)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle("Review")
    }

    private func save() async {
        store.save(entry)
        if let waist = entry.values[.waist] {
            let outcome = await LabHealthWriter.save(.waist(centimetres: waist), at: entry.date)
            if case .failed(let message) = outcome {
                status = "Saved in Soma. Health refused the waist: \(message)"
                return
            }
        }
        onDone()
    }
}

#Preview("Body measurements") {
    NavigationStack {
        BodyMeasurementsPage()
    }
}
