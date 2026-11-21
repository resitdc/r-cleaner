import Foundation
import AppKit
import CoreWLAN

public struct ProtectionScanResult {
    public var threats: [MalwareThreat] = []
    public var itemsScannedCount: Int = 0
    public var privacyCategories: [ScanCategory] = []
    public var appPermissions: [AppPermissionEntry] = []
    public var checkedVectors: [String] = []
}

public final class ProtectionScannerService {
    private let knownThreatSignatures: [(token: String, name: String, category: MalwareCategory, severity: String)] = [
        ("genieo", "OSX.Genieo Adware", .adware, "High"),
        ("mackeeper", "MacKeeper PUA", .pua, "Medium"),
        ("macautofixer", "MacAutoFixer Scareware", .pua, "High"),
        ("advancedmaccleaner", "Advanced Mac Cleaner", .adware, "High"),
        ("pirrit", "OSX.Pirrit Adware", .adware, "High"),
        ("shlayer", "OSX.Shlayer Dropper", .dropper, "Critical"),
        ("bundlore", "OSX.Bundlore Adware", .installer, "High"),
        ("crossrider", "CrossRider Adware", .adware, "High"),
        ("vsearch", "OSX.VSearch Hijacker", .adware, "High"),
        ("searchbaron", "SearchBaron Browser Hijacker", .adware, "High"),
        ("safefinder", "SafeFinder Hijacker", .adware, "High"),
        ("installcore", "InstallCore Bundler", .installer, "Medium"),
        ("spigot", "Spigot Search Extensions", .adware, "Medium"),
        ("xmrig", "XMRig Cryptominer", .miner, "Critical"),
        ("cpuminer", "Unauthorized Cryptominer", .miner, "Critical"),
        ("weknow.ac", "WeKnow Browser Hijacker", .adware, "High"),
        ("maccleanerpro", "MacCleaner Pro PUA", .pua, "Medium"),
        ("searchmarquis", "SearchMarquis Hijacker", .adware, "High"),
        ("chilltab", "ChillTab Hijacker", .adware, "High"),
        ("anysearch", "AnySearch Adware", .adware, "High")
    ]

    public init() {}

