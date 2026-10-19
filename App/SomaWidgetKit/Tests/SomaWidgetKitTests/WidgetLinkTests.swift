import Foundation
import Testing
@testable import SomaWidgetKit

struct WidgetLinkTests {
    @Test func urls() {
        #expect(WidgetLink.score(.recovery).url.absoluteString == "soma://score/recovery")
        #expect(WidgetLink.score(.strain).url.absoluteString == "soma://score/strain")
        #expect(WidgetLink.mood.url.absoluteString == "soma://track/mood")
        #expect(WidgetLink.captureStart.url.absoluteString == "soma://capture/start")
    }

    @Test func everyLinkHasItsURL() {
        #expect(WidgetLink.vitals.url.absoluteString == "soma://vitals")
        #expect(WidgetLink.fuel.url.absoluteString == "soma://fuel")
        #expect(WidgetLink.journal.url.absoluteString == "soma://journal")
        #expect(WidgetLink.meal.url.absoluteString == "soma://track/meal")
        for kind in ScoreKind.allCases {
            #expect(WidgetLink.score(kind).url.absoluteString == "soma://score/\(kind.rawValue)")
        }
    }
}
