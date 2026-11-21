import Foundation
import AppKit

public struct ApplicationsScanResult {
    public var installedApps: [InstalledAppRecord] = []
    public var updates: [AppUpdateRecord] = []
    public var leftovers: [ScanItem] = []
    public var installers: [ScanItem] = []
}

public final class ApplicationsService {
    public init() {}

    public func scanAll(
        settings: RCleanerSettings,
        checkUpdatesOnline: Bool = false,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> ApplicationsScanResult {
        var result = ApplicationsScanResult()

        progress("Scanning installed applications...", 0.15)
        result.installedApps = scanInstalledApplications(settings: settings, progress: progress)

        progress("Looking for App Leftovers...", 0.62)
        result.leftovers = scanLeftovers(installedApps: result.installedApps, settings: settings)

        progress("Scanning Unused Installers (DMG & PKG)...", 0.80)
        result.installers = scanUnusedInstallers(settings: settings)

        if checkUpdatesOnline {
            progress("Checking for application & macOS updates...", 0.90)
            result.updates = await checkForUpdates(apps: result.installedApps)
        } else {
            // Fast local Sparkle / outdated check
            result.updates = detectPotentialUpdatesLocally(apps: result.installedApps)
        }

        progress("Applications scan complete", 1.0)
        return result
    }

    private func scanInstalledApplications(
        settings: RCleanerSettings,
        progress: @escaping @Sendable (String, Double) -> Void
    ) -> [InstalledAppRecord] {
        let fm = FileManager.default
        var appDirs = ["/Applications", FileSystemHelpers.expand("~/Applications")]
        if !settings.ignoreSystemApplications {
            appDirs.append("/System/Applications")
        }

        // Pre-index all 12 user library folders for related-file discovery
        let supportDir = FileSystemHelpers.expand("~/Library/Application Support")
        let cachesDir = FileSystemHelpers.expand("~/Library/Caches")
        let prefsDir = FileSystemHelpers.expand("~/Library/Preferences")
        let logsDir = FileSystemHelpers.expand("~/Library/Logs")
        let containersDir = FileSystemHelpers.expand("~/Library/Containers")
        let groupContainersDir = FileSystemHelpers.expand("~/Library/Group Containers")
        let savedStateDir = FileSystemHelpers.expand("~/Library/Saved Application State")
        let cookiesDir = FileSystemHelpers.expand("~/Library/Cookies")
        let httpStorageDir = FileSystemHelpers.expand("~/Library/HTTPStorages")
        let webKitDir = FileSystemHelpers.expand("~/Library/WebKit")
        let crashDir = FileSystemHelpers.expand("~/Library/Application Support/CrashReporter")
        let launchAgentsDir = FileSystemHelpers.expand("~/Library/LaunchAgents")

        let supportEntries = (try? fm.contentsOfDirectory(atPath: supportDir)) ?? []
        let cacheEntries = (try? fm.contentsOfDirectory(atPath: cachesDir)) ?? []
        let prefEntries = (try? fm.contentsOfDirectory(atPath: prefsDir)) ?? []
        let logEntries = (try? fm.contentsOfDirectory(atPath: logsDir)) ?? []
        let containerEntries = (try? fm.contentsOfDirectory(atPath: containersDir)) ?? []
        let groupContainerEntries = (try? fm.contentsOfDirectory(atPath: groupContainersDir)) ?? []
        let savedEntries = (try? fm.contentsOfDirectory(atPath: savedStateDir)) ?? []
        let cookieEntries = (try? fm.contentsOfDirectory(atPath: cookiesDir)) ?? []
        let httpEntries = (try? fm.contentsOfDirectory(atPath: httpStorageDir)) ?? []
        let webKitEntries = (try? fm.contentsOfDirectory(atPath: webKitDir)) ?? []
        let crashEntries = (try? fm.contentsOfDirectory(atPath: crashDir)) ?? []
        let launchEntries = (try? fm.contentsOfDirectory(atPath: launchAgentsDir)) ?? []

        var records: [InstalledAppRecord] = []
        var appURLs: [URL] = []

        for dir in appDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                appURLs.append(URL(fileURLWithPath: (dir as NSString).appendingPathComponent(item)))
            }
        }

        for (idx, url) in appURLs.enumerated() {
            if Task.isCancelled { break }
            let appPath = url.path
            if FileSystemHelpers.isIgnored(path: appPath, category: .uninstaller, settings: settings) { continue }
            if idx % 8 == 0 {
                progress("Inspecting \(url.lastPathComponent)...", 0.15 + (Double(idx) / Double(max(1, appURLs.count))) * 0.42)
            }

            let plistURL = url.appendingPathComponent("Contents/Info.plist")
            let plistData = try? Data(contentsOf: plistURL)
            let plist = plistData.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }

