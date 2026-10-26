//
//  AskModelPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Which model writes Ask's answers: Apple Intelligence on the phone, Soma's
/// own, or the person's account at OpenAI, Anthropic, OpenRouter, Azure or
/// any compatible server. Each row says whether it is ready and, if not,
/// what is missing; the chosen one opens its key, model and address.
struct AskModelPage: View {
    @Environment(\.somaTheme) private var theme
    @State private var settings = AskProviderSettings.shared

    var body: some View {
        let effective = settings.effective

        ListScaffold(eyebrow: "Ask Soma", title: "Model") {
            SettingsSection("Answers come from") {
                SomaBrowseGroup(AskProvider.allCases) { provider in
                    Button {
                        settings.chosen = provider
                    } label: {
                        SettingsLine(provider.title, detail: settings.missing(for: provider) ?? provider.detail) {
                            if provider == effective {
                                Image(systemName: "checkmark")
                                    .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                                    .foregroundStyle(theme.colors.inkPrimary.color)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(SettingsRowPressStyle())
                    .accessibilityAddTraits(provider == effective ? .isSelected : [])
                }
                .sensoryFeedback(.selection, trigger: effective)
            }

            if effective.needsKey || effective.needsEndpoint || effective == .azure || effective == .custom {
                AskProviderFields(provider: effective, settings: settings)
                    .id(effective)
            }

            SettingsFootnote(effective == .appleIntelligence
                ? "Apple Intelligence answers on this iPhone. Nothing leaves it."
                : effective == .soma
                ? "Your question and today\u{2019}s numbers go to Soma\u{2019}s model, and nowhere else."
                : "Your question and today\u{2019}s numbers go to \(effective.title) with your key. The key stays in this iPhone\u{2019}s Keychain.")
        }
    }
}

/// The key, model and address of the chosen provider.
private struct AskProviderFields: View {
    let provider: AskProvider
    let settings: AskProviderSettings

    @Environment(\.somaTheme) private var theme
    @State private var key = ""
    @State private var model = ""
    @State private var endpoint = ""

    var body: some View {
        let metrics = theme.metrics

        SettingsSection("\(provider.title)") {
            VStack(spacing: 0) {
                if provider.needsKey {
                    field("API key", text: $key, secure: true, prompt: settings.key(for: provider) == nil ? "Paste your key" : "Saved. Paste to replace")
                        .onSubmit { settings.setKey(key, for: provider); key = "" }
                }
                if provider.needsEndpoint {
                    field("Address", text: $endpoint, prompt: provider == .azure ? "https://name.openai.azure.com" : "https://server/v1")
                        .onChange(of: endpoint) { settings.setEndpoint(endpoint, for: provider) }
                }
                field(provider == .azure ? "Deployment" : "Model", text: $model,
                      prompt: provider.defaultModel.isEmpty ? "Name" : provider.defaultModel)
                    .onChange(of: model) { settings.setModel(model, for: provider) }
            }
            .background(theme.colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        }
        .onAppear {
            model = settings.model(for: provider) == provider.defaultModel ? "" : settings.model(for: provider)
            endpoint = settings.endpoint(for: provider)
        }
        .onDisappear {
            if !key.isEmpty { settings.setKey(key, for: provider) }
        }
    }

    private func field(_ title: LocalizedStringResource, text: Binding<String>, secure: Bool = false, prompt: String) -> some View {
        let metrics = theme.metrics
        return HStack(spacing: metrics.browseRowSpacing) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(width: metrics.minimumTapTarget * 2.3, alignment: .leading)
            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                }
            }
            .somaFont(theme.typography.body)
#if os(iOS) || os(visionOS)
            .textInputAutocapitalization(.never)
#endif
            .autocorrectionDisabled()
            .submitLabel(.done)
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .frame(minHeight: metrics.browseRowMinHeight)
    }
}