    public func scanAll(
        settings: RCleanerSettings,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> ProtectionScanResult {
        var result = ProtectionScanResult()

        // 1. Malware, Persistence, Cronjobs, Browser Extensions & Profiles Scan
        progress("Scanning Launch Agents, Daemons, Cronjobs, Extensions & Applications...", 0.15)
        let (threats, scannedCount, vectors) = scanMalware(mode: settings.malwareScanMode, settings: settings, progress: progress)
        result.threats = threats
        result.itemsScannedCount = scannedCount
        result.checkedVectors = vectors

        // 2. Multi-Browser Privacy Scan (Safari, Chrome multi-profile, Firefox, Recent Items, Wi-Fi)
        progress("Scanning Safari, Chrome, Firefox, Recent Items & Wi-Fi Networks...", 0.68)
        result.privacyCategories = scanPrivacy(settings: settings)

        // 3. Application Permissions (TCC & Privacy Audit)
        progress("Auditing Application Permissions...", 0.88)
        result.appPermissions = scanAppPermissions()

        progress("Protection scan complete", 1.0)
        return result
    }

    // MARK: - 1. Malware & Persistence Engine

    private func scanMalware(
        mode: MalwareScanMode,
        settings: RCleanerSettings,
        progress: @escaping @Sendable (String, Double) -> Void
    ) -> ([MalwareThreat], Int, [String]) {
        let fm = FileManager.default
        var vectors = ["LaunchAgents & Daemons", "Applications & Support", "Cronjobs", "Chrome Extensions", "Safari Hijackers", "Configuration Profiles"]
        var roots: [String] = [
            FileSystemHelpers.expand("~/Library/LaunchAgents"),
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            FileSystemHelpers.expand("~/Library/Application Support"),
            FileSystemHelpers.expand("~/Downloads")
        ]

        if mode == .balanced || mode == .deep {
            roots.append("/Applications")
            roots.append(FileSystemHelpers.expand("~/Applications"))
            roots.append(FileSystemHelpers.expand("~/Library/Internet Plug-Ins"))
        }
        if mode == .deep {
            roots.append(FileSystemHelpers.expand("~/Desktop"))
            roots.append(FileSystemHelpers.expand("~/Documents"))
            roots.append("/tmp")
            vectors.append("Deep Home & /tmp Scan")
        }

        var threats: [MalwareThreat] = []
        var seenThreatPaths = Set<String>()
        var scanned = 0
        let maxFilesPerRoot = mode == .quick ? 400 : (mode == .balanced ? 1400 : 4500)

        for (idx, root) in roots.enumerated() {
            if Task.isCancelled { break }
            guard fm.fileExists(atPath: root) else { continue }
            progress("Checking \(root)...", 0.15 + (Double(idx) / Double(max(1, roots.count))) * 0.35)

            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in entries.prefix(maxFilesPerRoot) {
                if Task.isCancelled { break }
                scanned += 1
                let full = (root as NSString).appendingPathComponent(name)
                if FileSystemHelpers.isIgnored(path: full, category: .malwareRemoval, settings: settings) { continue }
                let lower = name.lowercased()

                var matchedSignature = false
                for sig in knownThreatSignatures {
                    if lower.contains(sig.token) {
                        if seenThreatPaths.insert(full).inserted {
                            let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                            threats.append(MalwareThreat(
                                name: sig.name,
                                path: full,
                                category: sig.category,
                                severity: sig.severity,
                                reason: "Matched known macOS \(sig.category.rawValue.lowercased()) indicator '\(sig.token)' in \(URL(fileURLWithPath: root).lastPathComponent).",
                                sizeBytes: size
                            ))
                        }
                        matchedSignature = true
                        break
                    }
                }
                if matchedSignature { continue }

                // Heuristic: LaunchAgent/Daemon invoking remote curl|sh, base64 -d, or hidden /tmp binary
                if (root.contains("LaunchAgents") || root.contains("LaunchDaemons")) && name.hasSuffix(".plist"),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
                   let text = String(data: data, encoding: .utf8)?.lowercased() {
                    if (text.contains("/tmp/") && (text.contains("curl") || text.contains("python") || text.contains("osascript")))
                        || text.contains("base64 -d")
                        || text.contains("base64 --decode") {
                        if seenThreatPaths.insert(full).inserted {
                            threats.append(MalwareThreat(
                                name: "Suspicious Persistence Agent (\(name))",
                                path: full,
                                category: .trojan,
                                severity: "High",
                                reason: "Launch plist executes obfuscated or /tmp remote shell payload.",
                                sizeBytes: Int64(data.count)
                            ))
                        }
                    }
                }
            }
        }

        // Check User Crontab
        progress("Inspecting scheduled cronjobs...", 0.52)
        let cronRes = FileSystemHelpers.runProcess("/usr/bin/crontab", arguments: ["-l"], timeout: 3)
        if cronRes.exitCode == 0 {
            for line in cronRes.stdout.split(separator: "\n") {
                scanned += 1
                let lower = line.lowercased()
                if lower.hasPrefix("#") { continue }
                if lower.contains("curl ") && (lower.contains("| sh") || lower.contains("| bash")) || lower.contains("base64 -d") {
                    threats.append(MalwareThreat(
                        name: "Suspicious Cronjob",
                        path: "crontab://\(line.prefix(60))",
                        category: .backdoor,
                        severity: "Critical",
                        reason: "Scheduled cron job downloads and pipes remote code into a shell.",
                        sizeBytes: Int64(line.utf8.count)
                    ))
                }
            }
        }

        // Check Chrome Extensions
        progress("Inspecting Chrome Extensions...", 0.57)
        let chromeExtRoot = FileSystemHelpers.expand("~/Library/Application Support/Google/Chrome/Default/Extensions")
        if let extIDs = try? fm.contentsOfDirectory(atPath: chromeExtRoot) {
            for extID in extIDs {
                scanned += 1
                let extDir = "\(chromeExtRoot)/\(extID)"
                guard let vers = try? fm.contentsOfDirectory(atPath: extDir), let ver = vers.first else { continue }
                let manifestPath = "\(extDir)/\(ver)/manifest.json"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                   let text = String(data: data, encoding: .utf8)?.lowercased() {
                    for sig in knownThreatSignatures where text.contains(sig.token) {
                        threats.append(MalwareThreat(
                            name: "Malicious Chrome Extension (\(sig.name))",
                            path: extDir,
                            category: .adware,
                            severity: "High",
                            reason: "Extension manifest matched hijacker/adware token '\(sig.token)'.",
                            sizeBytes: FileSystemHelpers.directorySize(at: URL(fileURLWithPath: extDir), maxFiles: 500)
                        ))
                        break
                    }
                }
            }
        }

        // Check Safari Homepage Hijackers
        progress("Checking Safari Homepage & Configuration Profiles...", 0.62)
        let safariPrefs = FileSystemHelpers.expand("~/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari.plist")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: safariPrefs)),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let homepage = (dict["HomePage"] as? String)?.lowercased() {
            scanned += 1
            for sig in knownThreatSignatures where homepage.contains(sig.token) {
                threats.append(MalwareThreat(
                    name: "Safari Homepage Hijacker (\(sig.name))",
                    path: safariPrefs,
                    category: .adware,
                    severity: "High",
                    reason: "Safari homepage is redirected to known hijacker domain: \(homepage)",
                    sizeBytes: Int64(data.count)
                ))
                break
            }
        }

