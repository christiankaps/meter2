import AppKit
import Foundation
import SwiftUI

struct AppReleaseVersion: Comparable, CustomStringConvertible, Equatable {
    let year: Int
    let major: Int
    let minor: Int

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let parts = normalized.split(separator: ".")

        guard parts.count == 2 || parts.count == 3,
              let year = Int(parts[0]),
              let major = Int(parts[1]) else {
            return nil
        }

        let minor: Int
        if parts.count == 3 {
            guard let parsedMinor = Int(parts[2]) else { return nil }
            minor = parsedMinor
        } else {
            minor = 0
        }

        self.year = year
        self.major = major
        self.minor = minor
    }

    var description: String {
        minor == 0 ? "\(year).\(major)" : "\(year).\(major).\(minor)"
    }

    static func < (lhs: AppReleaseVersion, rhs: AppReleaseVersion) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }
}

struct AppUpdateInfo: Equatable {
    let currentVersion: AppReleaseVersion
    let latestVersion: AppReleaseVersion
    let releasePageURL: URL
    let downloadURL: URL
    let assetName: String?
}

private final class UpdateDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Int64, Int64?) async -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64?) async -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        Task {
            await onProgress(totalBytesWritten, expectedBytes)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    enum Status: Equatable {
        case idle
        case checking
        case downloading(AppReleaseVersion)
        case installing(AppReleaseVersion)
        case upToDate(AppReleaseVersion)
        case updateAvailable(AppUpdateInfo)
        case failed(String)
    }

    struct UpdateProgress: Equatable {
        enum Phase: Equatable {
            case startingDownload
            case downloading(bytesReceived: Int64, totalBytes: Int64?)
            case mountingInstaller
            case stagingInstaller
            case verifyingInstaller
            case launchingInstaller
        }

        let version: AppReleaseVersion
        let phase: Phase

        var title: String {
            switch phase {
            case .startingDownload, .downloading:
                return String(format: String(localized: "update.progress.download.title %@"), version.description)
            case .mountingInstaller:
                return String(localized: "update.progress.mount.title")
            case .stagingInstaller:
                return String(localized: "update.progress.stage.title")
            case .verifyingInstaller:
                return String(localized: "update.progress.verify.title")
            case .launchingInstaller:
                return String(localized: "update.progress.launch.title")
            }
        }

        var detail: String {
            switch phase {
            case .startingDownload:
                return String(format: String(localized: "update.progress.download.start %@"), version.description)
            case .downloading(let bytesReceived, let totalBytes):
                if let totalBytes, totalBytes > 0 {
                    return String(
                        format: String(localized: "update.progress.download.bytes %@ %@"),
                        Self.byteCountString(bytesReceived),
                        Self.byteCountString(totalBytes)
                    )
                }
                if bytesReceived > 0 {
                    return String(
                        format: String(localized: "update.progress.download.received %@"),
                        Self.byteCountString(bytesReceived)
                    )
                }
                return String(format: String(localized: "update.progress.download.start %@"), version.description)
            case .mountingInstaller:
                return String(localized: "update.progress.mount.detail")
            case .stagingInstaller:
                return String(localized: "update.progress.stage.detail")
            case .verifyingInstaller:
                return String(localized: "update.progress.verify.detail")
            case .launchingInstaller:
                return String(localized: "update.progress.launch.detail")
            }
        }

        var fractionCompleted: Double? {
            guard case .downloading(let bytesReceived, let totalBytes) = phase,
                  let totalBytes,
                  totalBytes > 0 else {
                return nil
            }

            let fraction = Double(bytesReceived) / Double(totalBytes)
            return min(max(fraction, 0), 1)
        }

        var statusSummary: String {
            if let fractionCompleted {
                return "\(Int((fractionCompleted * 100).rounded()))%"
            }

            return "\(stepNumber)/\(totalSteps)"
        }

        private var stepNumber: Int {
            switch phase {
            case .startingDownload, .downloading:
                return 1
            case .mountingInstaller:
                return 2
            case .stagingInstaller:
                return 3
            case .verifyingInstaller:
                return 4
            case .launchingInstaller:
                return 5
            }
        }

        private var totalSteps: Int { 5 }

