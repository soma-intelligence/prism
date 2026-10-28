//
//  GenomePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import UniformTypeIdentifiers

/// What a 23andMe or AncestryDNA raw data file says about a few well studied
/// variants: the genotype, a plain reading, how strong the evidence is and
/// where it comes from. APOE waits behind its own choice, explained first.
///
/// Everything is read on this phone. Only the handful of variants is kept,
/// and the file itself only when the person asked to keep it.
struct GenomePage: View {
    @Environment(\.somaTheme) private var theme

    @State private var store = GenomeStore.shared
    @State private var isImporting = false
    @State private var asksAPOE = false
    @State private var asksDelete = false

    var body: some View {
        let result = store.result
        TabPartScaffold(
            aspect: nil,
            eyebrow: result.map { "\($0.provider.title) · \($0.importedAt.labDay)" },
            title: result == nil ? "No DNA file yet." : "\(result?.found.count ?? 0) variants read.",
            reason: result == nil
                ? "Import the raw data file from 23andMe or AncestryDNA. Soma reads it on this phone and keeps only the few variants below."
                : "Each one is a tendency seen in large studies, not a diagnosis. Tap a source to read it.",
            stats: result.map { result in [
                SomaStat("Read", value: result.snpsRead.formatted(.number.notation(.compactName))),
                SomaStat("No calls", value: result.noCalls.formatted(.number.notation(.compactName))),
                SomaStat("Kept file", value: result.keptFileName == nil ? "No" : "Yes"),
            ] } ?? []
        ) {
            if let result {
                ForEach(GenomeCatalog.shown) { variant in
                    GenomeVariantCard(variant: variant, genotype: result.genotype(variant))
                }
                apoeCard(result)
                LabRowGroup(heading: "This file", rows: [
                    LabRow("Build", detail: result.build),
                    LabRow("Import a newer file", action: { isImporting = true }),
                    LabRow("Delete the DNA data", detail: "from this phone", action: { asksDelete = true }),
                ])
            } else {
                SomaActionCard(
                    eyebrow: "Your DNA file",
                    title: "From 23andMe or AncestryDNA",
                    detail: "Download the raw data from the provider's site, then choose the .txt or the .zip here.",
                    actionTitle: "Import",
                    action: { isImporting = true }
                ) {
                    SomaOrb(aspect: .body, scale: .mini)
                }
            }
            LabFootnote("For information only: not a medical test and not a diagnosis. Consumer arrays can miscall rare variants. For anything about your health, a doctor or a genetic counsellor can tell you what it means for you.")
        }
        .labPageTitle(Text("Genome"))
        .sheet(isPresented: $isImporting) { GenomeImportSheet() }
        .confirmationDialog("Delete the DNA data?", isPresented: $asksDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The variants Soma kept, and the file if you kept it, are removed from this phone.")
        }
        .alert("Show your APOE type?", isPresented: $asksAPOE) {
            Button("Show APOE") { store.setShowsAPOE(true) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("APOE is linked to the risk of Alzheimer's disease. Some people would rather not know, and that is a fair choice. The result is a risk seen in large studies, not a diagnosis, and a consumer file can be wrong. A genetic counsellor can help you decide, and explain the result.")
        }
    }

    @ViewBuilder
    private func apoeCard(_ result: GenomeResult) -> some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                LabEyebrow("APOE · Alzheimer's risk")
                if store.showsAPOE {
                    if let apoe = result.apoe {
                        let meaning = apoe.type.meaning
                        Text(apoe.type.rawValue)
                            .somaFont(theme.typography.metricCompact)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        LabLeadText("\(meaning.headline). \(meaning.detail)")
                        if apoe.isAmbiguous {
                            Text("A file does not say which base sits on which chromosome: this pair reads as e2/e4, or very rarely e1/e3.")
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                        GenomeEvidenceLine(evidence: .strong, sources: GenomeCatalog.apoeSources)
                        Text("From rs429358 \(GenomeCatalog.byID["rs429358"].flatMap(result.genotype) ?? String(localized: "not read")) and rs7412 \(GenomeCatalog.byID["rs7412"].flatMap(result.genotype) ?? String(localized: "not read")), plus strand.")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    } else {
                        LabLeadText("Not in this file. One or both of the two variants that name the APOE type are missing or uncalled.")
                    }
                    Button("Hide APOE") { store.setShowsAPOE(false) }
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.accent.color)
                } else {
                    LabLeadText("Hidden until you choose to see it. APOE is linked to the risk of Alzheimer's disease, so Soma asks first.")
                    Button("Show APOE") { asksAPOE = true }
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.accent.color)
                }
            }
        }
    }
}

