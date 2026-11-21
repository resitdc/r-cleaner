import Foundation
import CryptoKit
import AppKit

// MARK: - GitHub Release Update Models

public struct AppReleaseInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let tagName: String
    public let version: String
    public let title: String
    public let releaseNotes: String
    public let publishedAt: Date?
    public let htmlURL: URL
    public let zipAssetURL: URL?
    public let zipAssetName: String?
    public let zipAssetSizeBytes: Int64
    public let dmgAssetURL: URL?
    public let dmgAssetName: String?
    public let dmgAssetSizeBytes: Int64
    public let checksumsURL: URL?

    public var preferredDownloadURL: URL? { zipAssetURL ?? dmgAssetURL }
    public var preferredAssetName: String? { zipAssetName ?? dmgAssetName }
    public var preferredAssetSizeBytes: Int64 {
        zipAssetURL != nil ? zipAssetSizeBytes : dmgAssetSizeBytes
    }
    public var supportsInPlaceInstall: Bool { zipAssetURL != nil }
}

public enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(latestVersion: String)
    case updateAvailable(AppReleaseInfo)
    case downloading(release: AppReleaseInfo, progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying(release: AppReleaseInfo)
    case installing(release: AppReleaseInfo)
    case readyToReveal(release: AppReleaseInfo, fileURL: URL, note: String)
    case failed(message: String)
}

// MARK: - Automatic GitHub Releases Updater Service

public final class AppUpdaterService: @unchecked Sendable {
    public static let repoOwner = "resitdc"
    public static let repoName = "resitdc-mac-cleaner"
    public static let releasesPageURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    public static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    public init() {}

