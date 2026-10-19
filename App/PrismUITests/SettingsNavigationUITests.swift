//
//  SettingsNavigationUITests.swift
//  PrismUITests
//

import XCTest

/// The settings sheet is one `NavigationStack` bound to a `[SettingsRoute]`
/// path, and every page it pushes has to land on it.
///
/// A page that brought a `NavigationStack` of its own onto that stack was
/// dropped on the way in, and the push after it trapped inside SwiftUI on
/// `AnyNavigationPath.Error.comparisonTypeMismatch`. The component gallery is
/// where that showed first; every not wired row and the account row did the
/// same. So each step pushes a page, proves it arrived, and goes back, and the
/// push that follows is the one that used to crash.
final class SettingsNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEverySettingsPageLandsAndTheNextPushSurvives() throws {
        let app = XCUIApplication()
        // The Developer section without seven taps: `UserDefaults` reads the
        // argument domain ahead of the app's own, and writes nothing back.
        app.launchArguments += ["-dev.revealed", "YES"]
        // Health as an empty store that asks nothing. Without it, a simulator
        // that has never answered puts Health's permission sheet over the app,
        // and that sheet belongs to Health's own view service: XCUITest cannot
        // see its buttons from here, and it does not swipe away.
        app.launchArguments += ["-health.empty", "YES"]
        // Past the first run, which otherwise stands in for the tabs.
        app.launchArguments += ["-onboarding.completed", "YES"]
        app.launch()

        let profile = app.buttons["Profile"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "Nothing opens Settings")
        profile.tap()

        push("Language and units", expecting: "Words and measures", in: app)
        pop(in: app)

        push("Account", expecting: "Sign in with Apple", in: app)
        pop(in: app)

        push("Developer tools", expecting: "Component gallery", in: app)
        push("Component gallery", expecting: "Components", in: app)
        pop(in: app)
        pop(in: app)

        // A page that never carried a stack, pushed after all of the above.
        push("Appearance", expecting: "How Soma looks", in: app)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Taps a row and waits for a text only the page it opens carries.
    @MainActor
    private func push(
        _ row: String,
        expecting landmark: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.buttons[row].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No row named \(row)", file: file, line: line)
        button.tap()

        let page = app.descendants(matching: .any).matching(identifier: landmark).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5), "\(row) did not open its page", file: file, line: line)
    }

    /// Goes back one page with the bar's own back button.
    @MainActor
    private func pop(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.buttons["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No way back", file: file, line: line)
        back.tap()
    }
}
