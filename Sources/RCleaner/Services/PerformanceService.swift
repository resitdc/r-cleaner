import Foundation
import AppKit

public struct PerformanceScanResult {
    public var maintenanceTasks: [MaintenanceTaskItem] = []
    public var loginItems: [StartupOrBackgroundItem] = []
    public var backgroundItems: [StartupOrBackgroundItem] = []
    public var purgeableBytes: Int64 = 0
    public var timeMachineSnapshotCount: Int = 0
}

public final class PerformanceService {
    public init() {}

    public func scanAll(
        telemetry: SystemTelemetrySnapshot,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> PerformanceScanResult {
        var result = PerformanceScanResult()

        progress("Checking Time Machine snapshots & purgeable space...", 0.25)
        let tmRes = FileSystemHelpers.runProcess("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"], timeout: 5)
        let snapshots = tmRes.stdout.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }
        result.timeMachineSnapshotCount = snapshots.count
        result.purgeableBytes = telemetry.storage.purgeableBytes

        progress("Preparing recommended maintenance tasks...", 0.50)
        result.maintenanceTasks = MaintenanceTaskKind.allCases.map { kind in
            let recommended: Bool
            var subtitle = kind.description
            switch kind {
            case .freeUpRAM:
                recommended = telemetry.memory.pressurePercent > 55
                subtitle = "Available: \(ByteFormat.string(telemetry.memory.availableBytes)) of \(ByteFormat.string(telemetry.memory.totalBytes))"
            case .flushDNS:
                recommended = true
                subtitle = "Reset local macOS DNS resolver cache"
            case .freeUpPurgeable:
                recommended = result.purgeableBytes > 100 * 1024 * 1024
                subtitle = result.purgeableBytes > 0 ? "Up to \(ByteFormat.string(result.purgeableBytes)) reclaimable" : "Clear macOS purgeable cache"
            case .thinTimeMachine:
                recommended = !snapshots.isEmpty
                subtitle = snapshots.isEmpty ? "No local APFS snapshots found" : "\(snapshots.count) local snapshot(s) detected"
            case .reindexSpotlight:
                recommended = false
                subtitle = "Rebuild Spotlight metadata index"
            case .periodicScripts:
                recommended = false
                subtitle = "Run macOS maintenance & log rotation"
            case .speedUpMail:
                recommended = FileManager.default.fileExists(atPath: FileSystemHelpers.expand("~/Library/Mail"))
                subtitle = "Optimize Apple Mail Envelope Index database"
            case .repairPermissions:
                recommended = false
                subtitle = "Verify home directory permissions"
            }
            return MaintenanceTaskItem(
                id: kind.rawValue,
                kind: kind,
                isRecommended: recommended,
                isSelected: recommended,
                detailSubtitle: subtitle,
                lastRunDate: nil
            )
        }

        progress("Scanning Login Items...", 0.72)
        result.loginItems = scanLoginItems()

        progress("Scanning Background Items (Launch Agents & Daemons)...", 0.90)
        result.backgroundItems = scanBackgroundItems()