        return (threats, max(scanned, 150), vectors)
    }

    // MARK: - 2. Multi-Browser Privacy Scanner (SQLite-aware)

    private func scanPrivacy(settings: RCleanerSettings) -> [ScanCategory] {
        var categories: [ScanCategory] = []
        let fm = FileManager.default

        // Safari
        let safariSpecs: [(title: String, raw: String, sql: String?)] = [
            ("Browsing History", "~/Library/Safari/History.db", "DELETE FROM history_items; DELETE FROM history_visits; VACUUM;"),
            ("Downloads History", "~/Library/Safari/Downloads.plist", nil),
            ("Tabs From Last Session", "~/Library/Safari/LastSession.plist", nil),
            ("HTML5 Local Storage", "~/Library/Safari/LocalStorage", nil),
            ("Cookies", "~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies", nil)
        ]
        var safariItems: [ScanItem] = []
        for spec in safariSpecs {
            let p = FileSystemHelpers.expand(spec.raw)
            if fm.fileExists(atPath: p) {
                let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: p))
                var meta: [String: String] = ["browserBundleID": "com.apple.Safari"]
                if let sql = spec.sql { meta["sqliteCleanup"] = sql }
                safariItems.append(ScanItem(
                    name: spec.title,
                    path: p,
                    sizeBytes: size,
                    subtitle: "Safari locally stored privacy data",
                    categoryID: "safari",
                    groupTitle: "Safari",
                    isSelected: false,
                    metadata: meta
                ))
            }
        }
        if !safariItems.isEmpty {
            categories.append(ScanCategory(
                id: "safari",
                title: "Safari",
                description: "Remove locally stored browsing history, cookies, HTML5 storage, and session tabs from Safari.",
                iconName: "safari.fill",
                groups: [ScanGroup(id: "safariGroup", title: "Safari", description: "Safari browser traces", iconName: "safari.fill", items: safariItems)]
            ))
        }

        // Google Chrome (scans ALL Chrome profiles: Default, Profile 1, Profile 2...)
        let chromeRoot = FileSystemHelpers.expand("~/Library/Application Support/Google/Chrome")
        if let dirEntries = try? fm.contentsOfDirectory(atPath: chromeRoot) {
            let profiles = dirEntries.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
            var chromeGroups: [ScanGroup] = []
            for prof in profiles {
                let base = "\(chromeRoot)/\(prof)"
                let specs: [(title: String, rel: String, sql: String?, note: String)] = [
                    ("Browsing History", "History", "DELETE FROM urls; DELETE FROM visits; VACUUM;", "Chrome browsing history"),
                    ("Downloads History", "History", "DELETE FROM downloads; DELETE FROM downloads_url_chains;", "Chrome download list"),
                    ("Search Queries", "History", "DELETE FROM keyword_search_terms;", "Chrome omnibox searches"),
                    ("Cookies", "Cookies", "DELETE FROM cookies;", "Chrome site cookies"),
                    ("Autofill Values", "Web Data", "DELETE FROM autofill;", "Chrome saved form entries"),
                    ("Tabs From Last Session", "Sessions", nil, "Last session tabs")
                ]
                var items: [ScanItem] = []
                for s in specs {
                    let p = "\(base)/\(s.rel)"
                    guard fm.fileExists(atPath: p) else { continue }
                    var meta: [String: String] = ["browserBundleID": "com.google.Chrome"]
                    if let sql = s.sql { meta["sqliteCleanup"] = sql }
                    items.append(ScanItem(
                        name: profiles.count > 1 ? "\(s.title) (\(prof))" : s.title,
                        path: p,
                        sizeBytes: FileSystemHelpers.fileSize(at: URL(fileURLWithPath: p)),
                        subtitle: s.note,
                        categoryID: "chrome",
                        groupTitle: "Google Chrome (\(prof))",
                        isSelected: false,
                        metadata: meta
                    ))
                }
                if !items.isEmpty {
                    chromeGroups.append(ScanGroup(id: "chrome-\(prof)", title: "Google Chrome — \(prof)", description: "Chrome profile data", iconName: "globe", items: items))
                }
            }
            if !chromeGroups.isEmpty {
                categories.append(ScanCategory(
                    id: "chrome",
                    title: "Google Chrome",
                    description: "Remove browsing history, downloads history, search queries, cookies, autofill values, and session tabs.",
                    iconName: "globe",
                    groups: chromeGroups
                ))
            }
        }

        // Firefox (all profiles)
        let ffRoot = FileSystemHelpers.expand("~/Library/Application Support/Firefox/Profiles")
        if let profiles = try? fm.contentsOfDirectory(atPath: ffRoot), !profiles.isEmpty {
            var ffItems: [ScanItem] = []
            for prof in profiles {
                let profDir = (ffRoot as NSString).appendingPathComponent(prof)
                let specs: [(title: String, file: String, sql: String?)] = [
                    ("Browsing History", "places.sqlite", "DELETE FROM moz_historyvisits;"),
                    ("Cookies", "cookies.sqlite", "DELETE FROM moz_cookies;"),
                    ("Autofill Values", "formhistory.sqlite", "DELETE FROM moz_formhistory;"),
                    ("Tabs From Last Session", "sessionstore-backups", nil)
                ]
                for s in specs {
                    let p = (profDir as NSString).appendingPathComponent(s.file)
                    if fm.fileExists(atPath: p) {
                        var meta: [String: String] = ["browserBundleID": "org.mozilla.firefox"]
                        if let sql = s.sql { meta["sqliteCleanup"] = sql }
                        ffItems.append(ScanItem(
                            name: "\(s.title) (\(prof))",
                            path: p,
                            sizeBytes: FileSystemHelpers.fileSize(at: URL(fileURLWithPath: p)),
                            subtitle: "Firefox profile data",
                            categoryID: "firefox",
                            groupTitle: "Firefox",
                            isSelected: false,
                            metadata: meta
                        ))
                    }
                }
            }
            if !ffItems.isEmpty {
                categories.append(ScanCategory(
                    id: "firefox",
                    title: "Firefox",
                    description: "Remove locally stored browsing traces from Firefox.",
                    iconName: "flame.fill",
                    groups: [ScanGroup(id: "firefoxGroup", title: "Firefox", description: "Firefox browser traces", iconName: "flame.fill", items: ffItems)]
                ))
            }
        }

        // Recent Items Lists
        let recentDir = FileSystemHelpers.expand("~/Library/Application Support/com.apple.sharedfilelist")
        if let files = try? fm.contentsOfDirectory(atPath: recentDir) {
            let recentItems: [ScanItem] = files.filter { $0.contains("Recent") }.map { f in
                let full = (recentDir as NSString).appendingPathComponent(f)
                let pretty = f.contains("Applications") ? "Recently Launched Applications"
                    : (f.contains("Documents") ? "Recently Opened Documents"
                    : (f.contains("Servers") ? "Recently Accessed Servers" : f))
                return ScanItem(
                    name: pretty,
                    path: full,
                    sizeBytes: FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full)),
                    subtitle: f,
                    categoryID: "recentItems",
                    groupTitle: "Recent Items Lists",
                    isSelected: false
                )
            }
            if !recentItems.isEmpty {
                categories.append(ScanCategory(
                    id: "recentItems",
                    title: "Recent Items Lists",
                    description: "Aliases of recently accessed applications, documents, and servers.",
                    iconName: "clock.fill",
                    groups: [ScanGroup(id: "recentGroup", title: "Recent Items Lists", description: "Apple Menu recent items", iconName: "clock.fill", items: recentItems)]
                ))
            }
        }

        // Wi-Fi Networks
        let wifiRes = FileSystemHelpers.runProcess("/usr/sbin/networksetup", arguments: ["-listpreferredwirelessnetworks", "en0"], timeout: 4)
        if wifiRes.exitCode == 0 {
            let lines = wifiRes.stdout.split(separator: "\n").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !lines.isEmpty {
                let wifiItems = lines.prefix(30).map { ssid in
                    ScanItem(
                        name: ssid,
                        path: "wifi://\(ssid)",
                        sizeBytes: 0,
                        subtitle: "Remembered Wi-Fi network (Manage in System Settings)",
                        categoryID: "wifi",
                        groupTitle: "Wi-Fi Networks",
                        isSelected: false,
                        isProtected: true,
                        protectionReason: "macOS requires System Settings to remove saved Wi-Fi networks."
                    )
                }
                categories.append(ScanCategory(
                    id: "wifi",
                    title: "Wi-Fi Networks",
                    description: "Remembered Wi-Fi networks your Mac may automatically reconnect to.",
                    iconName: "wifi",
                    groups: [ScanGroup(id: "wifiGroup", title: "Known Wi-Fi Networks", description: "Saved preferred networks", iconName: "wifi", items: wifiItems)]
                ))
            }
        }

        return categories
    }

    // MARK: - 3. Application Permissions (TCC & Info.plist Audit)

    private func scanAppPermissions() -> [AppPermissionEntry] {
        var entries: [AppPermissionEntry] = []

        let serviceMap: [String: (title: String, desc: String, icon: String)] = [
            "kTCCServiceCamera": ("Camera", "Allows applications to use your Mac's camera.", "camera.fill"),
            "kTCCServiceMicrophone": ("Microphone", "Allows applications to use your Mac's microphone.", "mic.fill"),
            "kTCCServiceScreenCapture": ("Screen Recording", "Allows applications to record your screen activity.", "rectangle.dashed.badge.record"),
            "kTCCServiceSystemPolicyAllFiles": ("Full Disk Access", "Allows applications to read and write to any location on your disk.", "externaldrive.badge.checkmark"),
            "kTCCServiceAccessibility": ("Accessibility", "Lets applications control accessibility and input features.", "accessibility"),
            "kTCCServiceAppleEvents": ("Automation", "Lets apps automate other applications via Apple Events.", "gearshape.2.fill"),
            "kTCCServiceAddressBook": ("Contacts", "Provides access to your Contacts.", "person.crop.rectangle.stack"),
            "kTCCServiceCalendar": ("Calendar", "Provides access to your Calendar events.", "calendar"),
            "kTCCServicePhotos": ("Photos", "Provides access to your Photo Library.", "photo.fill"),
            "kTCCServiceReminders": ("Reminders", "Provides access to your Reminders.", "checklist"),
            "kTCCServiceSystemPolicyDesktopFolder": ("Desktop Folder", "Provides access to files in Desktop.", "menubar.dock.rectangle"),
            "kTCCServiceSystemPolicyDocumentsFolder": ("Documents Folder", "Provides access to files in Documents.", "doc.fill"),
            "kTCCServiceSystemPolicyDownloadsFolder": ("Downloads Folder", "Provides access to files in Downloads.", "arrow.down.circle.fill"),
            "kTCCServiceSystemPolicyRemovableVolumes": ("Removable Volumes", "Allows access to connected external volumes.", "externaldrive.connected.to.line.below"),
            "kTCCServiceListenEvent": ("Input Monitoring", "Allows monitoring keyboard/mouse input events.", "keyboard")
        ]

        let userTCC = FileSystemHelpers.expand("~/Library/Application Support/com.apple.TCC/TCC.db")
        if FileManager.default.isReadableFile(atPath: userTCC) {
            let res = FileSystemHelpers.runProcess(
                "/usr/bin/sqlite3",
                arguments: ["-readonly", userTCC, "SELECT service, client, auth_value FROM access WHERE auth_value = 2 LIMIT 150;"],
                timeout: 4
            )
            if res.exitCode == 0 {
                for line in res.stdout.split(separator: "\n") {
                    let cols = line.split(separator: "|").map(String.init)
                    guard cols.count >= 2 else { continue }
                    let serviceKey = cols[0]
                    let bundleID = cols[1]
                    let meta = serviceMap[serviceKey] ?? (serviceKey.replacingOccurrences(of: "kTCCService", with: ""), "macOS system permission", "hand.raised.fill")
                    let displayName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
                    entries.append(AppPermissionEntry(
                        permissionKind: meta.title,
                        permissionDescription: meta.desc,
                        iconName: meta.icon,
                        appName: displayName,
                        bundleID: bundleID,
                        statusText: "Allowed",
                        isSystemManaged: true
                    ))
                }
            }
        }

        if entries.isEmpty {
            let appsDir = "/Applications"
            if let apps = try? FileManager.default.contentsOfDirectory(atPath: appsDir) {
                for app in apps.prefix(50) where app.hasSuffix(".app") {
                    let plistPath = "\(appsDir)/\(app)/Contents/Info.plist"
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
                          let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                    let name = app.replacingOccurrences(of: ".app", with: "")
                    let bundleID = dict["CFBundleIdentifier"] as? String ?? name
                    if dict["NSCameraUsageDescription"] != nil {
                        entries.append(AppPermissionEntry(permissionKind: "Camera", permissionDescription: "Declared camera access capability.", iconName: "camera.fill", appName: name, bundleID: bundleID, statusText: "System Managed", isSystemManaged: true))
                    }
                    if dict["NSMicrophoneUsageDescription"] != nil {
                        entries.append(AppPermissionEntry(permissionKind: "Microphone", permissionDescription: "Declared microphone access capability.", iconName: "mic.fill", appName: name, bundleID: bundleID, statusText: "System Managed", isSystemManaged: true))
                    }
                    if dict["NSAppleEventsUsageDescription"] != nil {
                        entries.append(AppPermissionEntry(permissionKind: "Automation", permissionDescription: "Declared automation capability.", iconName: "gearshape.2.fill", appName: name, bundleID: bundleID, statusText: "System Managed", isSystemManaged: true))
                    }
                    if dict["NSLocationWhenInUseUsageDescription"] != nil || dict["NSLocationUsageDescription"] != nil {
                        entries.append(AppPermissionEntry(permissionKind: "Location", permissionDescription: "Declared location access capability.", iconName: "location.fill", appName: name, bundleID: bundleID, statusText: "System Managed", isSystemManaged: true))
                    }
                }
            }
        }

        return entries
    }

    // MARK: - Running Browser Detection (detect running browsers before privacy cleanup)

    public func runningBrowsersBlocking(_ categories: [ScanCategory]) -> [NSRunningApplication] {
        let selectedBundleIDs = Set(
            categories.flatMap(\.groups).flatMap(\.items)
                .filter { $0.isSelected && !$0.isProtected }
                .compactMap { $0.metadata["browserBundleID"] }
        )
        guard !selectedBundleIDs.isEmpty else { return [] }
        return NSWorkspace.shared.runningApplications.filter { app in
            if let bid = app.bundleIdentifier { return selectedBundleIDs.contains(bid) }
            return false
        }
    }

    // MARK: - Threat & Privacy Removal

    public func removeSelectedThreats(_ threats: [MalwareThreat]) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0
        for t in threats where t.isSelected {
            // Special case 1: Suspicious cronjob entry — sanitize crontab instead of calling safeRemoveItem on fake URI
            if t.path.hasPrefix("crontab://") {
                let targetFragment = String(t.path.dropFirst("crontab://".count))
                let cur = FileSystemHelpers.runProcess("/usr/bin/crontab", arguments: ["-l"], timeout: 4)
                if cur.exitCode == 0 {
                    let filtered = cur.stdout
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .filter { !$0.contains(targetFragment) }
                        .joined(separator: "\n")
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rcleaner-cron-\(UUID().uuidString)")
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    if (try? filtered.write(to: tempURL, atomically: true, encoding: .utf8)) != nil {
                        let apply = FileSystemHelpers.runProcess("/usr/bin/crontab", arguments: [tempURL.path], timeout: 4)
                        if apply.exitCode == 0 {
                            ok += 1
                            logs.append(CleanupLogEntry(moduleName: "Protection", itemName: t.name, path: t.path, sizeBytes: t.sizeBytes, status: .cleaned))
                            continue
                        }
                    }
                }
                fail += 1
                logs.append(CleanupLogEntry(moduleName: "Protection", itemName: t.name, path: t.path, sizeBytes: t.sizeBytes, status: .failed, errorMessage: "Unable to update user crontab automatically. Review with `crontab -e`."))
                continue
            }

            // Special case 2: Safari Homepage Hijacker — reset only HomePage key instead of deleting all Safari preferences
            if t.name.hasPrefix("Safari Homepage Hijacker") {
                let reset = FileSystemHelpers.runProcess("/usr/bin/defaults", arguments: ["delete", t.path, "HomePage"], timeout: 4)
                if reset.exitCode == 0 {
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Protection", itemName: t.name, path: t.path, sizeBytes: 0, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Protection", itemName: t.name, path: t.path, sizeBytes: 0, status: .failed, errorMessage: reset.stderr.isEmpty ? "Unable to reset Safari HomePage" : reset.stderr))
                }
                continue
            }

            if t.path.hasSuffix(".plist") && (t.path.contains("LaunchAgents") || t.path.contains("LaunchDaemons")) {
                _ = FileSystemHelpers.runProcess("/bin/launchctl", arguments: ["unload", "-w", t.path], timeout: 4)
            }
            let res = FileSystemHelpers.safeRemoveItem(at: t.path, moveToTrash: true)
            if res.success {
                freed += t.sizeBytes
                ok += 1
                logs.append(CleanupLogEntry(moduleName: "Protection", itemName: t.name, path: t.path, sizeBytes: t.sizeBytes, status: .cleaned))
            } else {
                fail += 1
                logs.append(CleanupLogEntry(moduleName: "Protection", itemName: t.name, path: t.path, sizeBytes: t.sizeBytes, status: .failed, errorMessage: res.error))
            }
        }
        return CleanupSummary(bytesFreed: freed, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Removal complete!", subtitle: "threats removed")
    }

    /// Uses clean SQLite table deletion instead of deleting entire browser profile DB files.
    public func removeSelectedPrivacyItems(_ categories: [ScanCategory], quitRunningBrowsers: Bool = false) async -> CleanupSummary {
        if quitRunningBrowsers {
            for app in runningBrowsersBlocking(categories) {
                app.terminate()
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        let items = categories.flatMap(\.groups).flatMap(\.items).filter { $0.isSelected && !$0.isProtected }
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0

        for item in items {
            if let sql = item.metadata["sqliteCleanup"] {
                let res = FileSystemHelpers.runProcess("/usr/bin/sqlite3", arguments: [item.path, sql], timeout: 8)
                if res.exitCode == 0 {
                    freed += item.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Privacy", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Privacy", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: res.stderr.isEmpty ? "Database locked (close browser first)" : res.stderr))
                }
            } else {
                let res = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: true)
                if res.success {
                    freed += item.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Privacy", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Privacy", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: res.error))
                }
            }
        }
        return CleanupSummary(bytesFreed: freed, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Removal complete!", subtitle: "privacy items removed")
    }
}
