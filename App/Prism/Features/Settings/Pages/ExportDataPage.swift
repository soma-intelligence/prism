//
//  ExportDataPage.swift
//  Prism
//

import SwiftUI
import SomaUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// "Export my data": one ZIP of everything Soma holds on this device, made
/// here by ``DataExport``, then handed to the share sheet (a save panel on a
/// Mac). A copy can also go to the person's private storage, only while they
/// are signed in.
struct ExportDataPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health

    @State private var account = AccountSession.shared
    @State private var alsoUpload = false
    @State private var phase = Phase.idle
#if os(iOS)
    @State private var sharing: ShareFile?
#endif

    enum Phase: Equatable {
        case idle
        case working
        case ready(file: URL, uploaded: Bool)
        case failed(String)
    }

    var body: some View {
        ListScaffold(eyebrow: "Export", title: "Take your data") {
            SettingsSection("What it holds") {
                SettingsFootnote("Your profile and photo, the Journal, check-ins, moods, Track logs, blood panels, notifications, linked services, your Ask conversations, and every Apple Health reading Soma may read. One ZIP, made on this device.")
            }

            SettingsSection("Your account") {
                SomaBrowseGroup([SettingsItem].items("upload"), hasGlyphs: false) { _ in
                    SettingsLine(
                        String(localized: "Also save to my account"),
                        detail: account.isSignedIn
                            ? String(localized: "A copy in your private Soma storage")
                            : String(localized: "Sign in to keep a copy online")
                    ) {
                        SettingsSwitch(title: String(localized: "Also save to my account"), isOn: uploadBinding)
                            .disabled(!account.isSignedIn || phase == .working)
                    }
                }
            }

            action
            status
        }
#if os(iOS)
        .sheet(item: $sharing) { ActivitySheet(url: $0.url) }
#endif
    }

    /// Off whenever nobody is signed in, whatever was switched before.
    private var uploadBinding: Binding<Bool> {
        Binding(get: { alsoUpload && account.isSignedIn }, set: { alsoUpload = $0 })
    }

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .working:
            HStack(spacing: theme.metrics.browseRowSpacing) {
                ProgressView()
                Text("Gathering your data")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
            .accessibilityElement(children: .combine)
        case .ready(let file, _):
            VStack(spacing: theme.metrics.cardSpacing) {
                ShareLink(item: file) {
                    capsule(String(localized: "Share the export"), symbol: "square.and.arrow.up")
                }
                .buttonStyle(.somaGlassPress)
#if os(macOS)
                Button { save(file) } label: {
                    capsule(String(localized: "Save a copy"), symbol: "arrow.down.doc")
                }
                .buttonStyle(.somaGlassPress)
#endif
                Button { Task { await run() } } label: {
                    Text("Make it again")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        default:
            Button { Task { await run() } } label: {
                capsule(String(localized: "Make the export"), symbol: "doc.zipper")
            }
            .buttonStyle(.somaGlassPress)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .ready(_, let uploaded):
            SettingsFootnote(uploaded
                ? "Ready, and a copy is saved to your account."
                : "Ready. Nothing left this device.")
        case .failed(let reason):
            Text(reason)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.danger.color)
                .padding(.horizontal, theme.metrics.browseRowPadding)
        default:
            SettingsFootnote("Apple Health keeps its own export too: in the Health app, tap your picture, then Export All Health Data.")
        }
    }

    private func capsule(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .somaFont(theme.typography.body)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
            .background(Capsule().strokeBorder(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity * 2), lineWidth: 1))
            .contentShape(.capsule)
    }

    private func run() async {
        phase = .working
        do {
            let result = try await DataExport.run(upload: alsoUpload && account.isSignedIn, scores: health.scores)
            phase = .ready(file: result.file, uploaded: result.uploadedPath != nil)
            present(result.file)
        } catch {
            phase = .failed(String(localized: "The export couldn’t be made. Try again."))
        }
    }

    /// Opens the share sheet on a phone, the save panel on a Mac. The headset
    /// keeps the Share button, which is its own share sheet.
    private func present(_ file: URL) {
#if os(iOS)
        sharing = ShareFile(url: file)
#elseif os(macOS)
        save(file)
#endif
    }

#if os(macOS)
    private func save(_ file: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let target = panel.url else { return }
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: file, to: target)
        }
    }
#endif
}

#if os(iOS)
/// The file the share sheet is open on.
private struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet on one file, for when the export finishes and the
/// sheet should open without a second tap.
private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

#Preview("Export") {
    NavigationStack { ExportDataPage() }
        .environment(HealthDashboard())
}
