//
//  OnboardingProfileSteps.swift
//  Prism
//

import SwiftUI
import SomaUI

// MARK: - About you

/// The whole profile on one screen, in one card: the name (already filled
/// when Sign in with Apple shared it), the date of birth on a picker, the sex
/// as three choices, and the body clock as an optional row that opens the
/// five questions. Continue wakes once the birthday and the sex are given;
/// the name and the body clock can wait.
struct OnboardingAboutView: View {
    @Bindable var model: OnboardingModel

    @Environment(\.somaTheme) private var theme
    @State private var isAskingClock = false

    /// Thirteen and over, and no one older than the calendar allows.
    private var range: ClosedRange<Date> {
        let calendar = Calendar.current
        let latest = calendar.date(byAdding: .year, value: -13, to: .now) ?? .now
        let earliest = calendar.date(byAdding: .year, value: -110, to: .now) ?? .distantPast
        return earliest...latest
    }

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        OnboardingPage(title: String(localized: "A little about you.")) {
            SomaCard {
                VStack(spacing: 0) {
                    field(String(localized: "Name")) {
                        TextField("First name", text: $model.name)
                            .textFieldStyle(.plain)
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .multilineTextAlignment(.trailing)
                            .somaFont(theme.typography.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                    separator
                    field(String(localized: "Born")) {
                        DatePicker("Date of birth", selection: birthday, in: range, displayedComponents: .date)
                            .labelsHidden()
#if os(macOS)
                            // The Mac's compact picker is a bezelled field
                            // with a stepper; the bare field reads as a row value.
                            .datePickerStyle(.field)
                            .fixedSize()
#else
                            .datePickerStyle(.compact)
#endif
                            .opacity(model.hasBirthday ? 1 : 0.45)
                    }
                    separator
                    // The three chips sit beside the label while they fit; on
                    // a narrow phone or with larger text they drop under it
                    // and share the width evenly, never wrapping a word.
                    ViewThatFits(in: .horizontal) {
                        field(String(localized: "Sex")) { sexChips(fills: false) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sex")
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(colors.inkPrimary.color)
                            sexChips(fills: true)
                        }
                        .padding(.vertical, 10)
                    }
                    separator
                    Button { isAskingClock = true } label: {
                        HStack {
                            Text("Body clock")
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(colors.inkPrimary.color)
                            Spacer()
                            Text(model.profile.chronotypeCategory?.title ?? String(localized: "Five questions"))
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(colors.inkSecondary.color)
                            Image(systemName: "chevron.right")
                                .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .frame(minHeight: metrics.minimumTapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPressDim)
                }
            }
            .onboardingArrival(1)
        }
        .sheet(isPresented: $isAskingClock) {
            OnboardingChronotypeSheet(initial: model.profile.chronotype) { answers in
                model.update {
                    $0.chronotype = answers
                    $0.chronotypeAnsweredAt = Date()
                }
            }
        }
    }

    /// The birthday as the picker sees it: moving it is what gives it.
    private var birthday: Binding<Date> {
        Binding(
            get: { model.birthday },
            set: { model.birthday = $0; model.hasBirthday = true }
        )
    }

    private func sexChips(fills: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(BiologicalSex.allCases) { sex in
                OnboardingChip(title: sex.shortTitle, isOn: model.sex == sex, fills: fills) {
                    model.sex = sex
                }
                .accessibilityLabel(Text(sex.title))
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
            .frame(height: 0.5)
    }

    private func field<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: theme.metrics.cardPadding) {
            Text(title)
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Spacer(minLength: 0)
            value()
        }
        .frame(minHeight: theme.metrics.minimumTapTarget + 4)
    }
}

extension BiologicalSex {
    /// The word a chip has room for. The full wording stays the chip's
    /// spoken label.
    var shortTitle: String {
        switch self {
        case .male: String(localized: "Male")
        case .female: String(localized: "Female")
        case .other: String(localized: "Other")
        }
    }
}

// MARK: - Chronotype sheet

/// The five rMEQ questions as chips. Save wakes once all five are answered,
/// and hands the answers back; Cancel leaves the step as it was.
struct OnboardingChronotypeSheet: View {
    let initial: RMEQAnswers?
    let save: (RMEQAnswers) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [Int: Int] = [:]

    private var answers: RMEQAnswers? {
        let items = RMEQCatalog.items.indices.compactMap { picked[$0] }
        let answers = RMEQAnswers(items: items)
        return answers.isComplete ? answers : nil
    }

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                    Text("Your chronotype")
                        .somaFont(type.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    OnboardingLead(
                        lead: String(localized: "Five quick questions place your body clock."),
                        rest: String(localized: "Soma can guide you from day one instead of waiting two weeks for sleep data.")
                    )

                    ForEach(Array(RMEQCatalog.items.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.prompt)
                                .somaFont(type.callout)
                                .foregroundStyle(colors.inkPrimary.color)
                            OnboardingChipFlow {
                                ForEach(item.options, id: \.self) { option in
                                    OnboardingChip(title: option.text, isOn: picked[index] == option.points) {
                                        picked[index] = option.points
                                    }
                                }
                            }
                        }
                    }

                    if let answers {
                        Text("You read as \(answers.category.title.lowercased()).")
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                }
                .padding(metrics.pagePadding)
            }
            .background(colors.canvas.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let answers else { return }
                        save(answers)
                        dismiss()
                    }
                    .disabled(answers == nil)
                }
            }
        }
        .onAppear {
            guard let initial, initial.isComplete else { return }
            for (index, points) in initial.items.enumerated() { picked[index] = points }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 620)
#endif
    }
}
