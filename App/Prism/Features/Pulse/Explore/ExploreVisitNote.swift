//
//  ExploreVisitNote.swift
//  Prism
//

import SwiftUI

extension View {
    /// Notes, on this device only, that a page about `topic` was opened, so
    /// Explore can lead with what the person looks at most. Nil notes
    /// nothing.
    func notesVisit(_ topic: ArticleTopic?) -> some View {
        onAppear {
            if let topic { ExploreInterest.shared.noteVisit(topic) }
        }
    }
}
