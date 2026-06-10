import AppKit
import XCTest

@testable import Meter2

final class AppUpdateTests: XCTestCase {
    func testReleaseVersionParsesMajorAndMinorOnly() {
        let version = AppReleaseVersion(string: "2026.1")

        XCTAssertEqual(version?.year, 2026)
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 0)
        XCTAssertEqual(version?.description, "2026.1")
    }

    func testReleaseVersionParsesMinorReleaseVariant() {
        let version = AppReleaseVersion(string: "2026.0.3")

        XCTAssertEqual(version?.year, 2026)
        XCTAssertEqual(version?.major, 0)
        XCTAssertEqual(version?.minor, 3)
        XCTAssertEqual(version?.description, "2026.0.3")
    }

    func testReleaseVersionIgnoresLeadingVPrefixAndRejectsInvalidInput() {
        XCTAssertEqual(
            AppReleaseVersion(string: "v2026.1.2"),
            AppReleaseVersion(string: "2026.1.2")
        )
        XCTAssertNil(AppReleaseVersion(string: "2026"))
        XCTAssertNil(AppReleaseVersion(string: "2026.one.2"))
    }

    func testReleaseVersionComparisonTreatsMinorAsNewerThanBaseRelease() {
        let base = AppReleaseVersion(string: "2026.1")
        let patch = AppReleaseVersion(string: "2026.1.2")
        let nextMajor = AppReleaseVersion(string: "2026.2")

        XCTAssertNotNil(base)
        XCTAssertNotNil(patch)
        XCTAssertNotNil(nextMajor)
        XCTAssertLessThan(base!, patch!)
        XCTAssertLessThan(patch!, nextMajor!)
    }

    func testAppUpdateLatestReleaseRequestBypassesCachedReleasePayloads() throws {
        let url = try XCTUnwrap(URL(string: "https://api.github.com/repos/christiankaps/meter2/releases/latest"))

        let request = AppUpdateService.makeLatestReleaseRequest(url: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Meter2")
    }

    @MainActor
    func testAppUpdateRetriesWhenNewerReleaseInitiallyMissingInstallerAsset() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.0.2"))
        let releaseWithoutDMG = AppUpdateService.GitHubReleaseResponse(
            tagName: "2026.0.3",
            htmlURL: "https://github.com/christiankaps/meter2/releases/tag/stale-without-dmg",
            assets: []
        )
        let releaseWithDMG = AppUpdateService.GitHubReleaseResponse(
            tagName: "2026.0.3",
            htmlURL: "https://github.com/christiankaps/meter2/releases/tag/fresh-with-dmg",
            assets: [
                .init(
                    name: "Meter2_2026.0.3_43.dmg",
                    browserDownloadURL: "https://github.com/christiankaps/meter2/releases/download/2026.0.3/Meter2_2026.0.3_43.dmg"
                )
            ]
        )
        var responses = [releaseWithoutDMG, releaseWithDMG]
        var fetchCount = 0
        var sleepCount = 0

        let info = try await service.fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: {
                fetchCount += 1
                return responses.removeFirst()
            },
            sleep: { _ in
                sleepCount += 1
            }
        )

        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(sleepCount, 1)
        XCTAssertEqual(info?.latestVersion, AppReleaseVersion(string: "2026.0.3"))
        XCTAssertEqual(info?.assetName, "Meter2_2026.0.3_43.dmg")
        XCTAssertEqual(info?.releasePageURL.absoluteString, "https://github.com/christiankaps/meter2/releases/tag/fresh-with-dmg")
        XCTAssertEqual(
            info?.downloadURL.absoluteString,
            "https://github.com/christiankaps/meter2/releases/download/2026.0.3/Meter2_2026.0.3_43.dmg"
        )
    }

    @MainActor
    func testAppUpdateDoesNotRetryWhenLatestReleaseIsNotNewer() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.0.3"))
        var fetchCount = 0
        var sleepCount = 0

        let info = try await service.fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: {
                fetchCount += 1
                return AppUpdateService.GitHubReleaseResponse(
                    tagName: "2026.0.3",
                    htmlURL: "https://github.com/christiankaps/meter2/releases/tag/2026.0.3",
                    assets: []
                )
            },
            sleep: { _ in
                sleepCount += 1
            }
        )

        XCTAssertNil(info)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    @MainActor
    func testAppUpdateReportsMissingInstallerAfterRetries() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.0.2"))
        var fetchCount = 0
        var sleepCount = 0

        do {
            _ = try await service.fetchUpdateInfo(
                currentVersion: currentVersion,
                releaseFetcher: {
                    fetchCount += 1
                    return AppUpdateService.GitHubReleaseResponse(
                        tagName: "2026.0.3",
                        htmlURL: "https://github.com/christiankaps/meter2/releases/tag/2026.0.3",
                        assets: []
                    )
                },
                sleep: { _ in
                    sleepCount += 1
                }
            )
            XCTFail("Expected a missing installer error.")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("DMG") || message.contains("Installer"))
        }

        XCTAssertEqual(fetchCount, 4)
        XCTAssertEqual(sleepCount, 3)
    }

    @MainActor
    func testAppUpdateMountedVolumeURLParsesHdiutilPlist() throws {
        let propertyList: [String: Any] = [
            "system-entities": [
                ["dev-entry": "/dev/disk4"],
                ["mount-point": "/Volumes/Meter2", "volume-kind": "hfs"]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)

        let mountedURL = try AppUpdateService.mountedVolumeURL(fromAttachOutput: data)

        XCTAssertEqual(mountedURL.path, "/Volumes/Meter2")
    }

    @MainActor
    func testAppUpdateProgressFormatsDownloadFraction() {
        let progress = AppUpdateService.UpdateProgress(
            version: AppReleaseVersion(string: "2026.0.3")!,
            phase: .downloading(bytesReceived: 1_024, totalBytes: 2_048)
        )

        XCTAssertTrue(progress.title.contains("2026.0.3"))
        XCTAssertEqual(progress.statusSummary, "50%")
        XCTAssertEqual(progress.fractionCompleted ?? -1, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testAppUpdateProgressRejectsRegressiveUpdates() {
        XCTAssertFalse(
            AppUpdateService.UpdateProgress.shouldAccept(
                .downloading(bytesReceived: 2_048, totalBytes: 4_096),
                over: .mountingInstaller
            )
        )
        XCTAssertFalse(
            AppUpdateService.UpdateProgress.shouldAccept(
                .startingDownload,
                over: .downloading(bytesReceived: 2_048, totalBytes: 4_096)
            )
        )
    }

    @MainActor
    func testAppUpdateProgressSessionIgnoresUpdatesFromOlderSession() {
        let service = AppUpdateService()
        let oldVersion = AppReleaseVersion(string: "2026.0.3")!
        let newVersion = AppReleaseVersion(string: "2026.1")!
        let oldSessionID = service.beginUpdateProgressSession(for: oldVersion)
        _ = service.beginUpdateProgressSession(for: newVersion)

        service.applyUpdateProgress(.downloading(bytesReceived: 1_024, totalBytes: 2_048), version: oldVersion, sessionID: oldSessionID)

        XCTAssertEqual(service.updateProgress?.version, newVersion)
        XCTAssertEqual(service.updateProgress?.phase, .startingDownload)
        service.clearUpdateProgressSession()
    }

    @MainActor
    func testAppUpdateMountDiskImageReportsAttachFailure() {
        XCTAssertThrowsError(
            try AppUpdateService.mountDiskImage(
                at: URL(fileURLWithPath: "/tmp/Meter2.dmg"),
                processRunner: { _, _ in
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: attach failed"]
                    )
                }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("hdiutil: attach failed"))
        }
    }

    @MainActor
    func testAppUpdateDetachDiskImageRetriesWithForceWhenVolumeIsBusy() throws {
        var recordedArguments: [[String]] = []

        try AppUpdateService.detachDiskImage(
            at: URL(fileURLWithPath: "/Volumes/Meter2", isDirectory: true),
            processRunner: { executablePath, arguments in
                XCTAssertEqual(executablePath, "/usr/bin/hdiutil")
                recordedArguments.append(arguments)

                if recordedArguments.count == 1 {
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 16,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: couldn't unmount disk23"]
                    )
                }

                return Data()
            },
            sleep: { _ in }
        )

        XCTAssertEqual(
            recordedArguments,
            [
                ["detach", "/Volumes/Meter2"],
                ["detach", "-force", "/Volumes/Meter2"]
            ]
        )
    }

    @MainActor
    func testAppUpdateDetachDiskImageDoesNotForceForNonBusyFailures() {
        var recordedArguments: [[String]] = []

        XCTAssertThrowsError(
            try AppUpdateService.detachDiskImage(
                at: URL(fileURLWithPath: "/Volumes/Meter2", isDirectory: true),
                processRunner: { _, arguments in
                    recordedArguments.append(arguments)
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: no such image"]
                    )
                },
                sleep: { _ in }
            )
        )

        XCTAssertEqual(recordedArguments, [["detach", "/Volumes/Meter2"]])
    }

    @MainActor
    func testAppUpdateVerifyCodeSignatureReportsVerificationFailure() {
        XCTAssertThrowsError(
            try AppUpdateService.verifyCodeSignature(
                of: URL(fileURLWithPath: "/tmp/Meter2.app", isDirectory: true),
                expectedBundleIdentifier: AppConfiguration.bundleIdentifier,
                expectedTeamIdentifier: nil,
                processRunner: { _, _ in
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "code object is not signed at all"]
                    )
                },
                metadataProvider: { _ in
                    XCTFail("Metadata should not be requested when signature verification fails.")
                    return (identifier: nil, teamIdentifier: nil)
                }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("code object is not signed at all"))
        }
    }

    func testReleaseWorkflowSignsAndVerifiesAppBeforeCreatingDMG() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let workflowURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("codesign --force --deep --sign - \"$APP_PATH\""))
        XCTAssertTrue(workflow.contains("codesign --verify --deep --strict \"$APP_PATH\""))

        let signingStep = try XCTUnwrap(workflow.range(of: "- name: Sign and verify app"))
        let dmgStep = try XCTUnwrap(workflow.range(of: "- name: Create DMG"))
        XCTAssertLessThan(signingStep.lowerBound, dmgStep.lowerBound)
    }

    @MainActor
    func testAppUpdateInstallerScriptContainsReplaceRelaunchAndRollbackSteps() {
        let script = AppUpdateService.installerScript(
            currentPID: 1234,
            stagedAppURL: URL(fileURLWithPath: "/tmp/Meter2Update/Meter2.app"),
            destinationAppURL: URL(fileURLWithPath: "/Applications/Meter2.app"),
            temporaryRootURL: URL(fileURLWithPath: "/tmp/Meter2Update")
        )

        XCTAssertTrue(script.contains("CURRENT_PID=1234"))
        XCTAssertTrue(script.contains("/usr/bin/ditto"))
        XCTAssertTrue(script.contains("/usr/bin/osascript"))
        XCTAssertTrue(script.contains("/usr/bin/open \"$DESTINATION_APP\""))
        XCTAssertTrue(script.contains("/bin/rm -rf \"$TEMP_ROOT\""))
        XCTAssertTrue(script.contains("if /bin/mv \"$DESTINATION_APP.new\" \"$DESTINATION_APP\"; then"))
        XCTAssertTrue(script.contains("/bin/mv \"$DESTINATION_APP.previous\" \"$DESTINATION_APP\""))
    }

    @MainActor
    func testCustomAboutWindowIsConfiguredForMeter2() {
        Meter2AboutWindowController.shared.show()

        XCTAssertEqual(Meter2AboutWindowController.shared.window?.title, String(localized: "about.title"))
        Meter2AboutWindowController.shared.window?.close()
    }
}
