//
//  AccountDetailsPage.swift
//  Prism
//

import SwiftUI
import SomaUI
#if !os(visionOS)
import PhotosUI
#endif

/// Your details: the name Soma calls you, how to reach you, and what your
/// zones and fitness age are read against.
///
/// Account details, over the local profile onboarding writes
/// (``SomaProfileStore``). Edits are held on the page and written by Save, as
/// the design puts it. There is no account on a server yet, so the sign in
/// section says what is connected on this phone and nothing more.
struct AccountDetailsPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = SomaProfileStore.shared
    @State private var draft = SomaProfile()
    @State private var loaded = false
#if !os(visionOS)
    @State private var pick: PhotosPickerItem?
#endif

    var body: some View {
        ListScaffold(eyebrow: "Account", title: "Your details") {
            identity

            SettingsSection("Name") {
                SomaBrowseGroup([SettingsItem].items("name"), hasGlyphs: false) { _ in
                    SettingsLine("First name") {
                        TextField("First name", text: Binding(
                            get: { draft.name ?? "" },
                            set: { draft.name = $0 }
                        ))
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textContentType(.givenName)
                        #endif
                    }
                }
            }

            SettingsSection("About you") {
                SomaBrowseGroup([SettingsItem].items("email", "sex", "birthday", "age"), hasGlyphs: false) { item in
                    aboutRow(item.id)
                }
            }

            SettingsSection("Sign in") {
                SomaBrowseGroup([SettingsItem].items("apple"), hasGlyphs: false) { _ in
                    SettingsLine("Sign in with Apple") {
                        Text(draft.appleUserID == nil ? String(localized: "Not connected") : String(localized: "Connected"))
                            .somaFont(theme.typography.rowValue)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                }
                AccountSignOutRow()
                SettingsFootnote("Kept on this device.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let saved = draft
                    store.update { $0 = saved }
                    dismiss()
                }
                .disabled(draft == store.profile)
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = store.profile
            loaded = true
        }
    }

    private var identity: some View {
        HStack(spacing: theme.metrics.browseRowSpacing) {
            photoControl
            VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
                Text(draft.firstName ?? String(localized: "No name yet"))
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if store.photo != nil {
                    Button("Remove photo", role: .destructive) { store.setPhoto(nil) }
                        .somaFont(theme.typography.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                } else {
                    Text("Tap to add a photo")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
    }

    /// The avatar opens the photo library: the picture is cut to a centred
    /// square, kept at 512 pixels on this device, and never uploaded.
    @ViewBuilder
    private var photoControl: some View {
        let avatar = ProfileAvatar(diameter: theme.metrics.minimumTapTarget * 1.4)
#if os(visionOS)
        avatar
#else
        PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: theme.metrics.browseGlyphSize))
                        .foregroundStyle(theme.colors.inkPrimary.color, theme.colors.surface.color)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(store.photo == nil ? "Add a photo" : "Change photo")
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    store.setPhoto(data)
                }
                pick = nil
            }
        }
#endif
    }


    @ViewBuilder
    private func aboutRow(_ id: String) -> some View {
        switch id {
        case "email":
            SettingsLine("Email") {
                TextField("Email", text: Binding(
                    get: { draft.email ?? "" },
                    set: { draft.email = $0.isEmpty ? nil : $0 }
                ))
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            }
        case "sex":
            SettingsLine("Sex") {
                SettingsMenuValue(
                    title: "Sex",
                    options: [BiologicalSex?.none] + BiologicalSex.allCases.map(Optional.some),
                    label: { $0?.title ?? String(localized: "Not set") },
                    selection: $draft.sex
                )
            }
        case "birthday":
            SettingsLine("Birthday") {
                if draft.birthday != nil {
                    DatePicker("Birthday", selection: Binding(
                        get: { draft.birthday ?? Date() },
                        set: { draft.birthday = $0 }
                    ), in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                } else {
                    Button("Add") {
                        draft.birthday = Calendar.current.date(byAdding: .year, value: -35, to: Date())
                    }
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(theme.colors.accent.color)
                    .buttonStyle(.plain)
                }
            }
        default:
            SettingsLine("Age") {
                Text(draft.age().map { "\($0)" } ?? "-")
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
    }
}

#Preview("Account details") {
    NavigationStack { AccountDetailsPage() }
}
