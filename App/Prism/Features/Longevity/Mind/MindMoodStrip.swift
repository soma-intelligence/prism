//
//  MindMoodStrip.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The last fourteen days of mood as a row of orbs, each in the colour of
/// how the day felt; a day with nothing logged is an empty ring. Tapping an
/// orb sets that day under the row: its mood, the words named and what had
/// a hand in it.
struct MindMoodStrip: View {
    let days: [MindMoodDay]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Date?

    var body: some View {
        let metrics = theme.metrics
        let chosen = selected

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(spacing: 0) {
                ForEach(days) { day in
                    orb(day, isSelected: day.id == chosen?.id)
                        .frame(maxWidth: .infinity)
                }
            }
            detail(chosen)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// The day tapped, else the latest day with a mood.
    private var selected: MindMoodDay? {
        if let selection, let day = days.first(where: { $0.id == selection }) { return day }
        return days.last { $0.valence != nil } ?? days.last
    }

    /// One day as a bar from the midline: up for a pleasant day, down for an
    /// unpleasant one, as long as the mood was strong, in its colour. A day
    /// with nothing logged is a dot on the line, so a fortnight reads as a
    /// tide rather than a row of empty circles.
    private func orb(_ day: MindMoodDay, isSelected: Bool) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let height = metrics.minimumTapTarget * 1.3
        let half = height / 2 - 2
        let width = metrics.chartRingDiameter * 0.8
        let letters = Calendar.current.veryShortStandaloneWeekdaySymbols
        let letter = letters[(Calendar.current.component(.weekday, from: day.day) - 1) % letters.count]

        return Button {
            selection = day.id
        } label: {
            VStack(spacing: metrics.chartLabelGap) {
                ZStack {
                    Rectangle()
                        .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: 0.5)
                    if let valence = day.valence {
                        let length = max(width, half * CGFloat(min(abs(valence), 1)))
                        Capsule()
                            .fill(MindMoodPalette.color(valence).opacity(isSelected || selection == nil ? 1 : 0.55))
                            .frame(width: width, height: length)
                            .offset(y: valence >= 0 ? -length / 2 : length / 2)
                    } else {
                        Circle()
                            .fill(colors.inkPrimary.color.opacity(0.2))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: height)
                .animation(reduceMotion ? nil : theme.motion.selection, value: isSelected)

                Text(verbatim: letter)
                    .somaFont(theme.typography.captionValue)
                    .foregroundStyle(day.isToday || isSelected ? colors.inkPrimary.color : colors.inkSecondary.color)
            }
            .frame(minHeight: metrics.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.day, format: .dateTime.weekday(.wide).day().month()))
        .accessibilityValue(day.valence.map { String(localized: MindQuickMood.mood(valence: $0).title) } ?? String(localized: "Nothing logged"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func detail(_ day: MindMoodDay?) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        if let day {
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing + 4) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.trendMarkSpacing * 2) {
                    Text(day.day, format: .dateTime.weekday(.abbreviated).day())
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                    if let valence = day.valence {
                        Text(MindQuickMood.mood(valence: valence).title)
                            .somaFont(type.callout)
                            .foregroundStyle(MindMoodPalette.color(valence))
                    } else {
                        SomaMissingValue(type.callout)
                    }
                }
                if !day.words.isEmpty || !day.themes.isEmpty {
                    MindChipFlow().callAsFunction {
                        ForEach(day.words, id: \.self) { word in
                            MindWordChip(text: word, tint: day.valence.map(MindMoodPalette.color))
                        }
                        ForEach(day.themes, id: \.self) { item in
                            MindWordChip(text: item, tint: nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : theme.motion.selection, value: day.id)
        }
    }
}

/// A word under the mood strip: a feeling in its mood's colour, or a theme
/// in grey.
struct MindWordChip: View {
    let text: String
    let tint: Color?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(tint ?? colors.inkSecondary.color)
            .padding(.horizontal, metrics.spaceM)
            .padding(.vertical, metrics.chartLabelGap)
            .background((tint ?? colors.inkSecondary.color).opacity(metrics.chartBandOpacity), in: .capsule)
    }
}

#if DEBUG
#Preview("Mood strip") {
    SomaCard {
        MindMoodStrip(days: MindLensModel.preview.moods)
    }
    .padding()
    .somaTheme(.standard)
}
#endif
