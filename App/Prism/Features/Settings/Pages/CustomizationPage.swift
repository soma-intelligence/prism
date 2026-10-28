//
//  CustomizationPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// How Soma reads you: what it knows about you, what your usual is, and how it
/// answers.
///
/// Customization: goals, zones, data window, skin type and answers, as one
/// settings page. The choices are kept on the phone in
/// ``GlobalSettings``. The last meal cutoff drives the evening nudge on the
/// Notifications page; the others are read by the pages that use them.
struct CustomizationPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health

    @State private var settings = GlobalSettings.shared
    @State private var profiles = SomaProfileStore.shared

    var body: some View {
        @Bindable var settings = settings

        ListScaffold(eyebrow: "Customization", title: "How Soma reads you") {

            SettingsSection("About you") {
                SomaBrowseGroup([SettingsItem].items("focus", "clock", "skin"), hasGlyphs: false) { item in
                    if item.id == "focus" {
                        SettingsLine("Focus") { focusMenu }
                    } else if item.id == "clock" {
                        SettingsLine("Body clock", detail: profiles.profile.chronotypeCategory == nil
                                     ? String(localized: "From the questionnaire in onboarding") : nil) {
                            SomaNumber(profiles.profile.chronotypeCategory?.title, theme.typography.rowValue)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                    } else {
                        SettingsLine("Skin type", detail: "For the UV and sun lines") {
                            SettingsMenuValue(
                                title: "Skin type",
                                options: [SkinType?.none] + SkinType.allCases.map(Optional.some),
                                label: { $0?.title ?? String(localized: "Not set") },
                                selection: $settings.customization.skinType
                            )
                        }
                    }
                }
            }

            SettingsSection("Your usual") {
                SomaBrowseGroup([SettingsItem].items("window", "zones", "move", "zone2", "water", "meal"), hasGlyphs: false) { item in
                    usualRow(item.id)
                }
            }

            SettingsSection("Soma") {
                SomaBrowseGroup([SettingsItem].items("answers"), hasGlyphs: false) { _ in
                    SettingsLine("Answers", detail: settings.customization.answers == .short
                                 ? String(localized: "Plain words, your numbers first")
                                 : String(localized: "The reasoning behind each number")) {
                        SettingsMenuValue(title: "Answers", options: AnswerLength.allCases, label: \.title,
                                          selection: $settings.customization.answers)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func usualRow(_ id: String) -> some View {
        @Bindable var settings = settings
        switch id {
        case "window":
            SettingsLine("Usual ranges", detail: "The band every chart draws") {
                SettingsMenuValue(title: "Usual ranges", options: CustomizationPreferences.usualWindows,
                                  label: { String(localized: "\($0) days") },
                                  selection: $settings.customization.usualWindowDays)
            }
        case "zones":
            SettingsLine("Heart rate zones", detail: zonesDetail) {
                SomaNumber(maxHeartRate.map { String(localized: "Max \($0)") }, theme.typography.rowValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        case "move":
            SettingsLine("Move goal") {
                SettingsMenuValue(title: "Move goal", options: CustomizationPreferences.moveGoals,
                                  label: { "\($0) kcal" }, selection: $settings.customization.moveGoalKilocalories)
            }
        case "zone2":
            SettingsLine("Zone 2 a week") {
                SettingsMenuValue(title: "Zone 2 a week", options: CustomizationPreferences.zoneTwoTargets,
                                  label: { "\($0) min" }, selection: $settings.customization.zoneTwoMinutesPerWeek)
            }
        case "water":
            SettingsLine("Water") {
                SettingsMenuValue(title: "Water", options: CustomizationPreferences.waterTargets,
                                  label: { (Double($0) / 1000).formatted(.number.precision(.fractionLength(1))) + " L" },
                                  selection: $settings.customization.waterMillilitres)
            }
        default:
            SettingsLine("Last meal by") {
                SettingsMenuValue(title: "Last meal by", options: CustomizationPreferences.mealCutoffs,
                                  label: \.text, selection: $settings.customization.lastMealBy)
            }
        }
    }

    /// Several areas can be the focus; a menu of switches says so. The same
    /// picks as onboarding's Focus step, kept in the profile.
    private var focusMenu: some View {
        Menu {
            ForEach(FocusArea.allCases) { area in
                Toggle(area.title, isOn: Binding(
                    get: { profiles.profile.focus.contains(area) },
                    set: { isOn in
                        profiles.update { profile in
                            profile.focus.removeAll { $0 == area }
                            if isOn { profile.focus.append(area) }
                        }
                    }
                ))
            }
        } label: {
            HStack(spacing: theme.metrics.scoreLabelSpacing) {
                Text(focusText)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            .frame(minHeight: theme.metrics.minimumTapTarget)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Focus")
        .accessibilityValue(Text(focusText))
    }

    private var focusText: String {
        let focus = profiles.profile.focus
        guard let first = focus.first else { return String(localized: "None") }
        return focus.count == 1 ? first.title : String(localized: "\(first.title) and \(focus.count - 1) more")
    }

    /// Tanaka's estimate, the one the scoring falls back on: 208 minus
    /// 0.7 times age. Nil until Apple Health or the profile holds a birthday.
    private var maxHeartRate: Int? {
        (health.today?.age ?? profiles.profile.age()).map { Int((208 - 0.7 * Double($0)).rounded()) }
    }

    private var zonesDetail: String {
        maxHeartRate == nil
            ? String(localized: "From your age, once Soma knows your birthday")
            : String(localized: "From your age")
    }
}

#Preview("Customization") {
    NavigationStack { CustomizationPage() }
        .environment(HealthDashboard())
}
