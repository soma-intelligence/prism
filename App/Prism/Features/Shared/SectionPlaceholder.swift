//
//  SectionPlaceholder.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A part of a tab that has its place in the layout and nothing behind it yet.
///
/// It says so plainly. A section that shows nothing and explains nothing is
/// indistinguishable from a broken one.
struct SectionPlaceholder: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource

    var body: some View {
        PageScaffold(eyebrow: eyebrow, title: title) {
            NoteCard(
                title: "Nothing here yet",
                message: "This part of the page has its place in the layout. What it shows is still to be built."
            )
        }
    }
}

#Preview("Section placeholder") {
    NavigationStack {
        SectionPlaceholder(eyebrow: "Pulse", title: "Trends")
    }
}
