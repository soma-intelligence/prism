//
//  LanguageUnitsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Words and measures: the language Soma speaks, and how it writes a number.
///
/// The Language page, with the units.
/// Only the languages the app actually ships are offered; a language row that
/// changed nothing would be a lie. Choosing one sets the app's own language
/// preference, which the system applies when Soma next starts.
struct LanguageUnitsPage: View {
    @Environment(\.somaTheme) private var theme

    @State private var settings = GlobalSettings.shared
    @State private var chosen: String? = LanguageChoice.chosen

    var body: some View {
        ListScaffold(eyebrow: "Language and units", title: "Words and measures") {
            languageSection
            unitsSection
        }
    }

    private var languageSection: some View {
        SettingsSection("Language") {
            SomaBrowseGroup(LanguageChoice.offered, hasGlyphs: false) { language in
                languageRow(language)
            }
            SettingsFootnote(languageNote)
        }
    }

    private func languageRow(_ language: LanguageChoice) -> some View {
        SomaBrowseRow(title: language.name, opensSomething: false, action: { choose(language) }) {
            if language.code == current {
                Image(systemName: "checkmark")
                    .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(theme.colors.accent.color)
            }
        }
    }

    private var unitsSection: some View {
        SettingsSection("Units") {
            SomaBrowseGroup([SettingsItem].items("measures", "temperature", "glucose", "energy", "clock", "week"), hasGlyphs: false) { item in
                unitRow(item.id)
            }
        }
    }

    @ViewBuilder
    private func unitRow(_ id: String) -> some View {
        @Bindable var settings = settings
        switch id {
        case "measures":
            SettingsLine("Measures", detail: settings.units.measures.detail) {
                SettingsMenuValue(title: "Measures", options: MeasureSystem.allCases, label: \.title, selection: $settings.units.measures)
            }
        case "temperature":
            SettingsLine("Temperature") {
                SettingsMenuValue(title: "Temperature", options: TemperatureUnit.allCases, label: \.title, selection: $settings.units.temperature)
            }
        case "glucose":
            SettingsLine("Blood sugar") {
                SettingsMenuValue(title: "Blood sugar", options: GlucoseUnit.allCases, label: \.title, selection: $settings.units.glucose)
            }
        case "energy":
            SettingsLine("Energy") {
                SettingsMenuValue(title: "Energy", options: EnergyUnit.allCases, label: \.title, selection: $settings.units.energy)
            }
        case "clock":
            SettingsLine("Time") {
                SettingsMenuValue(title: "Time", options: ClockStyle.allCases, label: \.title, selection: $settings.units.clock)
            }
        default:
            SettingsLine("Week starts on") {
                SettingsMenuValue(title: "Week starts on", options: WeekStart.allCases, label: \.title, selection: $settings.units.weekStart)
            }
        }
    }

    private var current: String {
        chosen ?? LanguageChoice.running
    }

    private var languageNote: LocalizedStringKey {
        if let chosen, chosen != LanguageChoice.running {
            return "Soma speaks this language from its next start."
        }
        if LanguageChoice.offered.count == 1 {
            return "Soma is written in English today. Other languages appear here as they are translated."
        }
        return "The new language applies when Soma next starts."
    }

    private func choose(_ language: LanguageChoice) {
        chosen = language.code
        LanguageChoice.choose(language.code)
    }
}

/// A language the app ships, by its own name.
struct LanguageChoice: Identifiable, Hashable {
    let code: String
    var id: String { code }

    /// The language in its own words: Français, Deutsch.
    var name: String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    static var offered: [LanguageChoice] {
        let codes = Bundle.main.localizations.filter { $0 != "Base" }
        let unique = Array(Set(codes.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 })).sorted()
        return (unique.isEmpty ? ["en"] : unique).map(LanguageChoice.init(code:))
    }

    /// The language the app is running in now.
    static var running: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: preferred).language.languageCode?.identifier ?? preferred
    }

    /// The language chosen here, if one was.
    static var chosen: String? {
        (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
            .map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
    }

    /// The app's own language preference, which the system reads at launch.
    static func choose(_ code: String) {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }
}

#Preview("Language and units") {
    NavigationStack { LanguageUnitsPage() }
}