            let name = (plist?["CFBundleDisplayName"] as? String)
                ?? (plist?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let bundleID = (plist?["CFBundleIdentifier"] as? String) ?? "unknown.\(name.lowercased())"
            // Never list R-Cleaner itself in Uninstaller to prevent accidental self-uninstall
            if bundleID == "com.resitdc.r-cleaner" || bundleID == Bundle.main.bundleIdentifier { continue }
            let version = (plist?["CFBundleShortVersionString"] as? String)
                ?? (plist?["CFBundleVersion"] as? String)
                ?? "1.0"
            let sparkleURL = plist?["SUFeedURL"] as? String

            let isMAS = fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
            let isSystem = appPath.hasPrefix("/System")
            let store = classifyStore(path: appPath, bundleID: bundleID, isMAS: isMAS)
            let vendor = classifyVendor(bundleID: bundleID, name: name)

            let size = FileSystemHelpers.directorySize(at: url, maxFiles: 0)
            let vals = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
            let lastOpened = vals?.contentAccessDate ?? vals?.contentModificationDate

            // Find related files across all 12 macOS library locations
            let related = findRelatedFiles(
                appName: name,
                bundleID: bundleID,
                buckets: [
                    (supportDir, supportEntries, "Supporting Files"),
                    (cachesDir, cacheEntries, "Caches"),
                    (prefsDir, prefEntries, "Preferences"),
                    (logsDir, logEntries, "Logs"),
                    (containersDir, containerEntries, "Container"),
                    (groupContainersDir, groupContainerEntries, "Group Container"),
                    (savedStateDir, savedEntries, "Supporting Files"),
                    (cookiesDir, cookieEntries, "Cookies"),
                    (httpStorageDir, httpEntries, "HTTP Storage"),
                    (webKitDir, webKitEntries, "WebKit Data"),
                    (crashDir, crashEntries, "Crashes"),
                    (launchAgentsDir, launchEntries, "Login Items")
                ]
            )

            records.append(InstalledAppRecord(
                id: appPath,
                name: name,
                bundleID: bundleID,
                version: version,
                path: appPath,
                appSizeBytes: size,
                relatedFiles: related,
                lastOpenedDate: lastOpened,
                store: store,
                vendor: vendor,
                isSystemApp: isSystem,
                isAppStoreApp: isMAS,
                isSuspicious: bundleID.lowercased().contains("mackeeper") || bundleID.lowercased().contains("genieo"),
                is32BitOrUnsupported: false,
                isAudioPlugin: false,
                sparkleFeedURL: sparkleURL
            ))
        }

        // Also scan Audio Plugins (.component, .vst, .vst3)
        let audioDirs = [
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST",
            "/Library/Audio/Plug-Ins/VST3",
            FileSystemHelpers.expand("~/Library/Audio/Plug-Ins/Components")
        ]
        for dir in audioDirs {
            guard let plugins = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for p in plugins where p.hasSuffix(".component") || p.hasSuffix(".vst") || p.hasSuffix(".vst3") {
                let full = (dir as NSString).appendingPathComponent(p)
                let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                records.append(InstalledAppRecord(
                    id: full,
                    name: (p as NSString).deletingPathExtension,
                    bundleID: "audio.plugin.\(p)",
                    version: "Plugin",
                    path: full,
                    appSizeBytes: size,
                    relatedFiles: [],
                    lastOpenedDate: nil,
                    store: .other,
                    vendor: .other,
                    isSystemApp: false,
                    isAppStoreApp: false,
                    isSuspicious: false,
                    is32BitOrUnsupported: false,
                    isAudioPlugin: true,
                    sparkleFeedURL: nil
                ))
            }
        }

