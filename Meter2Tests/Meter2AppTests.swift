import AppKit
import XCTest

@testable import Meter2

final class Meter2AppTests: XCTestCase {
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

    func testAppearanceModeMapsToExpectedColorSchemes() {
        XCTAssertNil(AppearanceMode.system.preferredColorScheme)
        XCTAssertEqual(AppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testAppearanceModeFallsBackToSystemForUnknownStoredValue() {
        XCTAssertEqual(AppearanceMode.mode(for: "unexpected"), .system)
        XCTAssertEqual(AppearanceMode.mode(for: AppearanceMode.dark.rawValue), .dark)
    }

    func testApplicationTerminatesAfterTheLastWindowCloses() {
        let delegate = Meter2ApplicationDelegate()

        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func testClosingTheOnlyMainWindowTerminatesEvenWhenAnAuxiliaryWindowRemains() {
        let mainWindow = NSWindow()
        mainWindow.identifier = Meter2ApplicationDelegate.mainWindowIdentifier

        XCTAssertTrue(
            Meter2ApplicationDelegate.shouldTerminateAfterClosingMainWindow(mainWindow)
        )
    }

    func testClosingAnAuxiliaryWindowDoesNotTerminate() {
        let auxiliaryWindow = NSWindow()

        XCTAssertFalse(
            Meter2ApplicationDelegate.shouldTerminateAfterClosingMainWindow(auxiliaryWindow)
        )
    }

    func testMainWindowMarkerAssignsTheLifecycleIdentifierToItsHostWindow() {
        let window = NSWindow()
        let markerView = Meter2MainWindowMarkerView()

        window.contentView = markerView

        XCTAssertEqual(window.identifier, Meter2ApplicationDelegate.mainWindowIdentifier)
    }

    func testWindowCloseObserverTerminatesOnlyForTheMarkedMainWindow() {
        var terminationCount = 0
        let notificationCenter = NotificationCenter()
        let delegate = Meter2ApplicationDelegate(terminateApplication: {
            terminationCount += 1
        }, notificationCenter: notificationCenter)
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let auxiliaryWindow = NSWindow()
        notificationCenter.post(
            name: NSWindow.willCloseNotification,
            object: auxiliaryWindow
        )
        XCTAssertEqual(terminationCount, 0)

        let mainWindow = NSWindow()
        mainWindow.identifier = Meter2ApplicationDelegate.mainWindowIdentifier
        notificationCenter.post(
            name: NSWindow.willCloseNotification,
            object: mainWindow
        )
        XCTAssertEqual(terminationCount, 1)
    }
}
