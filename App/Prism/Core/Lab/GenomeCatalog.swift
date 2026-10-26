//
//  GenomeCatalog.swift
//  Prism
//
//  The few variants Soma reads from a consumer DNA file, each chosen because
//  it is common, well studied, and says something a person can use. Each one
//  carries its genotype table on the plus strand of GRCh37 (the orientation
//  both 23andMe and AncestryDNA write), a plain reading per genotype, how
//  strong the evidence is, and where it comes from.
//
//  Wording follows the FDA and FTC line for wellness genetics: informational,
//  never a diagnosis, never a reason to change a medicine, and a
//  professional for anything about health. APOE is held behind an explicit
//  choice to see it (`GenomeStore.showsAPOE`), because it speaks to
//  Alzheimer's risk.
//
//  Strand: the alleles below are the plus strand ones. A file written on the
//  other strand is caught when its alleles are the complement of the
//  expected pair, and flipped. A palindromic variant (A and T, or C and G)
//  cannot be told apart that way and is read as written; FTO rs9939609 is the
//  one here, and both providers write it on the plus strand.
//

import Foundation

nonisolated enum GenomeEvidence: String, Codable, Sendable, CaseIterable {
    case strong, moderate, limited

    var title: String {
        switch self {
        case .strong: "Strong evidence"
        case .moderate: "Moderate evidence"
        case .limited: "Limited evidence"
        }
    }
}

nonisolated struct GenomeSource: Sendable, Hashable {
    var name: String
    var url: String
}

/// What one genotype means, in a line and a paragraph.
nonisolated struct GenomeMeaning: Sendable, Hashable {
    var headline: String
    var detail: String
}

nonisolated struct GenomeVariant: Identifiable, Sendable, Hashable {
    /// The rsid, "rs762551".
    let id: String
    let gene: String
    let trait: String
    /// The two alleles on the plus strand, the reference first.
    let alleles: (Character, Character)
    let evidence: GenomeEvidence
    /// Which strand the table is on and what the gene's own naming is.
    let strandNote: String
    let sources: [GenomeSource]
    /// Genotype written sorted ("AC") to what it means.
    let meanings: [String: GenomeMeaning]
    /// Held behind the APOE choice.
    let isSensitive: Bool

    static func == (a: GenomeVariant, b: GenomeVariant) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var isPalindromic: Bool {
        let pair = Set([alleles.0, alleles.1])
        return pair == ["A", "T"] || pair == ["C", "G"]
    }

    /// The genotype read from a file, on the plus strand, sorted ("AG"), or
    /// nil for a no call or alleles that fit neither strand.
    func oriented(_ raw: String) -> String? {
        let letters = raw.uppercased().filter { "ACGT".contains($0) }
        guard letters.count == 2 else { return nil }
        let expected: Set<Character> = [alleles.0, alleles.1]
        if Set(letters).isSubset(of: expected) { return String(letters.sorted()) }
        guard !isPalindromic else { return nil }
        let flipped = letters.map(GenomeCatalog.complement)
        if Set(flipped).isSubset(of: expected) { return String(flipped.sorted()) }
        return nil
    }

    func meaning(of genotype: String) -> GenomeMeaning? { meanings[String(genotype.sorted())] }
}