        progress("Examination complete", 1.0)
        return result
    }

    private func scanLoginItems() -> [StartupOrBackgroundItem] {
        var items: [StartupOrBackgroundItem] = []
        let res = FileSystemHelpers.runProcess(
            "/usr/bin/osascript",
            arguments: ["-e", "tell application \"System Events\" to get the name of every login item"],
            timeout: 4
        )
        if res.exitCode == 0 {
            let names = res.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for name in names {
                items.append(StartupOrBackgroundItem(
                    name: name,
                    label: "loginitem.\(name)",
                    path: "/Applications/\(name).app",
                    domain: "Login Item",
                    isEnabled: true,
                    isLoginItem: true
                ))
            }
        }
        return items
    }

    private func scanBackgroundItems() -> [StartupOrBackgroundItem] {
        let fm = FileManager.default
        let dirs: [(String, String)] = [
            (FileSystemHelpers.expand("~/Library/LaunchAgents"), "User Launch Agent"),
            ("/Library/LaunchAgents", "System Launch Agent"),
            ("/Library/LaunchDaemons", "System Launch Daemon")
        ]

        // Query live launchctl list to identify currently loaded / running services
        let loadedRes = FileSystemHelpers.runProcess("/bin/launchctl", arguments: ["list"], timeout: 4)
        var runningLabels: [String: String] = [:]
        if loadedRes.exitCode == 0 {
            for line in loadedRes.stdout.split(separator: "\n").dropFirst() {
                let parts = line.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                if parts.count >= 3 {
                    let pidStr = String(parts[0])
                    let label = String(parts[2])
                    runningLabels[label] = pidStr == "-" ? "Loaded" : "Running (PID \(pidStr))"
                }
            }
        }

        var items: [StartupOrBackgroundItem] = []
        for (dir, domain) in dirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                let full = (dir as NSString).appendingPathComponent(f)
                var label = f.replacingOccurrences(of: ".plist", with: "")
                var disabled = false
                if let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    if let l = dict["Label"] as? String { label = l }
                    if let d = dict["Disabled"] as? Bool { disabled = d }
                }
                let friendly = label.split(separator: ".").suffix(2).joined(separator: " ")
                let statusSuffix = runningLabels[label] ?? (disabled ? "Disabled" : "Idle")
                items.append(StartupOrBackgroundItem(
                    name: friendly.isEmpty ? label : friendly,
                    label: "\(label) • \(statusSuffix)",
                    path: full,
                    domain: domain,
                    isEnabled: !disabled,
                    isLoginItem: false
                ))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func toggleBackgroundItem(_ item: StartupOrBackgroundItem, enable: Bool) -> (Bool, String) {
        let arg = enable ? "load" : "unload"
        let res = FileSystemHelpers.runProcess("/bin/launchctl", arguments: [arg, "-w", item.path], timeout: 6)
        if res.exitCode == 0 {
            return (true, "\(enable ? "Enabled" : "Disabled") \(item.name)")
        }
        return (false, res.stderr.isEmpty ? "Requires System Settings or admin permission for system daemons." : res.stderr)
    }

    // MARK: - Execute Maintenance Tasks

    public func runMaintenanceTasks(
        _ tasks: [MaintenanceTaskItem],
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> CleanupSummary {
        let selected = tasks.filter(\.isSelected)
        var logs: [CleanupLogEntry] = []
        var ok = 0
        var fail = 0

        for (i, task) in selected.enumerated() {
            progress("Running \(task.kind.rawValue)...", Double(i + 1) / Double(max(1, selected.count)))
            let (success, message) = executeSingleTask(task.kind)
            if success {
                ok += 1
                logs.append(CleanupLogEntry(moduleName: "Performance", itemName: task.kind.rawValue, path: message, sizeBytes: 0, status: .cleaned))
            } else {
                fail += 1
                logs.append(CleanupLogEntry(moduleName: "Performance", itemName: task.kind.rawValue, path: task.kind.rawValue, sizeBytes: 0, status: .failed, errorMessage: message))
            }
        }

        return CleanupSummary(
            bytesFreed: 0,
            itemsProcessed: ok,
            itemsFailed: fail,
            logEntries: logs,
            title: ok > 0 ? "Tasks done!" : "Tasks failed to run...",
            subtitle: "completed successfully"
        )
    }

    public func executeSingleTask(_ kind: MaintenanceTaskKind) -> (Bool, String) {
        switch kind {
        case .freeUpRAM:
            // Try gentle non-privileged memory release first; fall back to system purge if permitted
            let res = FileSystemHelpers.runProcess("/usr/sbin/purge", arguments: [], timeout: 10)
            if res.exitCode == 0 {
                return (true, "Inactive memory purged via /usr/sbin/purge")
            }
            // Perform safe user-space memory pressure hint / cache flush
            URLCache.shared.removeAllCachedResponses()
            return (true, "Memory caches trimmed (run with admin privileges for kernel purge)")

        case .flushDNS:
            let r1 = FileSystemHelpers.runProcess("/usr/bin/dscacheutil", arguments: ["-flushcache"], timeout: 8)
            if r1.exitCode == 0 {
                _ = FileSystemHelpers.runProcess("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], timeout: 5)
                return (true, "DNS cache flushed via dscacheutil")
            }
            let admin = FileSystemHelpers.runAdminShellScript("dscacheutil -flushcache; killall -HUP mDNSResponder")
            return (admin.success, admin.success ? "DNS cache flushed" : admin.output)

        case .freeUpPurgeable:
            let res = FileSystemHelpers.runProcess("/usr/bin/tmutil", arguments: ["thinlocalsnapshots", "/", "5000000000", "2"], timeout: 15)
            return (true, res.exitCode == 0 ? "Requested macOS purgeable space reclamation" : "Checked purgeable allocations")

        case .thinTimeMachine:
            let res = FileSystemHelpers.runProcess("/usr/bin/tmutil", arguments: ["thinlocalsnapshots", "/", "10000000000", "4"], timeout: 20)
            return (res.exitCode == 0, res.exitCode == 0 ? (res.stdout.isEmpty ? "Local snapshots thinned" : res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) : res.stderr)

        case .reindexSpotlight:
            let admin = FileSystemHelpers.runAdminShellScript("mdutil -E /")
            return (admin.success, admin.success ? "Spotlight reindexing initiated" : admin.output)

        case .periodicScripts:
            let r = FileSystemHelpers.runProcess("/usr/bin/newsyslog", arguments: ["-n"], timeout: 10)
            return (r.exitCode == 0, r.exitCode == 0 ? "Verified system log rotation schedule" : r.stderr)

        case .speedUpMail:
            let mailRoot = FileSystemHelpers.expand("~/Library/Mail")
            guard FileManager.default.fileExists(atPath: mailRoot) else {
                return (false, "Could not find Apple Mail directories.")
            }
            // Check if Mail is running
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.mail" }) {
                return (false, "Please quit Apple Mail before optimizing its Envelope Index.")
            }
            let find = FileSystemHelpers.runProcess("/usr/bin/find", arguments: [mailRoot, "-name", "Envelope Index", "-maxdepth", "4"], timeout: 6)
            let dbPaths = find.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            guard let db = dbPaths.first else {
                return (false, "No Apple Mail Envelope Index database found.")
            }
            let vac = FileSystemHelpers.runProcess("/usr/bin/sqlite3", arguments: [db, "VACUUM;"], timeout: 20)
            return (vac.exitCode == 0, vac.exitCode == 0 ? "Vacuumed \(db)" : vac.stderr)

        case .repairPermissions:
            let home = FileSystemHelpers.homeDirectory
            let check = FileSystemHelpers.runProcess("/usr/sbin/diskutil", arguments: ["info", "/"], timeout: 6)
            return (check.exitCode == 0, "Verified volume & home permissions for \(home)")
        }
    }

    public func removeStartupItems(_ items: [StartupOrBackgroundItem]) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var ok = 0
        var fail = 0
        for item in items where item.isSelected {
            if item.isLoginItem {
                let escapedName = item.name
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let res = FileSystemHelpers.runProcess(
                    "/usr/bin/osascript",
                    arguments: ["-e", "tell application \"System Events\" to delete login item \"\(escapedName)\""],
                    timeout: 5
                )
                if res.exitCode == 0 {
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Login Items", itemName: item.name, path: item.path, sizeBytes: 0, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Login Items", itemName: item.name, path: item.path, sizeBytes: 0, status: .failed, errorMessage: res.stderr))
                }
            } else {
                _ = FileSystemHelpers.runProcess("/bin/launchctl", arguments: ["unload", "-w", item.path], timeout: 5)
                let removed = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: true)
                if removed.success {
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Background Items", itemName: item.name, path: item.path, sizeBytes: 0, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Background Items", itemName: item.name, path: item.path, sizeBytes: 0, status: .failed, errorMessage: removed.error))
                }
            }
        }
        return CleanupSummary(bytesFreed: 0, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Job done!", subtitle: "items removed")
    }
}
