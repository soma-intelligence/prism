//
//  AskHistoryDrawer.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Ask's history, slid in from the leading edge: search, a new conversation,
/// Health records, past conversations by week and month, and the profile card
/// that opens Settings.
///
/// The chat history drawer. The conversations are the
/// ones ``AskHistoryStore`` keeps on this device, which, once someone is
/// signed in, holds every conversation in their account: opening the drawer
/// and pulling it down fetch the ones asked on another phone, and a delete
/// here deletes it in the account too.
struct AskHistoryDrawer: View {
    let current: UUID?
    let open: (UUID) -> Void
    let startNew: () -> Void
    let openRecords: () -> Void
    let openSettings: () -> Void

    @Environment(\.somaTheme) private var theme

    @State private var history = AskHistoryStore.shared
    @State private var profiles = SomaProfileStore.shared
    @State private var query = ""
    @State private var pendingDelete: UUID?

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(spacing: metrics.scoreLabelSpacing * 2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(colors.inkSecondary.color)
                TextField("Search conversations", text: $query)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, metrics.cardPadding)
            .frame(minHeight: metrics.minimumTapTarget)
            .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous).fill(colors.surface.color))

            drawerButton("New conversation", symbol: "square.and.pencil", isAccent: true, action: startNew)
            drawerButton("Health records", detail: "From your clinic, by kind", symbol: "list.clipboard", action: openRecords)

            Rectangle()
                .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                .frame(height: 0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                    if sections.isEmpty {
                        Text(query.isEmpty ? "Your conversations with Soma are kept here, and in your account once you sign in." : "No conversation matches.")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, metrics.cardSpacing)
                    }
                    ForEach(sections) { section in
                        Text(section.title)
                            .somaFont(theme.typography.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.inkSecondary.color)
                            .padding(.top, metrics.cardSpacing)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.ids, id: \.self) { id in
                            if let conversation = history.conversation(id) {
                                conversationRow(conversation)
                            }
                        }
                    }
                }
            }
            .refreshable { await CloudSync.shared.syncAskHistory() }
#if !os(visionOS)
            // The headset's keyboard floats apart from the window.
            .scrollDismissesKeyboard(.interactively)
#endif

            profileCard
        }
        .padding(metrics.pagePadding * 0.8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(colors.canvas.color.ignoresSafeArea())
        .task { await CloudSync.shared.syncAskHistory() }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { history.delete(pendingDelete) }
                if pendingDelete == current { startNew() }
                pendingDelete = nil
            }
        } message: {
            Text("It goes from this device and from your account.")
        }
    }

    private var sections: [ChatHistorySections.Section] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = history.conversations.filter { conversation in
            needle.isEmpty
                || conversation.title.lowercased().contains(needle)
                || conversation.turns.contains { $0.question.lowercased().contains(needle) || $0.lead.lowercased().contains(needle) }
        }
        return ChatHistorySections.group(matching.map { (id: $0.id, date: $0.updated) }, now: Date(), calendar: .current)
    }

    private func conversationRow(_ conversation: AskConversation) -> some View {
        let isCurrent = conversation.id == current
        return Button { open(conversation.id) } label: {
            VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
                Text(conversation.title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .lineLimit(1)
                Text(ChatHistorySections.stamp(conversation.updated, now: Date(), calendar: .current))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            .padding(.horizontal, theme.metrics.scoreLabelSpacing * 2)
            .padding(.vertical, theme.metrics.scoreLabelSpacing * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius * 0.6, style: .continuous)
                    .fill(isCurrent ? theme.colors.surface.color : .clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = conversation.id }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func drawerButton(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        symbol: String,
        isAccent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.metrics.browseRowSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: theme.metrics.browseGlyphSize))
                    .frame(width: theme.metrics.browseGlyphColumn)
                VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
                    Text(title).somaFont(theme.typography.body)
                    if let detail {
                        Text(detail)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                }
                Spacer(minLength: 0)
                if detail != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            .foregroundStyle(isAccent ? theme.colors.accent.color : theme.colors.inkPrimary.color)
            .frame(minHeight: theme.metrics.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var profileCard: some View {
        Button(action: openSettings) {
            SomaCard {
                HStack(spacing: theme.metrics.browseRowSpacing) {
                    SomaAvatarFace(shape: .circle, diameter: theme.metrics.minimumTapTarget)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
                        Text(profiles.profile.firstName ?? String(localized: "Your account"))
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        Text(profiles.profile.email ?? String(localized: "Settings"))
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel("Settings")
    }
}
