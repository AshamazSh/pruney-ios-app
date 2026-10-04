import XCTest

final class PruneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOnboardingDenialAndPersistentOverview() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["-resetOnboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Pruney"].exists)
        app.buttons["onboarding.continue"].tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Don' OR label CONTAINS[c] 'Не разреш'" )).firstMatch
        XCTAssertTrue(deny.exists)
        deny.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Photo access needed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Denied access"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Photo access needed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.continue"].exists)
    }

    @MainActor
    func testAuthorizedLibraryOverview() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["-resetOnboarding"]
        app.launch()
        let onboarding = XCTAttachment(screenshot: app.screenshot())
        onboarding.name = "Onboarding"
        onboarding.lifetime = .keepAlways
        add(onboarding)
        app.buttons["onboarding.continue"].tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let fullAccess = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label CONTAINS[c] 'полный доступ' OR label CONTAINS[c] 'ко всем'" )).firstMatch
        XCTAssertTrue(fullAccess.exists)
        fullAccess.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Accessible file size"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Live Photos"].exists)
        XCTAssertTrue(app.staticTexts["Videos"].exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Library overview"
        overview.lifetime = .keepAlways
        add(overview)
    }
}
