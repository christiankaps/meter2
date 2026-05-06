import XCTest
@testable import Meter2

final class Meter2Tests: XCTestCase {
    func testAppConfigurationMatchesTheProjectSetup() {
        XCTAssertEqual(AppConfiguration.appName, "Meter2")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "de.christiankaps.meter2")
        XCTAssertEqual(AppConfiguration.defaultWindowWidth, 800)
        XCTAssertEqual(AppConfiguration.defaultWindowHeight, 520)
    }

    func testAppBundleIsLoadedWithTheExpectedIconConfiguration() {
        let appBundle = Bundle.allBundles.first { $0.bundleIdentifier == AppConfiguration.bundleIdentifier }

        XCTAssertNotNil(appBundle)
        XCTAssertEqual(appBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Meter2")
        XCTAssertEqual(appBundle?.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIconVariants")
    }
}
