//
//  HomeMedicalCardPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// What someone helping in an emergency needs, pushed from Next move and from
/// All categories: date of birth, sex and blood type from Apple Health, height
/// and weight from the latest readings, and what the person wrote themselves:
/// allergies, medications, conditions, organ donation and who to call.
///
/// Allergies and conditions read from the medical record once the card's
/// free text has moved there (`MedicalRecord.migrate(from:)`); the card then
/// links to the record to change them.
///
/// Everything written here stays on this phone. The lock screen's Medical ID
/// is Apple's and is edited in the Health app; this page says so rather than
/// pretending to switch it.
struct HomeMedicalCardPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var clinical = HomeClinical()
    @State private var height: Double?
    @State private var weight: (value: Double, date: Date)?
    @State private var isEditing = false

    private var log: HomeLog { .shared }

    var body: some View {
        let card = log.medical
        let record = MedicalRecordStore.shared.record

        HomePage("Medical card") {
            VStack(alignment: .leading, spacing: 8) {
                HomeEyebrow("Medical ID")
                Text(card.name.isEmpty ? "Your name" : card.name)
                    .somaFont(theme.typography.title)
                    .foregroundStyle(card.name.isEmpty ? theme.colors.inkSecondary.color : theme.colors.inkPrimary.color)
                HomeReason(summary)
            }
            .padding(.bottom, theme.metrics.cardSpacing)

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                    field("Blood type", clinical.bloodType, fallback: "Not set in Apple Health")
                    HomeHairline()
                    field("Sex", clinical.sex, fallback: "Not set in Apple Health")
                    HomeHairline()
                    field("Allergies", record.migratedFromCard ? record.allergies.map(\.substance).joined(separator: ", ") : card.allergies)
                    HomeHairline()
                    field("Medications", card.medications)
                    HomeHairline()
                    field("Conditions", record.migratedFromCard ? record.conditions.map(\.name).joined(separator: ", ") : card.conditions)
                    HomeHairline()
                    field("Organ donor", card.organDonor.map { $0 ? "Registered" : "Not registered" })
                }
            }

            HomeEyebrow("Emergency contact")
                .padding(.top, theme.metrics.cardSpacing)
            SomaCard {
                HStack(spacing: theme.metrics.cardSpacing) {
                    VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                        Text(card.contactName.isEmpty ? "No one yet" : card.contactName)
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        Text([card.contactRelation, card.contactPhone].filter { !$0.isEmpty }.joined(separator: " · ").homeNonEmpty
                             ?? "Add who to call in Edit.")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let url = phoneURL(card.contactPhone) {
                        Button("Call") { openURL(url) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Call \(card.contactName)")
                    }
                }
            }

            NavigationLink(value: GlobalRoute.medicalRecord) {
                SettingsTileRow(String(localized: "Medical record"), symbol: "heart.text.clipboard",
                                detail: String(localized: "Allergies, conditions, visits"))
            }
            .buttonStyle(.plain)
            .padding(.top, theme.metrics.cardSpacing)

            HomeEyebrow("On the lock screen")
                .padding(.top, theme.metrics.cardSpacing)
            HomeReason("Kept on this phone.")

            HomePrimaryButton("Edit medical card") { isEditing = true }
                .padding(.top, theme.metrics.cardSpacing)
        }
        .task { await read() }
        .sheet(isPresented: $isEditing) { HomeMedicalEditSheet(card: log.medical) }
    }

    private func field(_ label: String, _ value: String?, fallback: String = "Not written yet") -> some View {
        let text = value?.homeNonEmpty
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            Text(text ?? fallback)
                .somaFont(theme.typography.body)
                .foregroundStyle(text == nil ? theme.colors.inkSecondary.color : theme.colors.inkPrimary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts: [String] = []
        if let birth = clinical.birth, let date = Calendar.current.date(from: birth) {
            let age = Calendar.current.dateComponents([.year], from: date, to: Date()).year
            parts.append("Born \(date.formatted(.dateTime.day().month(.wide).year()))\(age.map { ", \($0)" } ?? "").")
        } else {
            parts.append("No date of birth in Apple Health.")
        }
        var body: [String] = []
        if let height { body.append("\(HomeFormat.whole(height * 100)) cm") }
        if let weight {
            body.append("\(HomeFormat.decimal(weight.value)) kg, weighed on \(weight.date.formatted(.dateTime.day().month(.wide)))")
        }
        if !body.isEmpty { parts.append(body.joined(separator: " and ") + ".") }
        return parts.joined(separator: " ")
    }

    private func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private func read() async {
        let wanted = HomeClinical.characteristics + [HomeMetric.height, HomeMetric.bodyMass]
        guard !health.readsEmptyStore, let source = await health.prepare(wanted) else { return }
        clinical = HomeClinical.read()
        height = await source.homeLatest(HomeMetric.height)?.value
        if let reading = await source.homeLatest(HomeMetric.bodyMass) {
            weight = (reading.value, reading.start)
        }
    }
}

/// The medical card's own fields, written by the person.
struct HomeMedicalEditSheet: View {
    @State var card: HomeMedicalCard

    private var log: HomeLog { .shared }

    var body: some View {
        HomeInputSheet(title: "Medical card", actionTitle: "Save", action: { log.medical = card }) {
            HomeTextField(title: "Name", text: $card.name)
            if !MedicalRecordStore.shared.record.migratedFromCard {
                HomeTextField(title: "Allergies", text: $card.allergies, prompt: "Penicillin, a rash")
            }
            HomeTextField(title: "Medications", text: $card.medications, prompt: "Vitamin D, 1,000 IU a day")
            if MedicalRecordStore.shared.record.migratedFromCard {
                HomeReason("Allergies and conditions live in your medical record, one by one.")
            } else {
                HomeTextField(title: "Conditions", text: $card.conditions, prompt: "None known")
            }
            HomeChipGroup(
                title: "Organ donor",
                options: ["Registered", "Not registered"],
                chosen: Binding(
                    get: { card.organDonor.map { $0 ? ["Registered"] : ["Not registered"] } ?? [] },
                    set: { card.organDonor = $0.isEmpty ? nil : $0.contains("Registered") }
                ),
                single: true
            )
            HomeTextField(title: "Emergency contact", text: $card.contactName, prompt: "Name")
            HomeTextField(title: "Relation", text: $card.contactRelation, prompt: "Partner")
            HomeTextField(title: "Phone", text: $card.contactPhone, prompt: "+1 650 555 0100")
#if os(iOS)
                .keyboardType(.phonePad)
#endif
        }
    }
}

/// A labelled line to type into.
struct HomeTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            TextField(title, text: $text, prompt: Text(prompt))
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .padding(.horizontal, theme.metrics.cardPadding)
                .frame(minHeight: theme.metrics.minimumTapTarget + 8)
                .background(RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.colors.surface.color))
        }
    }
}

extension String {
    /// The string, or nil when it holds nothing but spaces.
    var homeNonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
