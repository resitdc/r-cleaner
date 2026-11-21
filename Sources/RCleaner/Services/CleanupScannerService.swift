import Foundation

public final class CleanupScannerService {
    public init() {}

    public func scanAll(
        settings: RCleanerSettings,
        focusedCategory: String? = nil,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> [ScanCategory] {
        var categories: [ScanCategory] = []

        let runSystemJunk = (focusedCategory == nil && settings.scanSystemJunk) || focusedCategory == "systemJunk"
        let runMail = (focusedCategory == nil && settings.scanMailAttachments) || focusedCategory == "mailAttachments"
        let runTrash = (focusedCategory == nil && settings.scanTrashBins) || focusedCategory == "trashBins"
        let runAI = (focusedCategory == nil && settings.scanAIClutter) || focusedCategory == "aiClutter"

        if runSystemJunk {
            progress("Scanning System Junk (Caches, Logs, Xcode, Localizations, Preferences)...", 0.12)
            let cat = scanSystemJunk(settings: settings, progress: progress)
            if cat.totalCount > 0 { categories.append(cat) }
        }

        if runMail {
            progress("Looking for Mail Attachments...", 0.62)
            let cat = scanMailAttachments(settings: settings)
            if cat.totalCount > 0 { categories.append(cat) }
        }

        if runTrash {
            progress("Checking System, Mail & External Trash Bins...", 0.74)
            let cat = scanTrashBins(settings: settings)
            if cat.totalCount > 0 { categories.append(cat) }
        }

        if runAI {
            progress("Scanning AI Clutter (Claude, Codex, Gemini, Cursor) & Local Models...", 0.85)
            let cat = scanAIClutter(settings: settings)
            if cat.totalCount > 0 { categories.append(cat) }
        }

        progress("Scan complete", 1.0)
        return categories
    }

    // MARK: - 1. System Junk

    private func scanSystemJunk(
        settings: RCleanerSettings,
        progress: @escaping @Sendable (String, Double) -> Void
    ) -> ScanCategory {
        var groups: [ScanGroup] = []
        let fm = FileManager.default

        // 1A. User Cache Files (~/Library/Caches + Sandbox Containers + Electron App Caches + Dev Caches)
        progress("~/Library/Caches", 0.16)
        var userCacheItems = scanDirectChildren(
            in: FileSystemHelpers.expand("~/Library/Caches"),
            categoryID: "systemJunk",
            groupTitle: "User Cache Files",
            ignoreCategory: .systemJunk,
            settings: settings,
            minSizeBytes: 64 * 1024
        )

        // Sandbox container caches: ~/Library/Containers/*/Data/Library/Caches
        progress("~/Library/Containers caches", 0.20)
        let containersDir = FileSystemHelpers.expand("~/Library/Containers")
        if let containers = try? fm.contentsOfDirectory(atPath: containersDir) {
            for container in containers.prefix(120) {
                let cacheDir = "\(containersDir)/\(container)/Data/Library/Caches"
                guard fm.fileExists(atPath: cacheDir) else { continue }
                if FileSystemHelpers.isIgnored(path: cacheDir, category: .systemJunk, settings: settings) { continue }
                let size = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: cacheDir), maxFiles: 1500)
                if size >= 256 * 1024 {
                    userCacheItems.append(ScanItem(
                        name: "\(container) (Container Cache)",
                        path: cacheDir,
                        sizeBytes: size,
                        subtitle: "Sandboxed app cache",
                        categoryID: "systemJunk",
                        groupTitle: "User Cache Files",
                        badge: "Sandbox"
                    ))
                }
            }
        }