        return records.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }

    private func findRelatedFiles(
        appName: String,
        bundleID: String,
        buckets: [(dir: String, entries: [String], group: String)]
    ) -> [AppResourceFile] {
        var found: [AppResourceFile] = []
        let nameLower = appName.lowercased()
        let bidLower = bundleID.lowercased()

        func matches(_ entry: String) -> Bool {
            let e = entry.lowercased()
            if bidLower.count > 4 && e.contains(bidLower) { return true }
            if nameLower.count > 3 && (e == nameLower || e == "\(nameLower).plist" || e.hasPrefix("\(nameLower).")) { return true }
            return false
        }

        for bucket in buckets {
            for e in bucket.entries where matches(e) {
                let full = (bucket.dir as NSString).appendingPathComponent(e)
                let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                found.append(AppResourceFile(name: e, path: full, group: bucket.group, sizeBytes: size))
            }
        }
        return found
    }

    private func scanLeftovers(installedApps: [InstalledAppRecord], settings: RCleanerSettings) -> [ScanItem] {
        let fm = FileManager.default
        let installedBundleIDs = Set(installedApps.map { $0.bundleID.lowercased() })
        let installedNames = Set(installedApps.map { $0.name.lowercased() })

        let leftoverDirs = [
            FileSystemHelpers.expand("~/Library/Application Support"),
            FileSystemHelpers.expand("~/Library/Saved Application State")
        ]

        var items: [ScanItem] = []
        let safeSystemPrefixes = ["com.apple.", "apple", "icloud", "cloudkit", "crashreporter", "dock", "finder", "knowledge", "addressbook", "calendars", "callhistory", "mobilesync", "google", "mozilla", "r-cleaner", "rcleaner", "fileprovider", "syncservices"]

        for dir in leftoverDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                let lower = entry.lowercased().replacingOccurrences(of: ".savedstate", with: "")
                if safeSystemPrefixes.contains(where: { lower.hasPrefix($0) || lower == $0 }) { continue }
                if installedBundleIDs.contains(lower) || installedNames.contains(lower) { continue }
                if installedNames.contains(where: { $0.count > 3 && lower.contains($0) }) { continue }

                let full = (dir as NSString).appendingPathComponent(entry)
                if FileSystemHelpers.isIgnored(path: full, category: .uninstaller, settings: settings) { continue }
                // Only flag as leftover candidate if it looks like a reverse-DNS bundle ID not currently installed
                guard lower.contains(".") && !lower.hasPrefix(".") else { continue }
                let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                guard size > 8 * 1024 else { continue }

                items.append(ScanItem(
                    name: entry,
                    path: full,
                    sizeBytes: size,
                    subtitle: "Orphaned files from uninstalled app",
                    categoryID: "leftovers",
                    groupTitle: "Leftover Files",
                    isSelected: true
                ))
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func scanUnusedInstallers(settings: RCleanerSettings) -> [ScanItem] {
        let fm = FileManager.default
        let searchRoots = [
            FileSystemHelpers.expand("~/Downloads"),
            FileSystemHelpers.expand("~/Desktop"),
            FileSystemHelpers.expand("~/Documents")
        ]
        var items: [ScanItem] = []
        for root in searchRoots {
            guard let files = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for f in files {
                let ext = (f as NSString).pathExtension.lowercased()
                guard ext == "dmg" || ext == "pkg" || ext == "mpkg" else { continue }
                let full = (root as NSString).appendingPathComponent(f)
                if FileSystemHelpers.isIgnored(path: full, category: .uninstaller, settings: settings) { continue }
                let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                items.append(ScanItem(
                    name: f,
                    path: full,
                    sizeBytes: size,
                    subtitle: "\(ext.uppercased()) Installer in \(URL(fileURLWithPath: root).lastPathComponent)",
                    categoryID: "installers",
                    groupTitle: "Unused Installers",
                    isSelected: true
                ))
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func detectPotentialUpdatesLocally(apps: [InstalledAppRecord]) -> [AppUpdateRecord] {
        // Show apps with Sparkle appcast feeds ready to check
        return apps.filter { $0.sparkleFeedURL != nil }.prefix(8).map { app in
            AppUpdateRecord(
                appName: app.name,
                bundleID: app.bundleID,
                currentVersion: app.version,
                latestVersion: "Check Feed",
                source: "Sparkle Feed",
                releaseNotes: "App supports Sparkle automatic update checks via \(app.sparkleFeedURL ?? ""). Click 'Check Online' to query live appcasts.",
                downloadURL: app.sparkleFeedURL,
                isMacOSUpdate: false,
                isSelected: false
            )
        }
    }

    public func checkForUpdates(apps: [InstalledAppRecord]) async -> [AppUpdateRecord] {
        var found: [AppUpdateRecord] = []

        // 1. Query Sparkle feeds (bounded concurrency, quick timeout)
        let sparkleApps = Array(apps.filter { $0.sparkleFeedURL != nil }.prefix(12))
        await withTaskGroup(of: AppUpdateRecord?.self) { group in
            for app in sparkleApps {
                guard let feedStr = app.sparkleFeedURL, let url = URL(string: feedStr) else { continue }
                group.addTask {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 4
                    guard let (data, _) = try? await URLSession.shared.data(for: req),
                          let xml = String(data: data, encoding: .utf8) else { return nil }
                    // Parse sparkle:shortVersionString="..."
                    if let range = xml.range(of: #"sparkle:shortVersionString="([^"]+)""#, options: .regularExpression) {
                        let token = String(xml[range])
                        let latest = token
                            .replacingOccurrences(of: "sparkle:shortVersionString=\"", with: "")
                            .replacingOccurrences(of: "\"", with: "")
                        var enclosureURL = feedStr
                        if let encRange = xml.range(of: #"<enclosure[^>]*url="([^"]+)""#, options: .regularExpression) {
                            let encStr = String(xml[encRange])
                            if let urlPart = encStr.range(of: #"url="([^"]+)""#, options: .regularExpression) {
                                enclosureURL = String(encStr[urlPart])
                                    .replacingOccurrences(of: "url=\"", with: "")
                                    .replacingOccurrences(of: "\"", with: "")
                            }
                        }
                        if latest != app.version && latest.compare(app.version, options: .numeric) == .orderedDescending {
                            return AppUpdateRecord(
                                appName: app.name,
                                bundleID: app.bundleID,
                                currentVersion: app.version,
                                latestVersion: latest,
                                source: "Sparkle Appcast",
                                releaseNotes: "New version \(latest) available (installed: \(app.version)). Click Download to fetch installer.",
                                downloadURL: enclosureURL,
                                isMacOSUpdate: false,
                                isSelected: true
                            )
                        }
                    }
                    return nil
                }
            }
            for await rec in group {
                if let rec { found.append(rec) }
            }
        }

        // 2. Check cached macOS software update status quickly (no-scan so it doesn't stall)
        let sw = FileSystemHelpers.runProcess("/usr/sbin/softwareupdate", arguments: ["-l", "--no-scan"], timeout: 5)
        if sw.exitCode == 0 && sw.stdout.contains("Label:") {
            let labelLine = sw.stdout.split(separator: "\n").first { $0.contains("Label:") } ?? "macOS Software Update"
            found.insert(AppUpdateRecord(
                appName: "macOS System Update",
                bundleID: "com.apple.systemupdate",
                currentVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                latestVersion: String(labelLine).replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces),
                source: "Apple Software Update",
                releaseNotes: "System updates should be installed via System Settings → Software Update.",
                downloadURL: nil,
                isMacOSUpdate: true,
                isSelected: false
            ), at: 0)
        }

        return found
    }

    // MARK: - Uninstall or Reset Apps

    public func uninstallApps(_ apps: [InstalledAppRecord], resetOnly: Bool = false) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0

        for app in apps where app.isSelected {
            // Quit running app first and allow brief graceful shutdown before removing files
            var terminatedAny = false
            for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier == app.bundleID {
                running.terminate()
                terminatedAny = true
            }
            if terminatedAny {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            // Remove selected related files
            for file in app.relatedFiles where file.isSelected {
                let res = FileSystemHelpers.safeRemoveItem(at: file.path, moveToTrash: true)
                if res.success {
                    freed += file.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Applications", itemName: "\(app.name) — \(file.name)", path: file.path, sizeBytes: file.sizeBytes, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Applications", itemName: file.name, path: file.path, sizeBytes: file.sizeBytes, status: .failed, errorMessage: res.error))
                }
            }

            if !resetOnly && !app.isSystemApp {
                let res = FileSystemHelpers.safeRemoveItem(at: app.path, moveToTrash: true)
                if res.success {
                    freed += app.appSizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Applications", itemName: app.name, path: app.path, sizeBytes: app.appSizeBytes, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Applications", itemName: app.name, path: app.path, sizeBytes: app.appSizeBytes, status: .failed, errorMessage: res.error))
                }
            }
        }

        return CleanupSummary(
            bytesFreed: freed,
            itemsProcessed: ok,
            itemsFailed: fail,
            logEntries: logs,
            title: resetOnly ? "App reset complete!" : "Job done!",
            subtitle: resetOnly ? "related files reset" : "successfully uninstalled"
        )
    }

    private func classifyStore(path: String, bundleID: String, isMAS: Bool) -> AppStoreSource {
        if isMAS { return .appStore }
        if path.contains("/Setapp/") { return .setapp }
        if path.lowercased().contains("steam") || bundleID.lowercased().contains("valvesoftware") { return .steam }
        if bundleID.lowercased().contains("blizzard") { return .battleNet }
        return .other
    }

    private func classifyVendor(bundleID: String, name: String) -> AppVendorGroup {
        let s = (bundleID + " " + name).lowercased()
        if s.contains("com.apple.") { return .apple }
        if s.contains("adobe") { return .adobe }
        if s.contains("google") { return .google }
        if s.contains("jetbrains") { return .jetBrains }
        if s.contains("microsoft") { return .microsoft }
        return .other
    }
}