        private static let byteCountFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            formatter.includesUnit = true
            formatter.isAdaptive = true
            return formatter
        }()

        private static func byteCountString(_ byteCount: Int64) -> String {
            byteCountFormatter.string(fromByteCount: byteCount)
        }

        static func shouldAccept(_ incoming: Phase, over current: Phase?) -> Bool {
            guard let current else { return true }

            let incomingRank = phaseRank(for: incoming)
            let currentRank = phaseRank(for: current)
            guard incomingRank >= currentRank else { return false }

            if incomingRank > currentRank {
                return true
            }

            switch (current, incoming) {
            case (.downloading, .startingDownload):
                return false
            case let (.downloading(currentBytes, currentTotal), .downloading(incomingBytes, incomingTotal)):
                if incomingBytes > currentBytes {
                    return true
                }
                if incomingBytes == currentBytes, currentTotal == nil, incomingTotal != nil {
                    return true
                }
                return false
            default:
                return true
            }
        }

        private static func phaseRank(for phase: Phase) -> Int {
            switch phase {
            case .startingDownload, .downloading:
                return 0
            case .mountingInstaller:
                return 1
            case .stagingInstaller:
                return 2
            case .verifyingInstaller:
                return 3
            case .launchingInstaller:
                return 4
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var updateProgress: UpdateProgress?

    private let owner: String
    private let repo: String
    private var activeUpdateSessionID: UUID?
    private static let installerAssetRetryCount = 3
    private static let installerAssetRetryDelay: Duration = .seconds(2)

    init(owner: String = "christiankaps", repo: String = "meter2") {
        self.owner = owner
        self.repo = repo
    }

    func beginUpdateProgressSession(for version: AppReleaseVersion) -> UUID {
        let sessionID = UUID()
        activeUpdateSessionID = sessionID
        updateProgress = UpdateProgress(version: version, phase: .startingDownload)
        return sessionID
    }

    func clearUpdateProgressSession() {
        activeUpdateSessionID = nil
        updateProgress = nil
    }

    func applyUpdateProgress(
        _ phase: UpdateProgress.Phase,
        version: AppReleaseVersion,
        sessionID: UUID
    ) {
        guard activeUpdateSessionID == sessionID else { return }
        guard UpdateProgress.shouldAccept(phase, over: updateProgress?.phase) else { return }
        updateProgress = UpdateProgress(version: version, phase: phase)
    }

    func checkForUpdates(userInitiated: Bool = true) {
        guard !isBusy else { return }

        clearUpdateProgressSession()
        status = .checking

        Task {
            do {
                let info = try await fetchUpdateInfo()
                if let info {
                    clearUpdateProgressSession()
                    status = .updateAvailable(info)
                    if userInitiated {
                        presentUpdateAlert(info)
                    }
                } else if let currentVersion = currentInstalledVersion() {
                    clearUpdateProgressSession()
                    status = .upToDate(currentVersion)
                    if userInitiated {
                        presentInformationalAlert(
                            title: String(localized: "update.alert.upToDate.title"),
                            message: String(format: String(localized: "update.alert.upToDate.message %@"), currentVersion.description)
                        )
                    }
                } else {
                    clearUpdateProgressSession()
                    status = .idle
                    if userInitiated {
                        presentInformationalAlert(
                            title: String(localized: "update.alert.finished.title"),
                            message: String(localized: "update.alert.finished.message")
                        )
                    }
                }
            } catch {
                clearUpdateProgressSession()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .failed(message)
                if userInitiated {
                    presentInformationalAlert(
                        title: String(localized: "update.alert.failed.title"),
                        message: message
                    )
                }
            }
        }
    }

    func installUpdate(_ info: AppUpdateInfo) {
        guard !isBusy else { return }

        let sessionID = beginInstallProgressSession(for: info.latestVersion)

        Task {
            do {
                let preparedInstaller = try await Self.prepareInstaller(
                    for: info,
                    currentAppURL: Bundle.main.bundleURL.standardizedFileURL,
                    currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                    progressHandler: { [weak self] phase in
                        await self?.applyUpdateProgress(phase, version: info.latestVersion, sessionID: sessionID)
                    }
                )
                status = .installing(info.latestVersion)
                applyUpdateProgress(.launchingInstaller, version: info.latestVersion, sessionID: sessionID)
                try Self.launchInstaller(preparedInstaller)
                NSApplication.shared.terminate(nil)
            } catch {
                clearUpdateProgressSession()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .failed(message)
                presentInformationalAlert(
                    title: String(localized: "update.alert.installFailed.title"),
                    message: message
                )
            }
        }
    }

    @discardableResult
    func beginInstallProgressSession(for version: AppReleaseVersion) -> UUID {
        status = .downloading(version)
        return beginUpdateProgressSession(for: version)
    }

    private func fetchUpdateInfo() async throws -> AppUpdateInfo? {
        guard let currentVersion = currentInstalledVersion() else {
            throw UpdateError.invalidInstalledVersion
        }

        return try await fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: { try await self.fetchLatestRelease() },
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    func fetchUpdateInfo(
        currentVersion: AppReleaseVersion,
        releaseFetcher: () async throws -> GitHubReleaseResponse,
        sleep: (Duration) async throws -> Void
    ) async throws -> AppUpdateInfo? {
        var response = try await releaseFetcher()
        var resolvedRelease = try updateRelease(from: response, currentVersion: currentVersion)
        if resolvedRelease != nil && resolvedRelease?.dmgAsset == nil {
            for _ in 0..<Self.installerAssetRetryCount {
                try await sleep(Self.installerAssetRetryDelay)
                response = try await releaseFetcher()
                resolvedRelease = try updateRelease(from: response, currentVersion: currentVersion)
                if resolvedRelease?.dmgAsset != nil {
                    break
                }
            }
        }

        guard let resolvedRelease else {
            return nil
        }

        guard let dmgAsset = resolvedRelease.dmgAsset else {
            throw UpdateError.missingInstallerAsset
        }

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: resolvedRelease.latestVersion,
            releasePageURL: resolvedRelease.releasePageURL,
            downloadURL: URL(string: dmgAsset.browserDownloadURL) ?? resolvedRelease.releasePageURL,
            assetName: dmgAsset.name
        )
    }

    private func updateRelease(
        from response: GitHubReleaseResponse,
        currentVersion: AppReleaseVersion
    ) throws -> (latestVersion: AppReleaseVersion, releasePageURL: URL, dmgAsset: GitHubReleaseResponse.Asset?)? {
        guard let latestVersion = AppReleaseVersion(string: response.tagName) else {
            throw UpdateError.invalidRemoteVersion(response.tagName)
        }

        guard latestVersion > currentVersion else {
            return nil
        }

        return (
            latestVersion,
            URL(string: response.htmlURL) ?? releaseWebURL,
            response.dmgInstallerAsset
        )
    }

    private func fetchLatestRelease() async throws -> GitHubReleaseResponse {
        let request = Self.makeLatestReleaseRequest(url: apiURL)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        } catch {
            throw UpdateError.invalidPayload
        }
    }

    nonisolated static func makeLatestReleaseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Meter2", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private func currentInstalledVersion() -> AppReleaseVersion? {
        let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return rawVersion.flatMap(AppReleaseVersion.init(string:))
    }

