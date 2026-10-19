//
//  PulseRoute.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Where a tile on a reading page opens: the readings behind it.
///
/// Registered on the Pulse and Longevity stacks both, so a card on either tab
/// zooms into the same page. A category is named by title so the route stays a
/// plain value.
enum PulseRoute: Hashable {
    case category(String)

    /// The Health category an aspect's card opens.
    static func aspect(_ aspect: SomaAspect) -> PulseRoute {
        switch aspect {
        case .sleep: .category("Sleep")
        case .mind: .category("Mental Wellbeing")
        case .heart: .category("Heart")
        case .activity: .category("Activity")
        case .gut: .category("Nutrition")
        case .body: .category("Body Measurements")
        }
    }

    @ViewBuilder
    var page: some View {
        switch self {
        case .category(let title):
            if let category = BodyCatalog.categories.first(where: { $0.title == title }) {
                BodyCategoryPage(category: category)
            } else {
                NotWiredPage(eyebrow: "Readings", title: LocalizedStringResource(stringLiteral: title), message: "This group of readings is not in the catalog.")
            }
        }
    }
}

/// A card that opens a page: the whole tile is the target, it dips a little
/// under the finger, and the page zooms out of it.
struct TileLink<Value: Hashable, Label: View>: View {
    let value: Value
    let label: Label

    init(value: Value, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        NavigationLink(value: value) {
            label
                .contentShape(.rect)
                .zoomSource(value)
        }
        .buttonStyle(TilePressStyle())
    }
}

/// A tile under the finger: a short dip in scale, no dim, so the card stays
/// readable while it is held and the zoom starts from where it sat.
struct TilePressStyle: ButtonStyle {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: theme.motion.pressDuration), value: configuration.isPressed)
    }
}
