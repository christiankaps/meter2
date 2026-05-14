import XCTest

final class Meter2CompanionUITests: XCTestCase {
    func testCompanionLaunchShowsMeterShell() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Meter2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sync Now"].exists || app.buttons["Jetzt synchronisieren"].exists)
    }
}
