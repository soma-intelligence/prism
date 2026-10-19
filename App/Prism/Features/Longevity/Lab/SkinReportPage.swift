//
//  SkinReportPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The face scan's skin report: tone uniformity, redness, melanin and shine,
/// each against your own earlier scans, and the history of scans.
///
/// Soma does not run the face scan yet, so every index is a dash, the
/// history is empty, and each index still opens the page that says what it
/// measures and how a scan is lit.
struct SkinReportPage: View {
    @State private var index: SkinIndex?
    @State private var isScanning = false

    var body: some View {
        TabPartScaffold(
            aspect: nil,
            eyebrow: "Face scan",
            title: "No scan yet.",
            reason: "A scan reads four indices from your face, lit the same way each time by the screen. From the fourth scan on, each index reads against your own.",
            stats: [
                SomaStat("Tone", value: nil, unit: "%"),
                SomaStat("Redness", value: nil),
                SomaStat("Shine", value: nil, unit: "%"),
            ]
        ) {
            LabBandCard(title: "Four indices", eyebrow: "Against your own scans", items: SkinIndex.allCases.map { index in
                LabBandItem(id: index.id, title: index.title, detail: index.line, value: nil)
            })
            LabRowGroup(rows: SkinIndex.allCases.map { index in
                LabRow("About \(index.title.lowercased())", action: { self.index = index })
            } + [LabRow("Perceived age", detail: "eight scans first")])
            SomaActionCard(
                eyebrow: "Next scan",
                title: "A morning, before any cream",
                detail: "So scans stay comparable. One a week is plenty.",
                actionTitle: "New scan",
                action: { isScanning = true }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
            LabFootnote("Wellness only, never a diagnosis.")
        }
        .navigationTitle("Skin Report")
        .sheet(item: $index) { SkinIndexSheet(index: $0) }
        .sheet(isPresented: $isScanning) {
            NotWiredPage(
                eyebrow: "Face scan",
                title: "New scan",
                message: "The face scan isn’t in this build yet. When it is, the screen lights your face in five colours and the four indices land on this page."
            )
        }
    }
}

/// The four indices a scan reads.
enum SkinIndex: String, CaseIterable, Identifiable {
    case tone, redness, melanin, shine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tone: "Tone uniformity"
        case .redness: "Redness"
        case .melanin: "Melanin"
        case .shine: "Shine and sebum"
        }
    }

    var line: String {
        switch self {
        case .tone: "percent, higher is more even"
        case .redness: "relative to your scans"
        case .melanin: "relative, steady over weeks"
        case .shine: "percent of the face"
        }
    }

    var means: String {
        switch self {
        case .tone: "How evenly colour spreads across your face. A single flat tone would read 100%; sun spots, marks from old blemishes and uneven tanning pull it down."
        case .redness: "How much red the blood under the skin shows. Heat, a hard session, alcohol and irritation all raise it for hours."
        case .melanin: "The pigment the sun builds. It follows the seasons and moves over weeks, not days."
        case .shine: "The share of the face that reflects light as a highlight. Oil, sweat and the time since you washed all move it."
        }
    }

    var moves: String {
        switch self {
        case .tone: "Sun, old marks and uneven tanning. It changes over weeks, so one scan a week is plenty."
        case .redness: "Heat, alcohol and irritation. Scan at the same time of day to compare."
        case .melanin: "Time in the sun and the season. Sunscreen slows it."
        case .shine: "Cleansing, humidity and the hour. Scan before any cream."
        }
    }
}

/// One index explained, on the explainer: what it reads, what moves it,
/// how a scan is lit, and your scans of it.
struct SkinIndexSheet: View {
    let index: SkinIndex

    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let look: (symbol: String, hue: SomaHealthHue) = switch index {
        case .tone: ("circle.lefthalf.filled", .body)
        case .redness: ("drop.fill", .heart)
        case .melanin: ("sun.max.fill", .mobility)
        case .shine: ("sparkle", .hearing)
        }

        SomaExplainer(eyebrow: "Skin", title: index.title, summary: index.line.scoreCapitalized + ".",
                      aspect: .body, onClose: { dismiss() }) {
            PulseMiniOrb(aspect: .body, diameter: theme.metrics.explainerHeroDiameter * 0.8)
                .frame(height: theme.metrics.explainerHeroDiameter)
        } content: {
            SomaExplainerSection("How it works") {
                SomaExplainerRow(symbol: look.symbol, hue: look.hue, term: "What it reads", line: index.means)
                SomaExplainerRow(symbol: "arrow.up.arrow.down", hue: look.hue, term: "What moves it", line: index.moves)
                SomaExplainerRow(symbol: "iphone", hue: .other, term: "How a scan is lit",
                                 line: "The screen flashes five colours, and the room’s own light is taken out.")
            }
            SomaExplainerSection("Your scans") {
                SomaExplainerRow(symbol: "camera.fill", hue: .other, term: "No scan yet", line: "Your scans of it land here.")
            }
            SomaExplainerNote("Wellness only, never a diagnosis.")
        }
    }
}

#Preview("Skin report") {
    NavigationStack {
        SkinReportPage()
    }
}
