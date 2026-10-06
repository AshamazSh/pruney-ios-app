import XCTest

// Run only against a dedicated simulator seeded with disposable QA media.
final class ReleaseReadinessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRUNEY_RELEASE_UI_INTEGRATION"] == "1",
                          "Opt in only on a dedicated simulator containing disposable QA media.")
    }

    @MainActor override func tearDownWithError() throws {
        capture(XCUIApplication(), "Final state — \(name)")
    }

    @MainActor private func launchAuthorized() -> XCUIApplication {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["-resetOnboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 10))
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.buttons["onboarding.continue"].tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Full Access'")).firstMatch
        XCTAssertTrue(allow.exists)
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["library.startSwiping"].waitForExistence(timeout: 60))
        return app
    }

    @MainActor private func startReview(_ app: XCUIApplication) {
        app.buttons["library.startSwiping"].tap()
        XCTAssertTrue(app.buttons["review.skipped"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+ items remaining")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func remaining(_ app: XCUIApplication) -> Int {
        let value = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+ items remaining")).firstMatch.label
        return Int(value.split(separator: " ").first ?? "") ?? -1
    }

    @MainActor private func waitForRemaining(_ count: Int, app: XCUIApplication) {
        let element = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+ items remaining")).firstMatch
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "\(count) of "), evaluatedWith: element)
        waitForExpectations(timeout: 10)
    }

    @MainActor private func decide(_ decision: String, app: XCUIApplication) {
        let before = remaining(app)
        app.buttons["review.\(decision)"].tap()
        if before > 1 { waitForRemaining(before - 1, app: app) }
    }

    @MainActor private func bulk(_ action: String, app: XCUIApplication) {
        app.buttons["review.bulkActions"].tap()
        let button = app.buttons[action]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testFiltersSheetValidationAndOrTiles() {
        let app = launchAuthorized()
        app.buttons["library.setUpFilters"].tap()
        XCTAssertFalse(app.buttons["filters.apply"].isEnabled)
        app.buttons["filters.add"].tap()
        XCTAssertTrue(app.buttons["filter.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filter.add"].isEnabled)
        app.buttons["filter.enable.type"].tap()
        XCTAssertTrue(app.buttons["filter.add"].isEnabled)
        app.buttons["filter.add"].tap()
        XCTAssertTrue(app.buttons["filters.apply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["filters.apply"].isEnabled)
        app.buttons["filters.add"].tap()
        app.buttons["filter.enable.size"].tap()
        app.buttons["filter.add"].tap()
        XCTAssertTrue(app.staticTexts["OR"].waitForExistence(timeout: 5))
        capture(app, "Alternative filter tiles")
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'filters.remove.'"))
        XCTAssertEqual(remove.count, 2)
        remove.firstMatch.tap()
        XCTAssertFalse(app.staticTexts["OR"].exists)
        remove.firstMatch.tap()
        XCTAssertFalse(app.buttons["filters.apply"].isEnabled)
    }

    @MainActor func testKeepUndoResetSortingAndReadOnlyCompletion() {
        let app = launchAuthorized()
        startReview(app)
        let initial = remaining(app)
        XCTAssertGreaterThan(initial, 50, "Seed the dedicated simulator with the QA media before running.")
        decide("skipped", app: app)
        XCTAssertEqual(remaining(app), initial - 1)
        app.buttons["review.undo"].tap()
        waitForRemaining(initial, app: app)
        XCTAssertEqual(remaining(app), initial)
        decide("deleted", app: app)
        app.buttons["Sort remaining items"].tap()
        app.buttons["By size"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["review.undo"])
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+ items remaining")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["review.undo"].tap()
        waitForRemaining(initial, app: app)
        XCTAssertEqual(remaining(app), initial)
        decide("skipped", app: app)
        app.buttons["review.undo"].press(forDuration: 1.7)
        XCTAssertTrue(app.alerts["Reset all selections?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Reset"].tap()
        XCTAssertEqual(remaining(app), initial)
        bulk("Keep all", app: app)
        XCTAssertTrue(app.buttons["review.backToLibrary"].waitForExistence(timeout: 10))
        capture(app, "Read-only review completion")
        app.buttons["review.backToLibrary"].tap()
        XCTAssertTrue(app.buttons["library.startSwiping"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts["Recently Deleted"].exists)
    }

    @MainActor func testBulkLimitsCancelWithoutSelectingAnything() {
        let app = launchAuthorized()
        startReview(app)
        let initial = remaining(app)
        bulk("Resize / Make static", app: app)
        XCTAssertTrue(app.buttons["pro.cancel"].waitForExistence(timeout: 10))
        capture(app, "Lifetime offer for over-limit resize batch")
        app.buttons["pro.cancel"].tap()
        XCTAssertEqual(remaining(app), initial)
        bulk("Delete all", app: app)
        XCTAssertTrue(app.buttons["pro.cancel"].waitForExistence(timeout: 10))
        app.buttons["pro.cancel"].tap()
        XCTAssertEqual(remaining(app), initial)
        XCTAssertFalse(app.buttons["review.undo"].isEnabled)
        bulk("Keep all", app: app)
        XCTAssertTrue(app.buttons["review.backToLibrary"].waitForExistence(timeout: 10))
    }

    @MainActor func testIndividualResizeLimitRejectsEleventhAndUndoFreesCapacity() {
        let app = launchAuthorized()
        startReview(app)
        let initial = remaining(app)
        for _ in 0..<10 { decide("resized", app: app) }
        XCTAssertEqual(remaining(app), initial - 10)
        app.buttons["review.resized"].tap()
        XCTAssertTrue(app.buttons["pro.cancel"].waitForExistence(timeout: 10))
        app.buttons["pro.cancel"].tap()
        XCTAssertEqual(remaining(app), initial - 10)
        app.buttons["review.undo"].tap()
        waitForRemaining(initial - 9, app: app)
        decide("resized", app: app)
        XCTAssertFalse(app.buttons["pro.cancel"].exists)
        XCTAssertEqual(remaining(app), initial - 10)
    }

    @MainActor func testIndividualDeleteLimitRejectsFiftyFirst() {
        let app = launchAuthorized()
        startReview(app)
        let initial = remaining(app)
        for _ in 0..<50 { decide("deleted", app: app) }
        XCTAssertEqual(remaining(app), initial - 50)
        app.buttons["review.deleted"].tap()
        XCTAssertTrue(app.buttons["pro.cancel"].waitForExistence(timeout: 10))
        app.buttons["pro.cancel"].tap()
        XCTAssertEqual(remaining(app), initial - 50)
        capture(app, "Fifty deletions reserved, next item retained")
    }

    @MainActor func testVideoControlsAndDragStayInsideReview() {
        let app = launchAuthorized()
        app.buttons["library.setUpFilters"].tap()
        app.buttons["filters.add"].tap()
        app.buttons["filter.enable.type"].tap()
        app.buttons["filter.type"].tap()
        app.buttons["Videos"].tap()
        app.buttons["filter.add"].tap()
        app.buttons["filters.apply"].tap()
        XCTAssertTrue(app.buttons["review.skipped"].waitForExistence(timeout: 20))
        let initial = remaining(app)
        decide("skipped", app: app)
        let play = app.buttons.matching(NSPredicate(format: "(label == 'Play video' OR label == 'Pause video') AND enabled == true")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 15)
        let timeline = app.sliders.matching(NSPredicate(format: "label == 'Video position' AND enabled == true")).firstMatch
        XCTAssertTrue(timeline.exists)
        let before = timeline.frame
        play.tap()
        app.buttons.matching(NSPredicate(format: "label == 'Mute video' AND enabled == true")).firstMatch.tap()
        timeline.adjust(toNormalizedSliderPosition: 0.5)
        capture(app, "Video playback and timeline")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)))
        waitForRemaining(initial - 2, app: app)
        XCTAssertEqual(remaining(app), initial - 2)
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertEqual(timeline.frame.minY, before.minY, accuracy: 2)
        XCTAssertTrue(app.buttons["review.bulkActions"].exists, "Review must not navigate back on a rightward drag.")
        capture(app, "Next video with stable playback panel")
    }
    @MainActor private func photosMutationAlert(_ app: XCUIApplication) -> XCUIElement {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if system.waitForExistence(timeout: 5) { return system }
        let own = app.alerts.firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10), app.debugDescription)
        return own
    }

    @MainActor func testZDeletionCancellationPreservesSelectionThenBatchReturnsToLibrary() {
        let app = launchAuthorized()
        startReview(app)
        let initial = remaining(app)
        decide("deleted", app: app)
        bulk("Keep all", app: app)
        XCTAssertTrue(app.buttons["review.deleteSelected"].waitForExistence(timeout: 10))
        app.buttons["review.deleteSelected"].tap()
        let first = photosMutationAlert(app)
        capture(app, "Photos deletion confirmation")
        let cancel = first.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow' OR label == 'Cancel'")).firstMatch
        XCTAssertTrue(cancel.exists, first.debugDescription)
        cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts["Deletion did not complete"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["review.deleteSelected"].exists)
        app.buttons["review.deleteSelected"].tap()
        let second = photosMutationAlert(app)
        let remove = second.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete'")).firstMatch
        XCTAssertTrue(remove.exists, second.debugDescription)
        remove.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts["Recently Deleted"].waitForExistence(timeout: 30))
        capture(app, "Recently Deleted notice after deletion")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["library.startSwiping"].waitForExistence(timeout: 30))
        startReview(app)
        XCTAssertEqual(remaining(app), initial - 1)
    }

    @MainActor func testZPhotoReplacementAndRecentlyDeletedNotice() {
        let app = launchAuthorized()
        app.buttons["library.setUpFilters"].tap()
        app.buttons["filters.add"].tap()
        app.buttons["filter.enable.type"].tap()
        app.buttons["filter.add"].tap()
        app.buttons["filters.apply"].tap()
        XCTAssertTrue(app.buttons["review.resized"].waitForExistence(timeout: 20))
        decide("resized", app: app)
        bulk("Keep all", app: app)
        XCTAssertTrue(app.buttons["review.continueToActions"].waitForExistence(timeout: 10))
        app.buttons["review.continueToActions"].tap()
        XCTAssertTrue(app.buttons["resize.continueToDeletion"].waitForExistence(timeout: 10))
        app.buttons["resize.continueToDeletion"].tap()
        app.buttons["actions.start"].tap()
        let alert = photosMutationAlert(app)
        capture(app, "Photos replacement confirmation")
        let remove = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete'")).firstMatch
        XCTAssertTrue(remove.exists, alert.debugDescription)
        remove.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["All done!"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["0 deleted · 1 resized · 0 made static"].exists)
        capture(app, "Completed photo replacement")
        app.buttons["actions.backToLibrary"].tap()
        XCTAssertTrue(app.alerts["Recently Deleted"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["library.startSwiping"].waitForExistence(timeout: 30))
    }

}
