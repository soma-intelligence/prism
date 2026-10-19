//
//  SomaTypography.swift
//  SomaUI
//

import SwiftUI

/// The faces the system is allowed to draw with.
///
/// Deliberately an enum and not a `Font.Design`: a face cannot be introduced by
/// writing one more token, only by editing this type. There is one, SF Pro, for
/// words and numbers alike, the way the website sets Geist for both.
public enum SomaFontFamily: Sendable, Equatable, CaseIterable {
    /// SF Pro. Everything: words, titles and values.
    case pro

    var design: Font.Design {
        switch self {
        case .pro: .default
        }
    }
}

/// How a role spaces its digits.
///
/// A value that changes in place has to hold its columns, or the number
/// shivers sideways each time a digit turns over. Running text has to keep the
/// face's natural spacing. The role decides, not the family.
public enum SomaDigits: Sendable, Equatable {
    /// The face's own spacing. Words, and numbers read inside a sentence.
    case proportional
    /// Every digit the same width. Values.
    case tabular
}

/// One typographic role: a family, a size, a weight, the tracking that goes
/// with them, and how its digits are spaced.
public struct SomaFontSpec: Sendable, Equatable {
    public var family: SomaFontFamily
    public var size: CGFloat
    public var weight: Font.Weight
    public var tracking: CGFloat
    public var digits: SomaDigits

    public init(
        family: SomaFontFamily = .pro,
        size: CGFloat,
        weight: Font.Weight = .regular,
        tracking: CGFloat = 0,
        digits: SomaDigits = .proportional
    ) {
        self.family = family
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.digits = digits
    }

    /// The font alone, without the tracking. A view applies the whole role
    /// with `somaFont(_:)`.
    public var font: Font {
        let base = Font.system(size: size, weight: weight, design: family.design)
        return digits == .tabular ? base.monospacedDigit() : base
    }
}

/// The type scale. Fixed in points on purpose: the app reads at a constant
/// density, one-handed, and the components handle accessibility sizes by
/// changing layout rather than by letting the scale run away.
///
/// Headlines and values are set the way the website sets Geist: regular
/// weight, tight tracking. Labels above a section are set wide, like the site's
/// section labels.
public struct SomaTypography: Sendable, Equatable {
    /// Hero values and screen titles.
    public var display: SomaFontSpec
    /// Section and card titles.
    public var title: SomaFontSpec
    /// Running text.
    public var body: SomaFontSpec
    /// Any number the user reads as a value. Always tabular.
    public var metric: SomaFontSpec
    /// Annotations under a value.
    public var caption: SomaFontSpec
    /// A number read inside a row rather than as a hero value. Always tabular.
    public var rowValue: SomaFontSpec
    /// What a person types or picks, on a screen that asks one thing.
    ///
    /// Bigger than body and smaller than display, because the answer is the
    /// second most important thing on such a screen and the question is the
    /// first. A form field set in body text reads as a detail on a page; set in
    /// this, it reads as the thing being asked for.
    public var field: SomaFontSpec
    /// The label under a tab glyph.
    public var tabLabel: SomaFontSpec
    /// The uppercase kicker above a card or a section.
    public var eyebrow: SomaFontSpec
    /// The label of a segment in a segmented control.
    ///
    /// The selected segment wears this weight and the others drop to regular,
    /// so the pill behind it is not the only thing saying which one is on.
    public var segment: SomaFontSpec
    /// The title a floating header folds into once its page has scrolled.
    ///
    /// The size the system gives an inline navigation title, so a pinned
    /// header and a system bar read as the same kind of thing.
    public var headerTitle: SomaFontSpec
    /// The move written on an orb: two words, the one thing a page asks.
    public var orbLabel: SomaFontSpec
    /// The sentence a page leads with, written from the data.
    public var headline: SomaFontSpec
    /// A line that leads a row or states the reason under a headline: one
    /// step under running text.
    public var callout: SomaFontSpec
    /// The title of a card that carries a list: Tonight, Today.
    public var cardTitle: SomaFontSpec
    /// A value inside a card that sits among others. Always tabular.
    public var metricCompact: SomaFontSpec
    /// A number read at caption size: a time in a timeline, a label on a
    /// chart. Always tabular, so a column of times holds its edge.
    public var captionValue: SomaFontSpec