/// One variant: gene and trait, the genotype, what it means, the evidence
/// and the sources, and the strand it was read on.
struct GenomeVariantCard: View {
    let variant: GenomeVariant
    let genotype: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let meaning = genotype.flatMap(variant.meaning)
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                LabEyebrow("\(variant.trait) · \(variant.gene) \(variant.id)")
                HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
                    SomaNumber(genotype.map { Self.slashed($0) }, theme.typography.metricCompact)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    Text(meaning?.headline ?? "Not in this file")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let meaning {
                    Text(meaning.detail)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GenomeEvidenceLine(evidence: variant.evidence, sources: variant.sources)
                Text(variant.strandNote)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "AG" as "A/G".
    static func slashed(_ genotype: String) -> String { genotype.map(String.init).joined(separator: "/") }
}

/// The evidence word and the sources as links.
struct GenomeEvidenceLine: View {
    let evidence: GenomeEvidence
    let sources: [GenomeSource]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
            Text(evidence.title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(evidence == .limited ? theme.colors.statusOut.color : theme.colors.inkPrimary.color)
            ForEach(sources, id: \.self) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        Text(source.name)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.accent.color)
                    }
                }
            }
        }
    }
}

/// Importing a DNA file: what happens to it, the choice to keep it, then the
/// file picker and the read.
struct GenomeImportSheet: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var store = GenomeStore.shared
    @State private var keepsFile = false
    @State private var isPicking = false
    @State private var isReading = false
    @State private var failure: String?

    var body: some View {
        LabSheet(
            eyebrow: "Genome",
            title: "Import your DNA file",
            reason: "Download the raw data from 23andMe (Settings, then 23andMe Data) or AncestryDNA (Settings, then Download DNA data), then choose the .txt or the .zip. It is read on this phone and never uploaded."
        ) {
            HStack(spacing: theme.metrics.browseRowSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep the file on this iPhone")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    Text("Off: only the few variants on the Genome page are kept.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .accessibilityHidden(true)
                Spacer(minLength: theme.metrics.browseRowSpacing)
                SettingsSwitch(title: String(localized: "Keep the file on this iPhone"), isOn: $keepsFile)
            }
            .padding(.horizontal, theme.metrics.browseRowPadding)
            .frame(minHeight: theme.metrics.browseRowMinHeight)
            .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                .fill(theme.colors.surface.color))
            if isReading {
                HStack(spacing: theme.metrics.cardSpacing) {
                    ProgressView()
                    Text("Reading the file")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 12)
            } else {
                LabPrimaryButton(title: "Choose the file") { isPicking = true }
            }
            if let failure {
                Text(failure)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger.color)
            }
            LabFootnote("For information only, not a medical test. Importing replaces an earlier file.")
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.plainText, .text, .zip, .commaSeparatedText, .tabSeparatedText]) { result in
            guard case .success(let url) = result else { return }
            Task { await read(url) }
        }
    }

    private func read(_ url: URL) async {
        isReading = true
        failure = nil
        do {
            let parse = try await GenomeFileReader.read(url: url)
            let kept = keepsFile ? store.keep(copyOf: url) : nil
            store.save(GenomeResult(importedAt: .now, parse: parse, keptFileName: kept))
            isReading = false
            dismiss()
        } catch let error as GenomeFileReader.Failure {
            isReading = false
            failure = error.message
        } catch {
            isReading = false
            failure = GenomeFileReader.Failure.unreadable.message
        }
    }
}

#Preview("Genome") {
    NavigationStack {
        GenomePage()
    }
}