    /// Current running application marketing version from Info.plist (falls back cleanly in `swift run`).
    public static var currentAppVersion: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !v.isEmpty {
            return normalizeVersion(v)
        }
        return "1.0.0"
    }

    public static var currentBuildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "100"
    }

    /// Strips leading `v`/`V` and surrounding whitespace.
    public static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        return s
    }

    /// Pure semantic version comparison (`remote > local`).
    /// Handles `1.2.0 > 1.1.9`, `v1.2.0 > 1.0`, and stable > prerelease (`1.2.0 > 1.2.0-beta.1`).
    public static func isVersion(_ remoteRaw: String, newerThan localRaw: String) -> Bool {
        let remote = normalizeVersion(remoteRaw)
        let local = normalizeVersion(localRaw)
        if remote.isEmpty || local.isEmpty || remote == local { return false }

        let (rCore, rPre) = splitPrerelease(remote)
        let (lCore, lPre) = splitPrerelease(local)

        let rParts = rCore.split(separator: ".").map { Int($0) ?? 0 }
        let lParts = lCore.split(separator: ".").map { Int($0) ?? 0 }
        let maxLen = max(rParts.count, lParts.count)

        for i in 0..<maxLen {
            let rv = i < rParts.count ? rParts[i] : 0
            let lv = i < lParts.count ? lParts[i] : 0
            if rv != lv {
                return rv > lv
            }
        }

        // Same numeric core: stable release beats pre-release
        switch (rPre, lPre) {
        case (nil, nil): return false
        case (nil, .some): return true
        case (.some, nil): return false
        case (.some(let rp), .some(let lp)):
            return rp.localizedStandardCompare(lp) == .orderedDescending
        }
    }

    private static func splitPrerelease(_ v: String) -> (core: String, prerelease: String?) {
        let noMeta = v.split(separator: "+", maxSplits: 1).first.map(String.init) ?? v
        let parts = noMeta.split(separator: "-", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return (noMeta, nil)
    }

    /// Parses standard `shasum -a 256` output (`<64-hex-hash>  <filename>`) into `[filename: lowercaseHex]`.
    public static func parseSHA256Sums(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2 else { continue }
            let hash = String(tokens[0]).lowercased()
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var name = String(tokens[1])
            if name.hasPrefix("*") { name.removeFirst() }
            let basename = URL(fileURLWithPath: name).lastPathComponent
            map[basename] = hash
        }
        return map
    }

    // MARK: - Check GitHub Releases API

    public enum UpdateCheckOutcome: Sendable {
        case updateAvailable(AppReleaseInfo)
        case upToDate(latestVersion: String)
        case noReleasesPublished
    }

    public func checkLatestRelease(currentVersion: String = AppUpdaterService.currentAppVersion) async throws -> UpdateCheckOutcome {
        var req = URLRequest(url: Self.latestReleaseAPIURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("R-Cleaner/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw UpdaterError.network("Invalid response from GitHub Releases.")
        }

        if http.statusCode == 404 {
            return .noReleasesPublished
        }
        if http.statusCode == 403 {
            throw UpdaterError.network("GitHub API rate limit reached. Please try again in a few minutes.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdaterError.network("GitHub Releases returned HTTP \(http.statusCode).")
        }

        let release = try parseReleaseJSON(data)
        if Self.isVersion(release.version, newerThan: currentVersion) {
            return .updateAvailable(release)
        } else {
            return .upToDate(latestVersion: release.version)
        }
    }

    public func parseReleaseJSON(_ data: Data) throws -> AppReleaseInfo {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = obj["tag_name"] as? String else {
            throw UpdaterError.invalidPayload("Could not parse release metadata from GitHub.")
        }

        let version = Self.normalizeVersion(tagName)
        let title = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (obj["body"] as? String) ?? ""
        let htmlStr = (obj["html_url"] as? String) ?? Self.releasesPageURL.absoluteString
        let htmlURL = URL(string: htmlStr) ?? Self.releasesPageURL

        let iso = ISO8601DateFormatter()
        let publishedAt = (obj["published_at"] as? String).flatMap { iso.date(from: $0) }

        var zipURL: URL?
        var zipName: String?
        var zipSize: Int64 = 0
        var dmgURL: URL?
        var dmgName: String?
        var dmgSize: Int64 = 0
        var checksumsURL: URL?

        if let assets = obj["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let dlStr = asset["browser_download_url"] as? String,
                      let dlURL = URL(string: dlStr) else { continue }
                let size = (asset["size"] as? Int64) ?? Int64((asset["size"] as? NSNumber)?.int64Value ?? 0)
                let lower = name.lowercased()

                if lower.hasSuffix(".app.zip") || (lower.hasSuffix(".zip") && zipURL == nil) {
                    // Prefer universal archive over arch-specific if multiple exist
                    if zipURL == nil || lower.contains("universal") {
                        zipURL = dlURL
                        zipName = name
                        zipSize = size
                    }
                } else if lower.hasSuffix(".dmg") {
                    if dmgURL == nil || lower.contains("universal") {
                        dmgURL = dlURL
                        dmgName = name
                        dmgSize = size
                    }
                } else if lower == "sha256sums.txt" || lower.contains("sha256") {
                    checksumsURL = dlURL
                }
            }
        }

        return AppReleaseInfo(
            id: tagName,
            tagName: tagName,
            version: version,
            title: (title?.isEmpty == false ? title! : "R-Cleaner \(tagName)"),
            releaseNotes: body,
            publishedAt: publishedAt,
            htmlURL: htmlURL,
            zipAssetURL: zipURL,
            zipAssetName: zipName,
            zipAssetSizeBytes: zipSize,
            dmgAssetURL: dmgURL,
            dmgAssetName: dmgName,
            dmgAssetSizeBytes: dmgSize,
            checksumsURL: checksumsURL
        )
    }

    // MARK: - Download, Verify SHA-256 & Install

    public enum InstallOutcome: Sendable {
        case launchedRelaunchScript
        case revealInFinder(fileURL: URL, note: String)
    }

    public func downloadVerifyAndInstall(
        release: AppReleaseInfo,
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onVerifying: @escaping @Sendable () -> Void,
        onInstalling: @escaping @Sendable () -> Void
    ) async throws -> InstallOutcome {
        guard let downloadURL = release.preferredDownloadURL,
              let assetName = release.preferredAssetName else {
            throw UpdaterError.missingAsset("No macOS .app.zip or .dmg installer found in release \(release.tagName).")
        }

        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("rcleaner-update-\(release.version)-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let downloadedFile = stagingDir.appendingPathComponent(assetName)

        // 1. Stream download with real-time progress
        var req = URLRequest(url: downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        req.setValue("R-Cleaner/\(Self.currentAppVersion)", forHTTPHeaderField: "User-Agent")

        let (bytesStream, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdaterError.network("Failed to download \(assetName) from GitHub Releases.")
        }

        let expectedTotal = max(response.expectedContentLength, release.preferredAssetSizeBytes)
        fm.createFile(atPath: downloadedFile.path, contents: nil)
        let fh = try FileHandle(forWritingTo: downloadedFile)

        var downloaded: Int64 = 0
        var chunk = Data()
        chunk.reserveCapacity(128 * 1024)
        var lastReport = CFAbsoluteTimeGetCurrent()

        do {
            for try await byte in bytesStream {
                if Task.isCancelled {
                    try? fh.close()
                    try? fm.removeItem(at: stagingDir)
                    throw CancellationError()
                }
                chunk.append(byte)
                if chunk.count >= 64 * 1024 {
                    try fh.write(contentsOf: chunk)
                    downloaded += Int64(chunk.count)
                    chunk.removeAll(keepingCapacity: true)
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastReport >= 0.08 {
                        lastReport = now
                        let pct = expectedTotal > 0 ? min(0.99, Double(downloaded) / Double(expectedTotal)) : 0.5
                        onProgress(pct, downloaded, expectedTotal)
                    }
                }
            }
            if !chunk.isEmpty {
                try fh.write(contentsOf: chunk)
                downloaded += Int64(chunk.count)
            }
            try fh.close()
        } catch {
            try? fh.close()
            try? fm.removeItem(at: stagingDir)
            throw error
        }
        onProgress(1.0, downloaded, max(expectedTotal, downloaded))

        // 2. Cryptographic SHA-256 verification against SHA256SUMS.txt (when published)
        onVerifying()
        if let checksumsURL = release.checksumsURL {
            var sumReq = URLRequest(url: checksumsURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            sumReq.setValue("R-Cleaner/\(Self.currentAppVersion)", forHTTPHeaderField: "User-Agent")
            if let (sumData, sumResp) = try? await URLSession.shared.data(for: sumReq),
               let sumHTTP = sumResp as? HTTPURLResponse,
               (200...299).contains(sumHTTP.statusCode),
               let sumText = String(data: sumData, encoding: .utf8) {
                let expectedMap = Self.parseSHA256Sums(sumText)
                if let expectedHash = expectedMap[assetName] {
                    let actualHash = try Self.sha256Hex(ofFileAt: downloadedFile)
                    guard actualHash == expectedHash else {
                        try? fm.removeItem(at: stagingDir)
                        throw UpdaterError.checksumMismatch("SHA-256 verification failed for \(assetName). Download aborted for your security.")
                    }
                }
            }
        }

        // 3. Extract & Install
        onInstalling()
        if assetName.lowercased().hasSuffix(".dmg") {
            NSWorkspace.shared.open(downloadedFile)
            return .revealInFinder(
                fileURL: downloadedFile,
                note: "Verified installer DMG opened. Drag R-Cleaner into Applications to complete the update."
            )
        }

        let extractDir = stagingDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let ditto = FileSystemHelpers.runProcess("/usr/bin/ditto", arguments: ["-xk", downloadedFile.path, extractDir.path], timeout: 45)
        guard ditto.exitCode == 0 else {
            throw UpdaterError.installFailed("Could not unpack update archive: \(ditto.stderr)")
        }

        let stagedApp = extractDir.appendingPathComponent("R-Cleaner.app")
        let stagedBinary = stagedApp.appendingPathComponent("Contents/MacOS/R-Cleaner")
        guard fm.isExecutableFile(atPath: stagedBinary.path) else {
            throw UpdaterError.installFailed("Extracted update did not contain a valid R-Cleaner.app bundle.")
        }

        // Clear quarantine flag on freshly downloaded verified bundle
        _ = FileSystemHelpers.runProcess("/usr/bin/xattr", arguments: ["-cr", stagedApp.path], timeout: 10)

        // Check if we're running from a real, writable .app bundle we can swap atomically
        let currentBundleURL = Bundle.main.bundleURL
        let isRunningAppBundle = currentBundleURL.pathExtension == "app"
            && !currentBundleURL.path.hasPrefix("/Volumes/")
            && fm.isWritableFile(atPath: currentBundleURL.deletingLastPathComponent().path)

        guard isRunningAppBundle else {
            NSWorkspace.shared.activateFileViewerSelecting([stagedApp])
            return .revealInFinder(
                fileURL: stagedApp,
                note: "Verified R-Cleaner \(release.tagName) is ready. Move it into Applications to finish installing."
            )
        }

        try launchAtomicSwapAndRelaunch(
            stagedAppPath: stagedApp.path,
            destinationAppPath: currentBundleURL.path,
            stagingRootPath: stagingDir.path
        )
        return .launchedRelaunchScript
    }

    /// Streams file in 256 KB chunks through CryptoKit SHA-256 (constant memory footprint).
    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let chunk = try fh.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Spawns a detached POSIX shell script that waits for the current PID to quit, atomically
    /// swaps the `.app` bundle (with automatic rollback on failure), and relaunches the new version.
    private func launchAtomicSwapAndRelaunch(
        stagedAppPath: String,
        destinationAppPath: String,
        stagingRootPath: String
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let backupPath = "\(stagingRootPath)/R-Cleaner-backup.app"

        let script = """
        #!/bin/sh
        PID="$1"
        STAGED="$2"
        DEST="$3"
        BACKUP="$4"
        STAGING_ROOT="$5"

        # Wait up to 12 seconds for the old app process to exit cleanly
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 60 ]; do
            sleep 0.2
            i=$((i + 1))
        done

        # Atomic swap with rollback protection
        if [ -d "$DEST" ]; then
            mv "$DEST" "$BACKUP" || exit 1
        fi
        if mv "$STAGED" "$DEST"; then
            rm -rf "$BACKUP"
            /usr/bin/xattr -cr "$DEST" 2>/dev/null || true
            /usr/bin/open -n "$DEST"
        else
            # Restore previous bundle if move failed
            if [ -d "$BACKUP" ]; then
                mv "$BACKUP" "$DEST"
            fi
            exit 1
        fi
        rm -rf "$STAGING_ROOT"
        """

        let scriptURL = URL(fileURLWithPath: stagingRootPath).appendingPathComponent("apply_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [scriptURL.path, "\(pid)", stagedAppPath, destinationAppPath, backupPath, stagingRootPath]
        proc.standardInput = nil
        proc.standardOutput = nil
        proc.standardError = nil
        try proc.run()
    }

    public enum UpdaterError: LocalizedError {
        case network(String)
        case invalidPayload(String)
        case missingAsset(String)
        case checksumMismatch(String)
        case installFailed(String)

        public var errorDescription: String? {
            switch self {
            case .network(let m), .invalidPayload(let m), .missingAsset(let m), .checksumMismatch(let m), .installFailed(let m):
                return m
            }
        }
    }
}
