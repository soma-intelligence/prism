//
//  BodyHeaderAndAdditionsTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
#if canImport(UIKit)
import UIKit
#endif
@testable import Prism

@Suite("Body: the header photographs and adding to the biomarkers")
struct BodyHeaderAndAdditionsTests {
    @Test("A blood test can always be added; readings only where this build writes to Health")
    func additions() {
        #expect(BodyAddition.offered(canWrite: false) == [.bloodTest])
        let all = BodyAddition.offered(canWrite: true)
        #expect(all.first == .bloodTest)
        #expect(all.count == 5)
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test("One credited photograph per aspect, none of the old landscapes left")
    func credits() {
        let credits = PhotoCredit.all
        #expect(credits.count == SomaAspect.allCases.count)
        #expect(Set(credits.map(\.photoID)).count == credits.count)
        #expect(Set(credits.map(\.aspect)).count == credits.count)
        // The first landscapes, then the warm forest set of round two, replaced
        // on 2026-10-20 by the quieter Oura-like grade.
        let gone = ["mPnxwQBtUZE", "1Q578d01zas", "oVWm9rQpbq0", "JP23z_-dA74", "qWmUGrV8B54", "HHYpIR68Eds",
                    "J1LpF-yJLf0", "gghk1DME6Cw", "qiWaWWhehTo", "AjsOy7aoX0Y", "OOE4xAnBhKo", "3y4Nafb_Zgg"]
        #expect(credits.allSatisfy { !gone.contains($0.photoID) })
    }

    @Test("NOTICE.md credits the same photographs as Settings, About")
    func noticeMatches() throws {
        let notice = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "open-source/overlay/NOTICE.md")
        let text = try String(contentsOf: notice, encoding: .utf8)
        for credit in PhotoCredit.all {
            #expect(text.contains("https://unsplash.com/photos/\(credit.photoID)"), "\(credit.photoID)")
            #expect(text.contains(credit.author), "\(credit.author)")
        }
    }

    #if canImport(UIKit)
    @Test("Every aspect's photograph ships, sized for the head of a page at 3x")
    func photographsShip() {
        for aspect in SomaAspect.allCases {
            let image = UIImage(named: SomaBackdropStyle.photoName(for: aspect))
            #expect(image != nil, "\(aspect)")
            if let image {
                #expect(image.size.width * image.scale >= 1_206, "\(aspect)")
                #expect(image.size.height > image.size.width, "\(aspect)")
            }
        }
    }
    #endif
}
