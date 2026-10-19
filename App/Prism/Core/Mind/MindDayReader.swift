//
//  MindDayReader.swift
//  Prism
//
//  Picks the people, the places and the moments out of a day told in words,
//  on the phone, with Apple's NaturalLanguage: names from its name tagger,
//  moments from the words the event classifier knows, and each moment's pull
//  from the tone of its sentence. Nothing is sent anywhere.
//

import Foundation
import NaturalLanguage

enum MindDayReader {
    /// A sentence at or above this tone lifted; at or under its negative, weighed.
    static let pullThreshold = 0.2

    static func read(_ text: String, day: Date, store: MindStore? = nil) -> MindDayNote {
        var note = MindDayNote(day: day, text: text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return note }

        let names = NLTagger(tagSchemes: [.nameType])
        names.string = text
        var people: [String] = []
        var places: [String] = []
        names.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            let word = String(text[range])
            if tag == .personalName, !people.contains(word) { people.append(word) }
            if tag == .placeName, !places.contains(word) { places.append(word) }
            return true
        }
        note.people = people
        note.places = places

        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = text
        var moments: [MindMoment] = []
        sentences.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            guard let title = momentTitle(in: sentence, people: people) else { return true }
            let category = store?.category(of: title) ?? MindEventClassifier.category(title: title)
            guard !moments.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else { return true }
            moments.append(MindMoment(title: title, category: category, pull: pull(of: sentence)))
            return true
        }
        note.moments = moments
        return note
    }

    /// The tone of a sentence, as a pull.
    static func pull(of sentence: String) -> MindPull {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = sentence
        let (tag, _) = tagger.tag(at: sentence.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let score = Double(tag?.rawValue ?? "0") ?? 0
        if score >= pullThreshold { return .lifted }
        if score <= -pullThreshold { return .weighed }
        return .none
    }

    /// The moment a sentence names: the word the classifier knows, the one or
    /// two describing words before it, and "with" a person after it.
    static func momentTitle(in sentence: String, people: [String]) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var words: [(String, NLTag?)] = []
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            words.append((String(sentence[range]), tag))
            return true
        }
        guard let index = words.firstIndex(where: { word in
            MindEventClassifier.category(title: word.0) != .unknown
        }) else { return nil }

        var start = index
        while start > 0, index - start < 2, [NLTag.noun, .adjective].contains(words[start - 1].1) {
            start -= 1
        }
        var picked = words[start...index].map(\.0)
        if index + 2 < words.count, words[index + 1].0.lowercased() == "with",
           people.contains(words[index + 2].0) {
            picked += ["with", words[index + 2].0]
        }
        let title = picked.joined(separator: " ")
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}
