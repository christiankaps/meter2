import XCTest

@testable import Meter2

final class Meter2AppTests: XCTestCase {
    func testAppConfigurationMatchesTheProjectSetup() {
        XCTAssertEqual(AppConfiguration.appName, "Meter2")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "de.christiankaps.meter2")
        XCTAssertEqual(AppConfiguration.companionBundleIdentifier, "de.christiankaps.meter2.companion")
        XCTAssertEqual(AppConfiguration.iCloudContainerIdentifier, "iCloud.de.christiankaps.meter2")
        XCTAssertEqual(AppConfiguration.defaultWindowWidth, 800)
        XCTAssertEqual(AppConfiguration.defaultWindowHeight, 520)
    }

    func testAppBundleIsLoadedWithTheExpectedIconConfiguration() {
        let appBundle = Bundle.allBundles.first { $0.bundleIdentifier == AppConfiguration.bundleIdentifier }

        XCTAssertNotNil(appBundle)
        XCTAssertEqual(appBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Meter2")
        XCTAssertEqual(appBundle?.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIconVariants")
    }

    func testAppearanceModeMapsToExpectedColorSchemes() {
        XCTAssertNil(AppearanceMode.system.preferredColorScheme)
        XCTAssertEqual(AppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testAppearanceModeFallsBackToSystemForUnknownStoredValue() {
        XCTAssertEqual(AppearanceMode.mode(for: "unexpected"), .system)
        XCTAssertEqual(AppearanceMode.mode(for: AppearanceMode.dark.rawValue), .dark)
    }
}