        // Electron / Developer Caches (Gradle, npm, Homebrew, Electron App Support caches)
        let devCachePaths: [(String, String)] = [
            ("~/.gradle/caches", "Gradle Build Cache"),
            ("~/.npm/_cacache", "npm Package Cache"),
            ("~/Library/Caches/Homebrew", "Homebrew Download Cache"),
            ("~/Library/Caches/CocoaPods", "CocoaPods Cache"),
            ("~/Library/Caches/org.swift.swiftpm", "SwiftPM Cache")
        ]
        for (raw, label) in devCachePaths {
            let full = FileSystemHelpers.expand(raw)
            guard fm.fileExists(atPath: full),
                  !FileSystemHelpers.isIgnored(path: full, category: .systemJunk, settings: settings) else { continue }
            let sz = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: full), maxFiles: 5000)
            if sz >= 1024 * 1024 {
                userCacheItems.append(ScanItem(
                    name: label,
                    path: full,
                    sizeBytes: sz,
                    subtitle: full,
                    categoryID: "systemJunk",
                    groupTitle: "User Cache Files",
                    badge: "Dev Cache"
                ))
            }
        }

        // Deduplicate by path and sort largest first
        var seenPaths = Set<String>()
        userCacheItems = userCacheItems.filter { seenPaths.insert($0.path).inserted }.sorted { $0.sizeBytes > $1.sizeBytes }
        if !userCacheItems.isEmpty {
            groups.append(ScanGroup(
                id: "userCaches",
                title: "User Cache Files",
                description: "Application, Sandbox Container, Electron, and build cache files that can be safely regenerated.",
                iconName: "archivebox.fill",
                items: userCacheItems
            ))
        }

        // 1B. System Cache Files
        progress("/Library/Caches", 0.25)
        let sysCacheItems = scanDirectChildren(
            in: "/Library/Caches",
            categoryID: "systemJunk",
            groupTitle: "System Cache Files",
            ignoreCategory: .systemJunk,
            settings: settings,
            minSizeBytes: 64 * 1024
        )
        if !sysCacheItems.isEmpty {
            groups.append(ScanGroup(
                id: "systemCaches",
                title: "System Cache Files",
                description: "System-wide caches created by macOS services and shared applications.",
                iconName: "externaldrive.fill",
                items: sysCacheItems
            ))
        }

        // 1C. User Log Files (~/Library/Logs + Sandbox Logs)
        progress("~/Library/Logs", 0.30)
        var userLogItems = scanDirectChildren(
            in: FileSystemHelpers.expand("~/Library/Logs"),
            categoryID: "systemJunk",
            groupTitle: "User Log Files",
            ignoreCategory: .systemJunk,
            settings: settings,
            minSizeBytes: 8 * 1024
        )
        if let containers = try? fm.contentsOfDirectory(atPath: containersDir) {
            for container in containers.prefix(80) {
                let logDir = "\(containersDir)/\(container)/Data/Library/Logs"
                guard fm.fileExists(atPath: logDir) else { continue }
                let size = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: logDir), maxFiles: 400)
                if size >= 64 * 1024 {
                    userLogItems.append(ScanItem(
                        name: "\(container) (Container Logs)",
                        path: logDir,
                        sizeBytes: size,
                        subtitle: "Sandbox container logs",
                        categoryID: "systemJunk",
                        groupTitle: "User Log Files"
                    ))
                }
            }
        }
        userLogItems.sort { $0.sizeBytes > $1.sizeBytes }
        if !userLogItems.isEmpty {
            groups.append(ScanGroup(
                id: "userLogs",
                title: "User Log Files",
                description: "Diagnostic and activity logs created by user applications.",
                iconName: "doc.plaintext.fill",
                items: userLogItems
            ))
        }

        // 1D. System Log Files
        progress("/Library/Logs", 0.34)
        let sysLogItems = scanDirectChildren(
            in: "/Library/Logs",
            categoryID: "systemJunk",
            groupTitle: "System Log Files",
            ignoreCategory: .systemJunk,
            settings: settings,
            minSizeBytes: 16 * 1024
        )
        if !sysLogItems.isEmpty {
            groups.append(ScanGroup(
                id: "systemLogs",
                title: "System Log Files",
                description: "System activity logs helpful only for debugging.",
                iconName: "text.alignleft",
                items: sysLogItems
            ))
        }

        // 1E. Xcode Junk (DerivedData, ModuleCache, Archives, iOS/macOS DeviceSupport, CoreSimulator Caches, Device Logs)
        progress("~/Library/Developer/Xcode", 0.39)
        let xcodePaths: [(path: String, label: String, defaultSelected: Bool)] = [
            ("~/Library/Developer/Xcode/DerivedData", "Xcode DerivedData", true),
            ("~/Library/Developer/CoreSimulator/Caches", "CoreSimulator Caches", true),
            ("~/Library/Developer/Xcode/iOS Device Logs", "iOS Device Logs", true),
            ("~/Library/Developer/Xcode/UserData/IB Support", "Interface Builder Cache", true),
            ("~/Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport Symbols", true),
            ("~/Library/Developer/Xcode/macOS DeviceSupport", "macOS DeviceSupport", true),
            ("~/Library/Developer/Xcode/Archives", "Xcode Archives", false)
        ]
        var xcodeItems: [ScanItem] = []
        for spec in xcodePaths {
            let expanded = FileSystemHelpers.expand(spec.path)
            let children = scanDirectChildren(
                in: expanded,
                categoryID: "systemJunk",
                groupTitle: "Xcode Junk",
                ignoreCategory: .systemJunk,
                settings: settings,
                minSizeBytes: 32 * 1024,
                defaultSelected: spec.defaultSelected,
                subtitleOverride: spec.label
            )
            xcodeItems.append(contentsOf: children)
        }
        if !xcodeItems.isEmpty {
            groups.append(ScanGroup(
                id: "xcodeJunk",
                title: "Xcode Junk",
                description: "DerivedData, simulator caches, DeviceSupport symbols, device logs, and old Xcode archives.",
                iconName: "hammer.fill",
                items: xcodeItems.sorted { $0.sizeBytes > $1.sizeBytes }
            ))
        }

        // 1F. Language Files (Unused .lproj bundles in third-party /Applications)
        progress("Checking unused Language Files...", 0.44)
        let langItems = scanUnusedLanguageFiles(settings: settings)
        if !langItems.isEmpty {
            groups.append(ScanGroup(
                id: "languageFiles",
                title: "Language Files",
                description: "Unused application localizations outside your preferred macOS languages. Unselected by default to preserve app signatures.",
                iconName: "globe",
                items: langItems
            ))
        }

        // 1G. Universal Binaries (Non-native architecture slice detection in third-party /Applications)
        progress("Inspecting Universal Binaries...", 0.48)
        let ubItems = scanUniversalBinaries(settings: settings)
        if !ubItems.isEmpty {
            groups.append(ScanGroup(
                id: "universalBinaries",
                title: "Universal Binaries",
                description: "Applications carrying both Apple Silicon (arm64) and Intel (x86_64) slices. Review only — thinning signed apps is skipped by default.",
                iconName: "cpu",
                items: ubItems
            ))
        }

        // 1H. Broken Preferences (Corrupt .plist files)
        progress("~/Library/Preferences", 0.52)
        var brokenPrefs: [ScanItem] = []
        let prefsDir = FileSystemHelpers.expand("~/Library/Preferences")
        if let files = try? fm.contentsOfDirectory(atPath: prefsDir) {
            for f in files where f.hasSuffix(".plist") {
                let full = (prefsDir as NSString).appendingPathComponent(f)
                if FileSystemHelpers.isIgnored(path: full, category: .systemJunk, settings: settings) { continue }
                if let data = try? Data(contentsOf: URL(fileURLWithPath: full)), !data.isEmpty {
                    do {
                        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    } catch {
                        brokenPrefs.append(ScanItem(
                            name: f,
                            path: full,
                            sizeBytes: Int64(data.count),
                            subtitle: "Corrupted property list",
                            categoryID: "systemJunk",
                            groupTitle: "Broken Preferences"
                        ))
                    }
                }
            }
        }
        if !brokenPrefs.isEmpty {
            groups.append(ScanGroup(
                id: "brokenPreferences",
                title: "Broken Preferences",
                description: "Corrupted preference files that can cause apps to crash or misbehave.",
                iconName: "exclamationmark.triangle.fill",
                items: brokenPrefs
            ))
        }

        // 1I. Broken Login Items (Orphaned LaunchAgents)
        progress("~/Library/LaunchAgents", 0.55)
        var brokenLoginItems: [ScanItem] = []
        let launchDir = FileSystemHelpers.expand("~/Library/LaunchAgents")
        if let files = try? fm.contentsOfDirectory(atPath: launchDir) {
            for f in files where f.hasSuffix(".plist") {
                let full = (launchDir as NSString).appendingPathComponent(f)
                if FileSystemHelpers.isIgnored(path: full, category: .systemJunk, settings: settings) { continue }
                if let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                    if let prog = program, prog.hasPrefix("/"), !fm.fileExists(atPath: prog) {
                        brokenLoginItems.append(ScanItem(
                            name: f,
                            path: full,
                            sizeBytes: Int64(data.count),
                            subtitle: "Missing target: \(prog)",
                            categoryID: "systemJunk",
                            groupTitle: "Broken Login Items"
                        ))
                    }
                }
            }
        }
        if !brokenLoginItems.isEmpty {
            groups.append(ScanGroup(
                id: "brokenLoginItems",
                title: "Broken Login Items",
                description: "Orphaned startup links whose target applications were previously removed.",
                iconName: "link.badge.plus",
                items: brokenLoginItems
            ))
        }

        // 1J. iOS Device Backups (with Device Name, iOS Version & Latest Badge)
        progress("~/Library/Application Support/MobileSync/Backup", 0.58)
        let iosBackups = scanIOSBackups(settings: settings)
        if !iosBackups.isEmpty {
            groups.append(ScanGroup(
                id: "iosBackups",
                title: "iOS Device Backups",
                description: "Local iPhone and iPad backups stored on your Mac. Latest backups are marked for safety.",
                iconName: "iphone",
                items: iosBackups
            ))
        }

        // 1K. Deleted Users
        let deletedUsers = scanDirectChildren(
            in: "/Users/Deleted Users",
            categoryID: "systemJunk",
            groupTitle: "Deleted Users",
            ignoreCategory: .systemJunk,
            settings: settings,
            minSizeBytes: 1024,
            defaultSelected: false
        )
        if !deletedUsers.isEmpty {
            groups.append(ScanGroup(
                id: "deletedUsers",
                title: "Deleted Users",
                description: "Remaining home folder archives of previously deleted macOS accounts.",
                iconName: "person.crop.circle.badge.xmark",
                items: deletedUsers
            ))
        }

        return ScanCategory(
            id: "systemJunk",
            title: "System Junk",
            description: "Redundant files that clog up device storage and impede optimal performance.",
            iconName: "sparkles.rectangle.stack.fill",
            groups: groups
        )
    }

    private func scanUnusedLanguageFiles(settings: RCleanerSettings) -> [ScanItem] {
        let fm = FileManager.default
        let preferredCodes = Set(Locale.preferredLanguages.map { $0.split(separator: "-").first.map(String.init)?.lowercased() ?? "en" } + ["en", "base"])
        let appsDir = "/Applications"
        guard let apps = try? fm.contentsOfDirectory(atPath: appsDir) else { return [] }

        var byLang: [String: (size: Int64, samplePath: String, appCount: Int)] = [:]
        for app in apps.prefix(60) where app.hasSuffix(".app") {
            let resDir = "\(appsDir)/\(app)/Contents/Resources"
            guard let items = try? fm.contentsOfDirectory(atPath: resDir) else { continue }
            for item in items where item.hasSuffix(".lproj") {
                let code = item.replacingOccurrences(of: ".lproj", with: "").lowercased()
                let baseCode = code.split(separator: "-").first.map(String.init) ?? code
                if preferredCodes.contains(code) || preferredCodes.contains(baseCode) { continue }
                let full = "\(resDir)/\(item)"
                if FileSystemHelpers.isIgnored(path: full, category: .systemJunk, settings: settings) { continue }
                let sz = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: full), maxFiles: 200)
                if sz > 16 * 1024 {
                    var cur = byLang[code] ?? (0, full, 0)
                    cur.size += sz
                    cur.appCount += 1
                    byLang[code] = cur
                }
            }
        }

        return byLang.compactMap { code, info in
            guard info.size >= 256 * 1024 else { return nil }
            let localizedName = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
            return ScanItem(
                name: "\(localizedName) (\(code).lproj)",
                path: info.samplePath,
                sizeBytes: info.size,
                subtitle: "Found across \(info.appCount) app(s)",
                categoryID: "systemJunk",
                groupTitle: "Language Files",
                isSelected: false,
                isProtected: true,
                protectionReason: "Protected to preserve macOS code signatures."
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func scanUniversalBinaries(settings: RCleanerSettings) -> [ScanItem] {
        let fm = FileManager.default
        let appsDir = "/Applications"
        guard let apps = try? fm.contentsOfDirectory(atPath: appsDir) else { return [] }

        var items: [ScanItem] = []
        for app in apps.prefix(50) where app.hasSuffix(".app") {
            let macosDir = "\(appsDir)/\(app)/Contents/MacOS"
            guard let bins = try? fm.contentsOfDirectory(atPath: macosDir), let mainBin = bins.first else { continue }
            let binPath = "\(macosDir)/\(mainBin)"
            if FileSystemHelpers.isIgnored(path: binPath, category: .systemJunk, settings: settings) { continue }
            guard let fh = try? FileHandle(forReadingFrom: URL(fileURLWithPath: binPath)) else { continue }
            let header = fh.readData(ofLength: 8)
            try? fh.close()
            guard header.count >= 4 else { continue }
            let magic = header.withUnsafeBytes { $0.load(as: UInt32.self) }
            // FAT_MAGIC (0xcafebabe) or FAT_CIGAM (0xbebafeca)
            if magic == 0xcafebabe || magic == 0xbebafeca {
                let totalSize = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: binPath))
                let extraSliceEstimate = totalSize / 2
                if extraSliceEstimate >= 2 * 1024 * 1024 {
                    items.append(ScanItem(
                        name: app.replacingOccurrences(of: ".app", with: ""),
                        path: binPath,
                        sizeBytes: extraSliceEstimate,
                        subtitle: "Universal Binary (arm64 + x86_64)",
                        categoryID: "systemJunk",
                        groupTitle: "Universal Binaries",
                        isSelected: false,
                        isProtected: true,
                        protectionReason: "Stripping slices invalidates notarized app signatures.",
                        badge: "Universal"
                    ))
                }
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func scanIOSBackups(settings: RCleanerSettings) -> [ScanItem] {
        let fm = FileManager.default
        let root = FileSystemHelpers.expand("~/Library/Application Support/MobileSync/Backup")
        guard let dirs = try? fm.contentsOfDirectory(atPath: root) else { return [] }

        var raw: [(name: String, deviceID: String, path: String, size: Int64, date: Date, subtitle: String)] = []
        for dir in dirs where !dir.hasPrefix(".") {
            let full = (root as NSString).appendingPathComponent(dir)
            if FileSystemHelpers.isIgnored(path: full, category: .systemJunk, settings: settings) { continue }
            let infoPlist = "\(full)/Info.plist"
            var deviceName = dir
            var deviceID = dir
            var iosVer = ""
            var lastBackup = (try? URL(fileURLWithPath: full).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

            if let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlist)),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                if let n = dict["Device Name"] as? String { deviceName = n }
                if let uid = dict["Unique Identifier"] as? String { deviceID = uid }
                if let v = dict["Product Version"] as? String { iosVer = "iOS \(v)" }
                if let d = dict["Last Backup Date"] as? Date { lastBackup = d }
            }
            let sz = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: full), maxFiles: 15_000)
            if sz > 1024 * 1024 {
                raw.append((deviceName, deviceID, full, sz, lastBackup, iosVer.isEmpty ? "iOS Backup" : iosVer))
            }
        }

        // Determine latest backup per device ID
        var latestByDevice: [String: Date] = [:]
        for item in raw {
            if let existing = latestByDevice[item.deviceID] {
                if item.date > existing { latestByDevice[item.deviceID] = item.date }
            } else {
                latestByDevice[item.deviceID] = item.date
            }
        }

        return raw.sorted { $0.size > $1.size }.map { item in
            let isLatest = latestByDevice[item.deviceID] == item.date
            return ScanItem(
                name: item.name,
                path: item.path,
                sizeBytes: item.size,
                subtitle: item.subtitle,
                categoryID: "systemJunk",
                groupTitle: "iOS Device Backups",
                isSelected: !isLatest,
                lastModified: item.date,
                badge: isLatest ? "Latest" : nil
            )
        }
    }

    // MARK: - 2. Mail Attachments

    private func scanMailAttachments(settings: RCleanerSettings) -> ScanCategory {
        var items: [ScanItem] = []
        let mailDownloadDirs = [
            FileSystemHelpers.expand("~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
            FileSystemHelpers.expand("~/Library/Mail Downloads")
        ]

        for dir in mailDownloadDirs {
            items.append(contentsOf: scanDirectChildren(
                in: dir,
                categoryID: "mailAttachments",
                groupTitle: "Mail Downloads",
                ignoreCategory: .mailAttachments,
                settings: settings,
                minSizeBytes: 1024
            ))
        }

        let groups = items.isEmpty ? [] : [
            ScanGroup(
                id: "mailDownloads",
                title: "Mail Downloads",
                description: "Local copies of email attachments stored by Apple Mail that remain available on your mail server.",
                iconName: "paperclip",
                items: items
            )
        ]

        return ScanCategory(
            id: "mailAttachments",
            title: "Mail Attachments",
            description: "Locally cached copies of email attachments that remain accessible online.",
            iconName: "envelope.open.fill",
            groups: groups
        )
    }

    // MARK: - 3. Trash Bins (System + Mail Trashes + Mounted Volumes)

    private func scanTrashBins(settings: RCleanerSettings) -> ScanCategory {
        var groups: [ScanGroup] = []

        let rootTrash = scanDirectChildren(
            in: FileSystemHelpers.expand("~/.Trash"),
            categoryID: "trashBins",
            groupTitle: "System Trash",
            ignoreCategory: .systemJunk,
            settings: settings,
            minSizeBytes: 1
        )
        if !rootTrash.isEmpty {
            groups.append(ScanGroup(
                id: "systemTrash",
                title: "Macintosh HD Trash",
                description: "Items previously deleted to your Trash that still consume disk space.",
                iconName: "trash.fill",
                items: rootTrash
            ))
        }

        // Mail Trashes (~/Library/Mail/V*/**/Deleted Messages.mbox)
        let mailRoot = FileSystemHelpers.expand("~/Library/Mail")
        if FileManager.default.fileExists(atPath: mailRoot) {
            let findRes = FileSystemHelpers.runProcess("/usr/bin/find", arguments: [mailRoot, "-maxdepth", "4", "-type", "d", "(", "-name", "Deleted Messages.mbox", "-o", "-name", "Trash.mbox", ")"], timeout: 5)
            let trashMboxes = findRes.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            var mailTrashItems: [ScanItem] = []
            for mbox in trashMboxes {
                let sz = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: mbox), maxFiles: 2000)
                if sz > 16 * 1024 {
                    mailTrashItems.append(ScanItem(
                        name: URL(fileURLWithPath: mbox).lastPathComponent,
                        path: mbox,
                        sizeBytes: sz,
                        subtitle: "Apple Mail Trash folder",
                        categoryID: "trashBins",
                        groupTitle: "Mail Trashes",
                        isSelected: false
                    ))
                }
            }
            if !mailTrashItems.isEmpty {
                groups.append(ScanGroup(
                    id: "mailTrashes",
                    title: "Mail Trashes",
                    description: "Deleted emails still stored locally inside Apple Mail Trash folders.",
                    iconName: "envelope.badge.minus",
                    items: mailTrashItems
                ))
            }
        }

        // External mounted volumes .Trashes
        if let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey], options: [.skipHiddenVolumes]) {
            var extItems: [ScanItem] = []
            for vol in mounted where vol.path != "/" && !vol.path.hasPrefix("/System") {
                let trashPath = vol.appendingPathComponent(".Trashes").path
                let found = scanDirectChildren(
                    in: trashPath,
                    categoryID: "trashBins",
                    groupTitle: "Mounted Trash Bins",
                    ignoreCategory: .systemJunk,
                    settings: settings,
                    minSizeBytes: 1
                )
                extItems.append(contentsOf: found)
            }
            if !extItems.isEmpty {
                groups.append(ScanGroup(
                    id: "mountedTrashes",
                    title: "Mounted Trash Bins",
                    description: "Trash folders located on external drives.",
                    iconName: "externaldrive.badge.minus",
                    items: extItems
                ))
            }
        }

        return ScanCategory(
            id: "trashBins",
            title: "Trash Bins",
            description: "Empty all available Trash Bins on your Mac, Apple Mail, and connected drives.",
            iconName: "trash.circle.fill",
            groups: groups
        )
    }

    // MARK: - 4. AI Clutter & Local Models

    private func scanAIClutter(settings: RCleanerSettings) -> ScanCategory {
        var groups: [ScanGroup] = []
        let fm = FileManager.default

        let aiJunkSpecs: [(tool: String, kind: String, relPath: String)] = [
            ("Claude", "Temp Files", "~/.claude/shell-snapshots"),
            ("Claude", "Logs", "~/.claude/telemetry"),
            ("Claude", "Caches", "~/.claude/stats-cache.json"),
            ("Claude", "Caches", "~/.claude/mcp-needs-auth-cache.json"),
            ("Claude", "Caches", "~/.claude/plugins/install-counts-cache.json"),
            ("Claude", "Logs", "~/Library/Logs/Claude"),
            ("Claude", "Caches", "~/Library/Application Support/Claude/Cache"),
            ("Claude", "Caches", "~/Library/Application Support/Claude/Code Cache"),
            ("Claude", "Caches", "~/Library/Application Support/Claude/GPUCache"),
            ("Claude", "Caches", "~/Library/Application Support/Claude/DawnGraphiteCache"),
            ("Claude", "Caches", "~/Library/Application Support/Claude/Service Worker/CacheStorage"),
            ("Codex", "Caches", "~/.codex/cache/codex_apps_server_info"),
            ("Codex", "Caches", "~/.codex/cache/codex_apps_tools"),
            ("Codex", "Caches", "~/.codex/cache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/Default/Cache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/Default/Code Cache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/Default/GPUCache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/Default/DawnGraphiteCache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/Default/DawnWebGPUCache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/Default/Service Worker/CacheStorage"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/GraphiteDawnCache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/component_crx_cache"),
            ("Gemini / Antigravity", "Caches", "~/.gemini/antigravity-browser-profile/extensions_crx_cache"),
            ("Cursor", "Caches", "~/Library/Application Support/Cursor/Cache"),
            ("Cursor", "Caches", "~/Library/Application Support/Cursor/CachedData"),
            ("Cursor", "Caches", "~/Library/Application Support/Cursor/Code Cache"),
            ("Cursor", "Caches", "~/Library/Application Support/Cursor/GPUCache"),
            ("Cursor", "Logs", "~/Library/Application Support/Cursor/logs"),
            ("OpenCode", "Logs", "~/.local/share/opencode/log"),
            ("Chrome DevTools MCP", "Caches", "~/.cache/chrome-devtools-mcp/chrome-profile/Default/Cache"),
            ("Chrome DevTools MCP", "Caches", "~/.cache/chrome-devtools-mcp/chrome-profile/Default/GPUCache"),
            ("Chrome DevTools MCP", "Caches", "~/.cache/chrome-devtools-mcp/chrome-profile/Default/Service Worker/CacheStorage")
        ]

        var aiJunkItems: [ScanItem] = []
        var seenAI = Set<String>()
        for spec in aiJunkSpecs {
            let full = FileSystemHelpers.expand(spec.relPath)
            guard seenAI.insert(full).inserted, fm.fileExists(atPath: full) else { continue }
            if FileSystemHelpers.isIgnored(path: full, category: .aiClutter, settings: settings) { continue }
            let size = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
            guard size > 4096 else { continue }
            aiJunkItems.append(ScanItem(
                name: "\(spec.tool) — \(URL(fileURLWithPath: full).lastPathComponent)",
                path: full,
                sizeBytes: size,
                subtitle: "\(spec.tool) • \(spec.kind)",
                categoryID: "aiClutter",
                groupTitle: "AI Junk Files",
                isSelected: true,
                badge: spec.kind
            ))
        }

        // Stale Claude CLI versions (~/.local/share/claude/versions)
        let claudeVersDir = FileSystemHelpers.expand("~/.local/share/claude/versions")
        if let versions = try? fm.contentsOfDirectory(atPath: claudeVersDir), versions.count > 1 {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for stale in sorted.dropFirst() {
                let full = "\(claudeVersDir)/\(stale)"
                let sz = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                if sz > 1024 {
                    aiJunkItems.append(ScanItem(
                        name: "Claude CLI (Stale v\(stale))",
                        path: full,
                        sizeBytes: sz,
                        subtitle: "Claude • Stale Version",
                        categoryID: "aiClutter",
                        groupTitle: "AI Junk Files",
                        isSelected: true,
                        badge: "Stale Version"
                    ))
                }
            }
        }

        if !aiJunkItems.isEmpty {
            groups.append(ScanGroup(
                id: "aiJunkFiles",
                title: "AI Junk Files",
                description: "Caches, logs, stale versions, and temporary files created by AI tools such as Claude, Codex, Gemini, Cursor, and OpenCode.",
                iconName: "cpu.fill",
                items: aiJunkItems.sorted { $0.sizeBytes > $1.sizeBytes }
            ))
        }

        // Local Models: Real Ollama Manifest Parser + LM Studio + HuggingFace
        var modelItems: [ScanItem] = []
        modelItems.append(contentsOf: scanOllamaModels(settings: settings))

        let otherModelRoots: [(engine: String, path: String)] = [
            ("LM Studio", "~/.lmstudio/models"),
            ("LM Studio", "~/.cache/lm-studio/models"),
            ("HuggingFace", "~/.cache/huggingface/hub")
        ]
        let totalRAMBytes = Int64(ProcessInfo.processInfo.physicalMemory)
        for (engine, rawPath) in otherModelRoots {
            let fullRoot = FileSystemHelpers.expand(rawPath)
            guard fm.fileExists(atPath: fullRoot) else { continue }
            let entries = scanDirectChildren(
                in: fullRoot,
                categoryID: "aiClutter",
                groupTitle: "Local Models",
                ignoreCategory: .aiClutter,
                settings: settings,
                minSizeBytes: 5 * 1024 * 1024,
                defaultSelected: false,
                subtitleOverride: "\(engine) Local Model"
            ).map { item -> ScanItem in
                var copy = item
                let fitsRAM = Double(item.sizeBytes) * 1.2 < Double(totalRAMBytes)
                copy.badge = fitsRAM ? engine : "Exceeds RAM"
                return copy
            }
            modelItems.append(contentsOf: entries)
        }

        if !modelItems.isEmpty {
            groups.append(ScanGroup(
                id: "localModels",
                title: "Local Models",
                description: "Models downloaded with Ollama, LM Studio, and HuggingFace. Unselected by default to protect active projects.",
                iconName: "brain.head.profile",
                items: modelItems.sorted { $0.sizeBytes > $1.sizeBytes }
            ))
        }

        return ScanCategory(
            id: "aiClutter",
            title: "AI Clutter",
            description: "Temporary files, caches, stale versions, and downloaded local models from AI apps.",
            iconName: "wand.and.rays",
            badge: "New",
            groups: groups
        )
    }

    /// Parses `~/.ollama/models/manifests` to resolve exact human-readable model names (`llama3:latest`), blob digests, and RAM compatibility.
    private func scanOllamaModels(settings: RCleanerSettings) -> [ScanItem] {
        let fm = FileManager.default
        let manifestsRoot = FileSystemHelpers.expand("~/.ollama/models/manifests")
        let blobsRoot = FileSystemHelpers.expand("~/.ollama/models/blobs")
        guard fm.fileExists(atPath: manifestsRoot) else { return [] }

        let totalRAM = Int64(ProcessInfo.processInfo.physicalMemory)
        var models: [ScanItem] = []

        guard let en = fm.enumerator(at: URL(fileURLWithPath: manifestsRoot), includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        for case let fileURL as URL in en {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let layers = json["layers"] as? [[String: Any]] else { continue }

            let tag = fileURL.lastPathComponent
            let modelName = fileURL.deletingLastPathComponent().lastPathComponent
            let displayName = "\(modelName):\(tag)"
            if FileSystemHelpers.isIgnored(path: fileURL.path, category: .aiClutter, settings: settings) { continue }

            var totalBytes: Int64 = 0
            var blobPaths: [String] = []
            for layer in layers {
                if let digest = layer["digest"] as? String {
                    let blobName = digest.replacingOccurrences(of: ":", with: "-")
                    let blobPath = "\(blobsRoot)/\(blobName)"
                    if fm.fileExists(atPath: blobPath) {
                        blobPaths.append(blobPath)
                    }
                }
                if let size = layer["size"] as? Int64 {
                    totalBytes += size
                } else if let sizeNum = layer["size"] as? NSNumber {
                    totalBytes += sizeNum.int64Value
                }
            }

            let fitsRAM = Double(totalBytes) * 1.2 < Double(totalRAM)
            let ramNote = fitsRAM ? "Runs on your Mac" : "Too large for RAM"
            models.append(ScanItem(
                name: displayName,
                path: fileURL.path,
                sizeBytes: totalBytes,
                subtitle: "Ollama • \(blobPaths.count) blobs • \(ramNote)",
                categoryID: "aiClutter",
                groupTitle: "Local Models",
                isSelected: false,
                badge: fitsRAM ? "Ollama" : "Exceeds RAM",
                metadata: ["ollamaBlobs": blobPaths.joined(separator: "\n")]
            ))
        }
        return models
    }

    // MARK: - Cleaning Execution

    public func cleanSelected(
        categories: [ScanCategory],
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> CleanupSummary {
        let selected = categories.flatMap(\.groups).flatMap(\.items).filter { $0.isSelected && !$0.isProtected }
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var succeeded = 0
        var failed = 0
        var removedBrokenPrefs = false

        for (index, item) in selected.enumerated() {
            let pct = Double(index + 1) / Double(max(1, selected.count))
            progress("Cleaning \(item.name)...", pct)

            // If this is an Ollama model manifest, remove both the manifest and its exclusive blobs
            if let blobsStr = item.metadata["ollamaBlobs"], !blobsStr.isEmpty {
                let blobs = blobsStr.split(separator: "\n").map(String.init)
                var allOK = true
                for b in blobs {
                    let r = FileSystemHelpers.safeRemoveItem(at: b, moveToTrash: false)
                    if !r.success { allOK = false }
                }
                let mRes = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: false)
                if mRes.success && allOK {
                    freed += item.sizeBytes
                    succeeded += 1
                    logs.append(CleanupLogEntry(moduleName: "Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
                } else {
                    failed += 1
                    logs.append(CleanupLogEntry(moduleName: "Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: mRes.error))
                }
                continue
            }

            let isTrashOrCache = item.categoryID == "trashBins" || item.path.contains("/Library/Caches/")
            let result = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: !isTrashOrCache)
            if result.success {
                if item.groupTitle == "Broken Preferences" { removedBrokenPrefs = true }
                freed += item.sizeBytes
                succeeded += 1
                logs.append(CleanupLogEntry(
                    moduleName: "Cleanup",
                    itemName: item.name,
                    path: item.path,
                    sizeBytes: item.sizeBytes,
                    status: .cleaned
                ))
            } else {
                failed += 1
                logs.append(CleanupLogEntry(
                    moduleName: "Cleanup",
                    itemName: item.name,
                    path: item.path,
                    sizeBytes: item.sizeBytes,
                    status: .failed,
                    errorMessage: result.error
                ))
            }
        }

        // Flush cfprefsd if broken preference files were removed
        if removedBrokenPrefs {
            _ = FileSystemHelpers.runProcess("/usr/bin/killall", arguments: ["cfprefsd"], timeout: 4)
        }

        return CleanupSummary(
            bytesFreed: freed,
            itemsProcessed: succeeded,
            itemsFailed: failed,
            logEntries: logs,
            title: succeeded > 0 ? "Cleanup complete!" : "Cleanup failed...",
            subtitle: "successfully cleaned"
        )
    }

    // MARK: - Helpers

    private func scanDirectChildren(
        in dirPath: String,
        categoryID: String,
        groupTitle: String,
        ignoreCategory: IgnoreListCategory,
        settings: RCleanerSettings,
        minSizeBytes: Int64,
        defaultSelected: Bool = true,
        subtitleOverride: String? = nil
    ) -> [ScanItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }
        var result: [ScanItem] = []

        for name in names {
            if name == ".DS_Store" || name == ".localized" { continue }
            if name.lowercased().contains("r-cleaner") || name.lowercased().contains("rcleaner") { continue }
            let full = (dirPath as NSString).appendingPathComponent(name)
            if FileSystemHelpers.isProtectedSystemPath(full) { continue }
            if FileSystemHelpers.isIgnored(path: full, category: ignoreCategory, settings: settings) { continue }

            let url = URL(fileURLWithPath: full)
            let size = FileSystemHelpers.fileSize(at: url)
            guard size >= minSizeBytes else { continue }

            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
            result.append(ScanItem(
                name: name,
                path: full,
                sizeBytes: size,
                subtitle: subtitleOverride ?? full,
                categoryID: categoryID,
                groupTitle: groupTitle,
                isSelected: defaultSelected,
                lastModified: vals?.contentModificationDate,
                lastAccessed: vals?.contentAccessDate
            ))
        }
        return result.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
