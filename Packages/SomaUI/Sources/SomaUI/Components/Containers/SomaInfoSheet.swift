//
//  SomaInfoSheet.swift
//  SomaUI
//

import SwiftUI

/// One short part of an info sheet: a heading set small and wide, and a few
/// plain lines under it.
public struct SomaInfoSection: Identifiable, Equatable, Sendable {
    public var id: String { heading }
    public var heading: String
    public var body: String

    public init(_ heading: String, body: String) {
        self.heading = heading
        self.body = body
    }
}

/// What a page keeps behind its small info control: the long explanation a
/// person reads once, so the page itself can stay short. A title, then a few
/// sections, then whatever the page adds at the foot (a link to every
/// reading, say). Presented as a sheet by the page that owns it.
public struct SomaInfoSheet<Footer: View>: View {
    private let title: String
    private let sections: [SomaInfoSection]
    private let footer: Footer

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(title: String, sections: [SomaInfoSection], @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.sections = sections
        self.footer = footer()
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                Text(title)
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: metrics.cardSpacing / 2) {
                        Text(section.heading)
                            .somaFont(theme.typography.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.inkSecondary.color)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .somaFont(theme.typography.body)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                footer
            }
            .padding(metrics.pagePadding)
            .padding(.top, metrics.cardSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(colors.canvas.color.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(width: metrics.minimumTapTarget, height: metrics.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
            .padding(.trailing, metrics.pagePadding / 2)
            .padding(.top, metrics.cardSpacing / 2)
        }
    }
}

public extension SomaInfoSheet where Footer == EmptyView {
    init(title: String, sections: [SomaInfoSection]) {
        self.init(title: title, sections: sections) { EmptyView() }
    }
}

#Preview("Info sheet") {
    SomaInfoSheet(title: "Steps", sections: [
        SomaInfoSection("What it is", body: "Every step your phone and watch count through the day."),
        SomaInfoSection("Your usual", body: "The range your days sat in over the last two weeks. It moves with you."),
        SomaInfoSection("Unit", body: "Steps"),
    ])
}