nonisolated enum GenomeCatalog {
    static func complement(_ base: Character) -> Character {
        switch base {
        case "A": "T"
        case "T": "A"
        case "C": "G"
        case "G": "C"
        default: base
        }
    }

    private static func dbSNP(_ rsid: String) -> GenomeSource {
        GenomeSource(name: "dbSNP \(rsid)", url: "https://www.ncbi.nlm.nih.gov/snp/\(rsid)")
    }

    private static func snpedia(_ rsid: String) -> GenomeSource {
        GenomeSource(name: "SNPedia \(rsid)", url: "https://www.snpedia.com/index.php/\(rsid.capitalized)")
    }

    static let variants: [GenomeVariant] = [
        GenomeVariant(
            id: "rs762551", gene: "CYP1A2", trait: "Caffeine metabolism", alleles: ("A", "C"), evidence: .moderate,
            strandNote: "Plus strand, as the gene. The A allele is CYP1A2*1F, the more inducible form.",
            sources: [dbSNP("rs762551"),
                      GenomeSource(name: "PharmGKB CYP1A2", url: "https://www.pharmgkb.org/gene/PA27093"),
                      GenomeSource(name: "Cornelis et al., JAMA 2006", url: "https://pubmed.ncbi.nlm.nih.gov/16522833/"),
                      snpedia("rs762551")],
            meanings: [
                "AA": .init(headline: "Likely a fast caffeine metabolizer",
                            detail: "Two copies of the faster form. In studies, people with this genotype cleared caffeine sooner, especially smokers. How you feel after coffee is the better guide."),
                "AC": .init(headline: "Likely a slower caffeine metabolizer",
                            detail: "One copy of the faster form. Caffeine may stay with you longer, so an afternoon coffee can reach your night."),
                "CC": .init(headline: "Likely a slower caffeine metabolizer",
                            detail: "No copy of the faster form. Caffeine may stay with you longer, so an afternoon coffee can reach your night."),
            ], isSensitive: false),
        GenomeVariant(
            id: "rs4988235", gene: "MCM6 (LCT)", trait: "Lactose tolerance", alleles: ("A", "G"), evidence: .strong,
            strandNote: "Plus strand. The gene reads on the minus strand, where this is LCT -13910 C>T: plus strand A is the T allele that keeps lactase on.",
            sources: [dbSNP("rs4988235"),
                      GenomeSource(name: "ClinVar, lactase persistence", url: "https://www.ncbi.nlm.nih.gov/clinvar/?term=rs4988235"),
                      GenomeSource(name: "Enattah et al., Nat Genet 2002", url: "https://pubmed.ncbi.nlm.nih.gov/11788828/"),
                      snpedia("rs4988235")],
            meanings: [
                "AA": .init(headline: "Likely to digest milk into adulthood",
                            detail: "Two copies of the variant that keeps lactase on. Strongest evidence in people of European ancestry; other ancestries carry other variants that do the same."),
                "AG": .init(headline: "Likely to digest milk into adulthood",
                            detail: "One copy of the variant that keeps lactase on is usually enough. Strongest evidence in people of European ancestry."),
                "GG": .init(headline: "Lactase may fade after childhood",
                            detail: "No copy of the European persistence variant. Many people with this genotype digest less lactose as adults, but other variants can keep lactase on. Your own experience counts more than this line."),
            ], isSensitive: false),
        GenomeVariant(
            id: "rs1801133", gene: "MTHFR", trait: "Folate processing", alleles: ("G", "A"), evidence: .moderate,
            strandNote: "Plus strand. The gene reads on the minus strand, where this is C677T: plus strand A is the 677T allele.",
            sources: [dbSNP("rs1801133"),
                      GenomeSource(name: "ClinVar rs1801133", url: "https://www.ncbi.nlm.nih.gov/clinvar/?term=rs1801133"),
                      GenomeSource(name: "ACMG practice guideline, Genet Med 2013", url: "https://pubmed.ncbi.nlm.nih.gov/23288205/"),
                      snpedia("rs1801133")],
            meanings: [
                "GG": .init(headline: "The common form of MTHFR",
                            detail: "Two copies of 677C, the most common genotype. The enzyme works at its usual pace."),
                "AG": .init(headline: "One copy of 677T",
                            detail: "Around 4 in 10 people of European ancestry carry one. The enzyme runs a little slower; on its own this is not linked to illness."),
                "AA": .init(headline: "Two copies of 677T",
                            detail: "The enzyme runs slower and homocysteine can read higher, mostly when folate is low. Medical guidelines advise against acting on this result alone: a blood homocysteine and folate level say more. Talk to a doctor before taking any supplement for it."),
            ], isSensitive: false),
        GenomeVariant(
            id: "rs1815739", gene: "ACTN3", trait: "Fast twitch muscle protein", alleles: ("C", "T"), evidence: .moderate,
            strandNote: "Plus strand, as the gene. C is R577 (the working protein), T is 577X (a stop, no alpha actinin 3).",
            sources: [dbSNP("rs1815739"),
                      GenomeSource(name: "Yang et al., Am J Hum Genet 2003", url: "https://pubmed.ncbi.nlm.nih.gov/12879365/"),
                      snpedia("rs1815739")],
            meanings: [
                "CC": .init(headline: "Two working copies of ACTN3 (RR)",
                            detail: "Fast twitch fibres make alpha actinin 3. This genotype is more common among sprint and power athletes, but training matters far more than any gene."),
                "CT": .init(headline: "One working copy of ACTN3 (RX)",
                            detail: "Fast twitch fibres still make alpha actinin 3. The most common genotype in many populations."),
                "TT": .init(headline: "No alpha actinin 3 (XX)",
                            detail: "About one person in five in Europe. Somewhat more common among endurance athletes. Healthy, and no limit on what training can do."),
            ], isSensitive: false),
        GenomeVariant(
            id: "rs9939609", gene: "FTO", trait: "Weight tendency", alleles: ("T", "A"), evidence: .strong,
            strandNote: "Plus strand, as the gene. A and T are a palindromic pair, so the file's own orientation is trusted; both providers write the plus strand.",
            sources: [dbSNP("rs9939609"),
                      GenomeSource(name: "Frayling et al., Science 2007", url: "https://pubmed.ncbi.nlm.nih.gov/17434869/"),
                      GenomeSource(name: "Kilpelainen et al., PLoS Med 2011", url: "https://pubmed.ncbi.nlm.nih.gov/22069379/"),
                      snpedia("rs9939609")],
            meanings: [
                "TT": .init(headline: "No copy of the FTO weight allele",
                            detail: "The most studied weight variant. Its effect is small next to sleep, food and movement."),
                "AT": .init(headline: "One copy of the FTO weight allele",
                            detail: "On average about 1.2 kg more body weight in large studies. In active people the effect was about a quarter smaller."),
                "AA": .init(headline: "Two copies of the FTO weight allele",
                            detail: "On average about 3 kg more body weight in large studies. A tendency, not a fate: in active people the effect was about a quarter smaller."),
            ], isSensitive: false),
        GenomeVariant(
            id: "rs429358", gene: "APOE", trait: "APOE (part one)", alleles: ("T", "C"), evidence: .strong,
            strandNote: "Plus strand, as the gene. With rs7412 it names the APOE type: C here marks e4.",
            sources: [dbSNP("rs429358"), snpedia("rs429358")],
            meanings: [:], isSensitive: true),
        GenomeVariant(
            id: "rs7412", gene: "APOE", trait: "APOE (part two)", alleles: ("C", "T"), evidence: .strong,
            strandNote: "Plus strand, as the gene. With rs429358 it names the APOE type: T here marks e2.",
            sources: [dbSNP("rs7412"), snpedia("rs7412")],
            meanings: [:], isSensitive: true),
    ]

    static let byID: [String: GenomeVariant] = Dictionary(uniqueKeysWithValues: variants.map { ($0.id, $0) })

    static var wanted: Set<String> { Set(variants.map(\.id)) }

    /// The ones shown as their own cards: everything but APOE's two halves.
    static var shown: [GenomeVariant] { variants.filter { !$0.isSensitive } }

    static let apoeSources = [
        GenomeSource(name: "SNPedia APOE", url: "https://www.snpedia.com/index.php/APOE"),
        GenomeSource(name: "ClinVar APOE", url: "https://www.ncbi.nlm.nih.gov/clinvar/?term=APOE%5Bgene%5D"),
        GenomeSource(name: "Belloy et al., JAMA 2019", url: "https://pubmed.ncbi.nlm.nih.gov/31112260/"),
        GenomeSource(name: "Farrer et al., JAMA 1997", url: "https://pubmed.ncbi.nlm.nih.gov/9343467/"),
    ]
}

