import XCTest

final class CyclometerUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testRideMetricsDashboardLoads() throws {
        // Hero speed label should show 0.0 on cold launch
        XCTAssertTrue(app.staticTexts["0.0"].waitForExistence(timeout: 5))
    }

    func testStartRideButtonExists() throws {
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }
}