    public init(
        display: SomaFontSpec,
        title: SomaFontSpec,
        body: SomaFontSpec,
        metric: SomaFontSpec,
        caption: SomaFontSpec,
        rowValue: SomaFontSpec,
        field: SomaFontSpec,
        tabLabel: SomaFontSpec,
        eyebrow: SomaFontSpec,
        segment: SomaFontSpec,
        headerTitle: SomaFontSpec,
        orbLabel: SomaFontSpec,
        headline: SomaFontSpec,
        callout: SomaFontSpec,
        cardTitle: SomaFontSpec,
        metricCompact: SomaFontSpec,
        captionValue: SomaFontSpec
    ) {
        self.display = display
        self.title = title
        self.body = body
        self.metric = metric
        self.caption = caption
        self.rowValue = rowValue
        self.field = field
        self.tabLabel = tabLabel
        self.eyebrow = eyebrow
        self.segment = segment
        self.headerTitle = headerTitle
        self.orbLabel = orbLabel
        self.headline = headline
        self.callout = callout
        self.cardTitle = cardTitle
        self.metricCompact = metricCompact
        self.captionValue = captionValue
    }

    /// Every role in this scale, for anything that has to walk them.
    public var allRoles: [SomaFontSpec] {
        [display, title, body, metric, caption, rowValue, field, tabLabel, eyebrow, segment, headerTitle,
         orbLabel, headline, callout, cardTitle, metricCompact, captionValue]
    }

    /// Read at arm's length on a handheld screen.
    public static let touch = SomaTypography(
        display: SomaFontSpec(size: 34, tracking: -0.5),
        title: SomaFontSpec(size: 22, tracking: -0.2),
        body: SomaFontSpec(size: 16),
        metric: SomaFontSpec(size: 36, tracking: -0.8, digits: .tabular),
        caption: SomaFontSpec(size: 13),
        rowValue: SomaFontSpec(size: 15, digits: .tabular),
        field: SomaFontSpec(size: 24, tracking: -0.3),
        tabLabel: SomaFontSpec(size: 11, weight: .medium),
        eyebrow: SomaFontSpec(size: 11, weight: .medium, tracking: 3.0),
        segment: SomaFontSpec(size: 14, weight: .medium),
        headerTitle: SomaFontSpec(size: 17, weight: .semibold),
        orbLabel: SomaFontSpec(size: 26, tracking: -0.6),
        headline: SomaFontSpec(size: 24, tracking: -0.4),
        callout: SomaFontSpec(size: 15),
        cardTitle: SomaFontSpec(size: 17, weight: .semibold),
        metricCompact: SomaFontSpec(size: 28, tracking: -0.6, digits: .tabular),
        captionValue: SomaFontSpec(size: 13, digits: .tabular)
    )

    /// Read at desk distance. The desktop's body text is 13pt, and a scale built
    /// for a phone held in one hand reads as shouting in a window.
    public static let pointer = SomaTypography(
        display: SomaFontSpec(size: 26, tracking: -0.4),
        title: SomaFontSpec(size: 17, tracking: -0.1),
        body: SomaFontSpec(size: 13),
        metric: SomaFontSpec(size: 26, tracking: -0.5, digits: .tabular),
        caption: SomaFontSpec(size: 11),
        rowValue: SomaFontSpec(size: 12, digits: .tabular),
        field: SomaFontSpec(size: 17, tracking: -0.1),
        tabLabel: SomaFontSpec(size: 10, weight: .medium),
        eyebrow: SomaFontSpec(size: 10, weight: .medium, tracking: 2.4),
        segment: SomaFontSpec(size: 12, weight: .medium),
        headerTitle: SomaFontSpec(size: 13, weight: .semibold),
        orbLabel: SomaFontSpec(size: 20, tracking: -0.4),
        headline: SomaFontSpec(size: 18, tracking: -0.3),
        callout: SomaFontSpec(size: 12),
        cardTitle: SomaFontSpec(size: 13, weight: .semibold),
        metricCompact: SomaFontSpec(size: 21, tracking: -0.4, digits: .tabular),
        captionValue: SomaFontSpec(size: 11, digits: .tabular)
    )

#if os(macOS)
    public static let standard = pointer
#else
    public static let standard = touch
#endif
}
