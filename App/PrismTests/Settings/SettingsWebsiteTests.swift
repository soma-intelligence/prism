//
//  SettingsWebsiteTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Settings website pages")
struct SettingsWebsiteTests {
    @Test("Terms and Privacy open the website's own legal pages")
    func legalRoutesOpenTheWebsite() {
        #expect(SettingsRoute.terms.websiteURL == URL(string: "https://www.somalabs.me/legal/terms"))
        #expect(SettingsRoute.privacy.websiteURL == URL(string: "https://www.somalabs.me/legal/privacy"))
        #expect(SettingsRoute.help.websiteURL == URL(string: "https://www.somalabs.me/help"))
    }

    @Test("Every other route draws a page of its own")
    func otherRoutesStayInTheApp() {
        for route in [SettingsRoute.appearance, .openSource, .about, .healthAccess, .developerTools] {
            #expect(route.websiteURL == nil)
        }
    }
}