// MARK: - APOE

/// The APOE type from its two defining variants. Each allele is a pair of
/// bases on one chromosome: e2 is (T, T), e3 (T, C), e4 (C, C) and the rare
/// e1 (C, T), written as (rs429358, rs7412). A file does not say which base
/// sits on which chromosome, so one genotype pair (both heterozygous) reads
/// as e2/e4 or, far more rarely, e1/e3; the common reading is given and the
/// doubt is said.
nonisolated enum APOEType: String, Sendable, CaseIterable {
    case e2e2 = "e2/e2", e2e3 = "e2/e3", e3e3 = "e3/e3", e2e4 = "e2/e4", e3e4 = "e3/e4", e4e4 = "e4/e4"
    case e1e2 = "e1/e2", e1e4 = "e1/e4", e1e1 = "e1/e1"

    /// From the two genotypes, each sorted on the plus strand ("CT").
    static func from(rs429358: String, rs7412: String) -> (type: APOEType, isAmbiguous: Bool)? {
        let c = rs429358.filter { $0 == "C" }.count   // e4 or e1 marks
        let t = rs7412.filter { $0 == "T" }.count     // e2 or e1 marks
        guard rs429358.count == 2, rs7412.count == 2 else { return nil }
        switch (c, t) {
        case (0, 0): return (.e3e3, false)
        case (0, 1): return (.e2e3, false)
        case (0, 2): return (.e2e2, false)
        case (1, 0): return (.e3e4, false)
        case (1, 1): return (.e2e4, true)   // or e1/e3
        case (2, 0): return (.e4e4, false)
        case (1, 2): return (.e1e2, false)
        case (2, 1): return (.e1e4, false)
        case (2, 2): return (.e1e1, false)
        default: return nil
        }
    }

    var e4Copies: Int {
        switch self {
        case .e4e4: 2
        case .e2e4, .e3e4, .e1e4: 1
        default: 0
        }
    }

    var meaning: GenomeMeaning {
        switch e4Copies {
        case 2:
            return .init(headline: "Two copies of APOE e4",
                         detail: "About 2 in 100 people. In large studies this genotype carried the highest average risk of Alzheimer's disease, yet many people with it never develop it. It is a risk, not a diagnosis. A doctor or a genetic counsellor can explain what it means for you, and whether a clinical test makes sense.")
        case 1:
            return .init(headline: "One copy of APOE e4",
                         detail: "About 1 in 4 people. In large studies one copy raised the average risk of Alzheimer's disease; most people with it do not develop it. It is a risk, not a diagnosis. A doctor or a genetic counsellor can explain what it means for you.")
        default:
            if self == .e2e2 || self == .e2e3 {
                return .init(headline: "No APOE e4, with e2",
                             detail: "In large studies e2 carriers had a lower average risk of Alzheimer's disease. Two copies of e2 can affect blood fats in a few people; a lipid panel says more.")
            }
            return .init(headline: "No copy of APOE e4",
                         detail: "The most common type is e3/e3. Without e4, the average risk is the population's; it is not zero, and age, blood pressure, sleep and activity matter for everyone.")
        }
    }
}