    private func presentUpdateAlert(_ info: AppUpdateInfo) {
        let alert = NSAlert()
        alert.messageText = String(localized: "update.alert.available.title")
        alert.informativeText = String(
            format: String(localized: "update.alert.available.message %@ %@"),
            info.currentVersion.description,
            info.latestVersion.description
        )
        alert.addButton(withTitle: String(localized: "update.install"))
        alert.addButton(withTitle: String(localized: "cancel"))
        alert.addButton(withTitle: String(localized: "update.releasePage"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            installUpdate(info)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(info.releasePageURL)
        default:
            break
        }
    }

    private func presentInformationalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "ok"))
        alert.runModal()
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing:
            return true
        case .idle, .upToDate, .updateAvailable, .failed:
            return false
        }
    }

    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    private var releaseWebURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
    }

    struct GitHubReleaseResponse: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        var dmgInstallerAsset: Asset? {
            assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        }
    }

    private struct PreparedInstaller {
        let scriptURL: URL
    }

    private struct ProcessExecutionError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private enum UpdateError: LocalizedError {
        case invalidInstalledVersion
        case invalidRemoteVersion(String)
        case invalidResponse
        case httpStatus(Int)
        case invalidPayload
        case missingInstallerAsset
        case downloadMoveFailed
        case mountFailed(String)
        case detachFailed(String)
        case mountedVolumeNotFound
        case appBundleNotFound
        case invalidInstallerBundle(String)
        case signatureValidationFailed(String)
        case installerLaunchFailed
        case installerScriptWriteFailed

        var errorDescription: String? {
            switch self {
            case .invalidInstalledVersion:
                return String(localized: "update.error.invalidInstalledVersion")
            case .invalidRemoteVersion(let version):
                return String(format: String(localized: "update.error.invalidRemoteVersion %@"), version)
            case .invalidResponse:
                return String(localized: "update.error.invalidResponse")
            case .httpStatus(let status):
                return String(format: String(localized: "update.error.httpStatus %d"), status)
            case .invalidPayload:
                return String(localized: "update.error.invalidPayload")
            case .missingInstallerAsset:
                return String(localized: "update.error.missingInstallerAsset")
            case .downloadMoveFailed:
                return String(localized: "update.error.downloadMoveFailed")
            case .mountFailed(let message):
                return String(format: String(localized: "update.error.mountFailed %@"), message)
            case .detachFailed(let message):
                return String(format: String(localized: "update.error.detachFailed %@"), message)
            case .mountedVolumeNotFound:
                return String(localized: "update.error.mountedVolumeNotFound")
            case .appBundleNotFound:
                return String(localized: "update.error.appBundleNotFound")
            case .invalidInstallerBundle(let message):
                return message
            case .signatureValidationFailed(let message):
                return String(format: String(localized: "update.error.signatureValidationFailed %@"), message)
            case .installerLaunchFailed:
                return String(localized: "update.error.installerLaunchFailed")
            case .installerScriptWriteFailed:
                return String(localized: "update.error.installerScriptWriteFailed")
            }
        }
    }

    nonisolated private static let diskImageDetachRetryDelay: TimeInterval = 0.2

    nonisolated private static func prepareInstaller(
        for info: AppUpdateInfo,
        currentAppURL: URL,
        currentProcessIdentifier: Int32,
        progressHandler: @escaping @Sendable (UpdateProgress.Phase) async -> Void
    ) async throws -> PreparedInstaller {
        let tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meter2Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)

        let installerFileName = info.assetName ?? "Meter2.dmg"
        let downloadedDMGURL = tempRootURL.appendingPathComponent(installerFileName)
        await progressHandler(.startingDownload)
        try await downloadInstaller(from: info.downloadURL, to: downloadedDMGURL, progressHandler: progressHandler)

        await progressHandler(.mountingInstaller)
        let mountedVolumeURL = try mountDiskImage(at: downloadedDMGURL)
        let stagedAppURL = tempRootURL.appendingPathComponent(currentAppURL.lastPathComponent, isDirectory: true)
        let expectedBundleIdentifier = Bundle.main.bundleIdentifier ?? AppConfiguration.bundleIdentifier
        let expectedTeamIdentifier = currentTeamIdentifier(for: currentAppURL)

        do {
            let mountedAppURL = try locateAppBundle(in: mountedVolumeURL, named: currentAppURL.lastPathComponent)
            await progressHandler(.stagingInstaller)
            try FileManager.default.copyItem(at: mountedAppURL, to: stagedAppURL)
            await progressHandler(.verifyingInstaller)
            try validateInstalledApp(
                at: stagedAppURL,
                expectedAppName: currentAppURL.lastPathComponent,
                expectedBundleIdentifier: expectedBundleIdentifier,
                expectedTeamIdentifier: expectedTeamIdentifier
            )
        } catch {
            try? detachDiskImage(at: mountedVolumeURL)
            throw error
        }

        try? detachDiskImage(at: mountedVolumeURL)

        let scriptURL = tempRootURL.appendingPathComponent("install-update.sh")
        let script = installerScript(
            currentPID: currentProcessIdentifier,
            stagedAppURL: stagedAppURL,
            destinationAppURL: currentAppURL,
            temporaryRootURL: tempRootURL
        )

        guard FileManager.default.createFile(atPath: scriptURL.path, contents: script.data(using: .utf8)) else {
            throw UpdateError.installerScriptWriteFailed
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        return PreparedInstaller(scriptURL: scriptURL)
    }

    nonisolated private static func downloadInstaller(
        from sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (UpdateProgress.Phase) async -> Void
    ) async throws {
        var request = URLRequest(url: sourceURL)
        request.setValue("Meter2", forHTTPHeaderField: "User-Agent")
        let progressDelegate = UpdateDownloadProgressDelegate { bytesReceived, totalBytes in
            await progressHandler(.downloading(bytesReceived: bytesReceived, totalBytes: totalBytes))
        }
        let (temporaryURL, _) = try await URLSession.shared.download(for: request, delegate: progressDelegate)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw UpdateError.downloadMoveFailed
        }
    }

    nonisolated private static func mountDiskImage(at diskImageURL: URL) throws -> URL {
        try mountDiskImage(at: diskImageURL, processRunner: runProcess)
    }

    nonisolated static func mountDiskImage(
        at diskImageURL: URL,
        processRunner: (_ executablePath: String, _ arguments: [String]) throws -> Data
    ) throws -> URL {
        let output: Data
        do {
            output = try processRunner(
                "/usr/bin/hdiutil",
                ["attach", "-plist", "-nobrowse", "-noautoopen", diskImageURL.path]
            )
        } catch {
            throw UpdateError.mountFailed(
                processFailureMessage(from: error, defaultMessage: String(localized: "update.error.noMountDetails"))
            )
        }

        do {
            return try mountedVolumeURL(fromAttachOutput: output)
        } catch {
            let message = String(data: output, encoding: .utf8) ?? String(localized: "update.error.noMountDetails")
            throw UpdateError.mountFailed(message)
        }
    }

    nonisolated private static func detachDiskImage(at mountedVolumeURL: URL) throws {
        try detachDiskImage(at: mountedVolumeURL, processRunner: runProcess, sleep: { Thread.sleep(forTimeInterval: $0) })
    }

    nonisolated static func detachDiskImage(
        at mountedVolumeURL: URL,
        processRunner: (_ executablePath: String, _ arguments: [String]) throws -> Data,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws {
        do {
            _ = try processRunner("/usr/bin/hdiutil", ["detach", mountedVolumeURL.path])
        } catch let initialError {
            guard shouldRetryDiskImageDetach(after: initialError) else {
                throw UpdateError.detachFailed(
                    processFailureMessage(
                        from: initialError,
                        defaultMessage: String(localized: "update.error.diskImageDetachDefault")
                    )
                )
            }

            sleep(diskImageDetachRetryDelay)

            do {
                _ = try processRunner("/usr/bin/hdiutil", ["detach", "-force", mountedVolumeURL.path])
            } catch let forcedError {
                throw UpdateError.detachFailed(
                    processFailureMessage(
                        from: forcedError,
                        fallback: processFailureMessage(
                            from: initialError,
                            defaultMessage: String(localized: "update.error.diskImageDetachDefault")
                        )
                    )
                )
            }
        }
    }

    nonisolated static func mountedVolumeURL(fromAttachOutput output: Data) throws -> URL {
        let propertyList = try PropertyListSerialization.propertyList(from: output, format: nil)
        guard let root = propertyList as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]] else {
            throw UpdateError.mountedVolumeNotFound
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }

        throw UpdateError.mountedVolumeNotFound
    }

    nonisolated private static func locateAppBundle(in mountedVolumeURL: URL, named expectedAppName: String) throws -> URL {
        let enumerator = FileManager.default.enumerator(
            at: mountedVolumeURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "app", item.lastPathComponent == expectedAppName {
                return item
            }
        }

        throw UpdateError.appBundleNotFound
    }

    nonisolated private static func validateInstalledApp(
        at appURL: URL,
        expectedAppName: String,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws {
        guard appURL.lastPathComponent == expectedAppName else {
            throw UpdateError.invalidInstallerBundle(
                String(format: String(localized: "update.error.wrongAppName %@ %@"), appURL.lastPathComponent, expectedAppName)
            )
        }

        guard let bundle = Bundle(url: appURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier == expectedBundleIdentifier else {
            throw UpdateError.invalidInstallerBundle(String(localized: "update.error.unexpectedBundle"))
        }

        try verifyCodeSignature(
            of: appURL,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
    }

    nonisolated private static func currentTeamIdentifier(for appURL: URL) -> String? {
        try? codesignMetadata(for: appURL).teamIdentifier
    }

    nonisolated private static func verifyCodeSignature(
        of appURL: URL,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?
    ) throws {
        try verifyCodeSignature(
            of: appURL,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier,
            processRunner: runProcess,
            metadataProvider: codesignMetadata
        )
    }

    nonisolated static func verifyCodeSignature(
        of appURL: URL,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String?,
        processRunner: (_ executablePath: String, _ arguments: [String]) throws -> Data,
        metadataProvider: (_ appURL: URL) throws -> (identifier: String?, teamIdentifier: String?)
    ) throws {
        do {
            _ = try processRunner("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        } catch {
            throw UpdateError.signatureValidationFailed(
                processFailureMessage(from: error, defaultMessage: String(localized: "update.error.signatureDefault"))
            )
        }

        let metadata = try metadataProvider(appURL)
        if let signingIdentifier = metadata.identifier,
           signingIdentifier != expectedBundleIdentifier {
            throw UpdateError.signatureValidationFailed(
                String(format: String(localized: "update.error.signingIdentifierMismatch %@ %@"), expectedBundleIdentifier, signingIdentifier)
            )
        }

        if let expectedTeamIdentifier,
           let actualTeamIdentifier = metadata.teamIdentifier,
           actualTeamIdentifier != expectedTeamIdentifier {
            throw UpdateError.signatureValidationFailed(
                String(format: String(localized: "update.error.teamIdentifierMismatch %@ %@"), expectedTeamIdentifier, actualTeamIdentifier)
            )
        }
    }

    nonisolated private static func codesignMetadata(for appURL: URL) throws -> (identifier: String?, teamIdentifier: String?) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--verbose=4", appURL.path]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? String(localized: "update.error.signatureInspectDefault")
            throw UpdateError.signatureValidationFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let diagnostics = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return (
            identifier: codesignField(named: "Identifier", in: diagnostics),
            teamIdentifier: codesignField(named: "TeamIdentifier", in: diagnostics)
        )
    }

    nonisolated private static func codesignField(named name: String, in diagnostics: String) -> String? {
        for line in diagnostics.split(whereSeparator: \.isNewline) {
            let prefix = "\(name)="
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    nonisolated private static func processFailureMessage(from error: Error) -> String? {
        let message: String
        if let processError = error as? ProcessExecutionError {
            message = processError.message
        } else if let localizedDescription = (error as? LocalizedError)?.errorDescription {
            message = localizedDescription
        } else {
            message = error.localizedDescription
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func processFailureMessage(from error: Error, defaultMessage: String) -> String {
        processFailureMessage(from: error) ?? defaultMessage
    }

    nonisolated private static func processFailureMessage(from error: Error, fallback: String) -> String {
        processFailureMessage(from: error) ?? fallback
    }

    nonisolated private static func shouldRetryDiskImageDetach(after error: Error) -> Bool {
        guard let message = processFailureMessage(from: error)?.lowercased() else {
            return false
        }

        return message.contains("resource busy")
            || message.contains("couldn't unmount")
            || message.contains("couldnt unmount")
    }

    nonisolated private static func launchInstaller(_ preparedInstaller: PreparedInstaller) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [preparedInstaller.scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw UpdateError.installerLaunchFailed
        }
    }

    nonisolated private static func runProcess(executablePath: String, arguments: [String]) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData.isEmpty ? outputData : errorData, encoding: .utf8) ?? executablePath
            throw ProcessExecutionError(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return outputData
    }

    nonisolated static func installerScript(
        currentPID: Int32,
        stagedAppURL: URL,
        destinationAppURL: URL,
        temporaryRootURL: URL
    ) -> String {
        let stagedPath = shellQuoted(stagedAppURL.path)
        let destinationPath = shellQuoted(destinationAppURL.path)
        let temporaryRootPath = shellQuoted(temporaryRootURL.path)
        let replaceFunction = replaceFunctionScript()
        let privilegedCommand = """
        set -eu
        STAGED_APP=\(stagedPath)
        DESTINATION_APP=\(destinationPath)
        \(replaceFunction)
        install_update
        """

        let privilegedAppleScript = appleScriptQuoted(privilegedCommand)

        return """
        #!/bin/sh
        set -eu

        CURRENT_PID=\(currentPID)
        STAGED_APP=\(stagedPath)
        DESTINATION_APP=\(destinationPath)
        TEMP_ROOT=\(temporaryRootPath)

        \(replaceFunction)

        wait_for_app_exit() {
          ATTEMPTS=0
          while /bin/kill -0 "$CURRENT_PID" 2>/dev/null; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if [ "$ATTEMPTS" -gt 120 ]; then
              break
            fi
            /bin/sleep 1
          done
        }

        wait_for_app_exit

        if ! install_update; then
          /usr/bin/osascript -e "do shell script \(privilegedAppleScript) with administrator privileges"
        fi

        if [ ! -d "$DESTINATION_APP" ]; then
          exit 1
        fi

        /usr/bin/open "$DESTINATION_APP"
        /bin/rm -rf "$TEMP_ROOT"
        """
    }

    nonisolated private static func replaceFunctionScript() -> String {
        """
        install_update() {
          /bin/rm -rf "$DESTINATION_APP.new"
          /usr/bin/ditto "$STAGED_APP" "$DESTINATION_APP.new"
          /bin/rm -rf "$DESTINATION_APP.previous"
          if [ -e "$DESTINATION_APP" ]; then
            /bin/mv "$DESTINATION_APP" "$DESTINATION_APP.previous"
          fi
          if /bin/mv "$DESTINATION_APP.new" "$DESTINATION_APP"; then
            /bin/rm -rf "$DESTINATION_APP.previous"
            return 0
          fi
          /bin/rm -rf "$DESTINATION_APP"
          if [ -e "$DESTINATION_APP.previous" ]; then
            /bin/mv "$DESTINATION_APP.previous" "$DESTINATION_APP"
          fi
          return 1
        }
        """
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    nonisolated private static func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

@MainActor
final class Meter2AboutWindowController: NSWindowController {
    static let shared = Meter2AboutWindowController()

    private init() {
        let controller = NSHostingController(rootView: Meter2AboutView())
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "about.title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct Meter2AboutView: View {
    private let releaseVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"

    @StateObject private var updateService = AppUpdateService.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 6) {
                Text(AppConfiguration.appName)
                    .font(.system(size: 24, weight: .semibold))

                Text(String(format: String(localized: "about.versionBuild %@ %@"), releaseVersion, buildNumber))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(String(localized: "update.check")) {
                updateService.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .disabled(updateService.isBusy)

            if let progress = updateService.updateProgress {
                updateProgressCard(progress)
            }

            if let message = updateStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aboutCard {
                VStack(spacing: 4) {
                    Text(String(localized: "about.developedBy"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("Christian Kaps")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }

            Text(String(localized: "about.copyright"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private func updateProgressCard(_ progress: AppUpdateService.UpdateProgress) -> some View {
        aboutCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    if progress.fractionCompleted == nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.title)
                            .font(.caption.weight(.semibold))

                        Text(progress.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(progress.statusSummary)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let fractionCompleted = progress.fractionCompleted {
                    ProgressView(value: fractionCompleted)
                        .progressViewStyle(.linear)
                }
            }
        }
        .transition(.opacity)
    }

    private var updateStatusMessage: String? {
        switch updateService.status {
        case .idle:
            return nil
        case .checking:
            return String(localized: "update.status.checking")
        case .downloading(let version):
            return updateService.updateProgress == nil
                ? String(format: String(localized: "update.status.downloading %@"), version.description)
                : nil
        case .installing(let version):
            return updateService.updateProgress == nil
                ? String(format: String(localized: "update.status.installing %@"), version.description)
                : nil
        case .upToDate(let version):
            return String(format: String(localized: "update.status.upToDate %@"), version.description)
        case .updateAvailable(let info):
            return String(format: String(localized: "update.status.available %@"), info.latestVersion.description)
        case .failed(let message):
            return message
        }
    }
}
