import Foundation
import AppKit
import Darwin

/// Process Pulse & App Cryo-Freezer Engine:
/// 1. Suspends heavy macOS apps/processes to 0% CPU in kernel space via `SIGSTOP` without closing their windows,
///    and resumes them instantaneously via `SIGCONT`.
/// 2. Tracks rolling per-PID resident memory (`RSS`) history across snapshots to detect live memory growth / leaks.
/// 3. Enforces strict safety guards so system daemons, WindowServer, Finder, Dock, Audio, and R-Cleaner are never frozen.
public final class CryoFreezerService: @unchecked Sendable {
    private let lock = NSLock()
    private var memoryHistoryByPID: [Int32: [Int64]] = [:]
    private var sessionFrozenPIDs: Set<Int32> = []
    private let maxHistorySamples = 14

    /// Critical macOS UI, kernel, audio, and terminal processes that must never be cryo-frozen.
    public static let protectedProcessNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "Finder", "Dock", "SystemUIServer",
        "ControlCenter", "loginwindow", "coreaudiod", "bluetoothd", "cfprefsd",
        "UserEventAgent", "NotificationCenter", "Spotlight", "WallpaperAgent",
        "R-Cleaner", "RCleaner", "Terminal", "iTerm2", "Warp", "Ghostty", "Alacritty",
        "securityd", "trustd", " opendirectoryd", "mds", "mds_stores", "distnoted",
        "hidd", "powerd", "logd", "configd", "WiFiAgent", "audiomxd"
    ]

    public init() {}

    // MARK: - Live Process Pulse & Thermal / Cryo Discovery

    public func scanProcesses() -> CryoFreezerSnapshot {
        let guiAppsByPID = Self.fetchRunningGUIApps()
        let psRes = FileSystemHelpers.runProcess(
            "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,stat=,%cpu=,rss=,etime=,comm="],
            timeout: 3
        )
        guard psRes.exitCode == 0 else {
            return CryoFreezerSnapshot()
        }

        let rawRows = Self.parsePsTable(psRes.stdout)
        let selfPID = getpid()

        lock.lock()
        var currentPIDSet = Set<Int32>()
        var items: [CryoProcessItem] = []
        items.reserveCapacity(min(60, rawRows.count))

        let ignoredCLITools: Set<String> = ["ps", "lsof", "git", "sh", "zsh", "bash", "sed", "awk", "grep", "top", "nettop"]

        for row in rawRows {
            // Exclude R-Cleaner itself so its own transient scan thread isn't listed as a freeze target
            guard row.pid != selfPID else { continue }
            let rawExecName = (row.executablePath as NSString).lastPathComponent
            if ignoredCLITools.contains(rawExecName) { continue }

            currentPIDSet.insert(row.pid)
            let guiInfo = guiAppsByPID[row.pid]
            let isFrozen = row.stat.uppercased().hasPrefix("T") || sessionFrozenPIDs.contains(row.pid)
            if !row.stat.uppercased().hasPrefix("T") && sessionFrozenPIDs.contains(row.pid) {
                sessionFrozenPIDs.remove(row.pid)
            }

            let isGUI = guiInfo != nil || row.executablePath.contains(".app/Contents/MacOS/")
            let memBytes = row.rssKB * 1024

            // Keep processes that are currently frozen, GUI apps with >= 45 MB RAM, or processes using >= 2% CPU / >= 120 MB RAM
            let isSignificant = isFrozen
                || (isGUI && memBytes >= 45 * 1_048_576)
                || row.cpuPercent >= 2.0
                || memBytes >= 120 * 1_048_576
            guard isSignificant else { continue }

            // Skip root/system background daemons under /System/Library or /usr/libexec unless they are GUI apps
            if !isGUI && !isFrozen {
                if row.executablePath.hasPrefix("/System/Library/")
                    || row.executablePath.hasPrefix("/usr/libexec/")
                    || row.executablePath.hasPrefix("/usr/sbin/")
                    || row.executablePath.hasPrefix("/sbin/") {
                    continue
                }
            }

            // Update rolling memory history for this PID
            var hist = memoryHistoryByPID[row.pid] ?? []
            hist.append(memBytes)
            if hist.count > maxHistorySamples {
                hist.removeFirst(hist.count - maxHistorySamples)
            }
            memoryHistoryByPID[row.pid] = hist

            let (deltaBytes, isGrowing) = Self.evaluateMemoryGrowth(history: hist, currentBytes: memBytes)
            let resolvedBundle = guiInfo ?? Self.resolveAppBundle(fromExecutablePath: row.executablePath)
            let procShortName = resolvedBundle?.name ?? (row.executablePath as NSString).lastPathComponent

            let isProtected = Self.isProtectedProcess(
                pid: row.pid,
                selfPID: selfPID,
                processName: procShortName,
                executablePath: row.executablePath,
                bundleIdentifier: guiInfo?.bundleID
            )

            let effectiveCPU = isFrozen ? 0.0 : row.cpuPercent
            let thermal = Self.classifyThermalState(
                isFrozen: isFrozen,
                cpuPercent: effectiveCPU,
                memoryBytes: memBytes,
                isMemoryGrowing: isGrowing
            )

            items.append(CryoProcessItem(
                pid: row.pid,
                ppid: row.ppid,
                name: (row.executablePath as NSString).lastPathComponent,
                bundleName: resolvedBundle?.name,
                bundlePath: resolvedBundle?.bundlePath,
                executablePath: row.executablePath,
                stateCode: row.stat,
                isFrozen: isFrozen,
                isGUIApp: isGUI,
                cpuPercent: effectiveCPU,
                memoryBytes: memBytes,
                memoryHistory: hist,
                memoryDeltaBytes: deltaBytes,
                isMemoryGrowing: isGrowing,
                uptimeLabel: row.etime,
                thermalState: thermal,
                isSystemProtected: isProtected
            ))
        }

        // Prune dead PIDs from history
        memoryHistoryByPID = memoryHistoryByPID.filter { currentPIDSet.contains($0.key) }
        sessionFrozenPIDs = sessionFrozenPIDs.intersection(currentPIDSet)
        lock.unlock()

        // Sort: Frozen first, then Overheating, then Warm, then by CPU + RAM score descending
        items.sort { a, b in
            if a.isFrozen != b.isFrozen { return a.isFrozen && !b.isFrozen }
            let rankA = Self.thermalSortRank(a.thermalState)
            let rankB = Self.thermalSortRank(b.thermalState)
            if rankA != rankB { return rankA < rankB }
            if a.isSystemProtected != b.isSystemProtected { return !a.isSystemProtected }
            let scoreA = a.cpuPercent * 18.0 + (Double(a.memoryBytes) / 10_485_760.0)
            let scoreB = b.cpuPercent * 18.0 + (Double(b.memoryBytes) / 10_485_760.0)
            return scoreA > scoreB
        }

        // Deduplicate repetitive Electron "Helper" worker clones so one app doesn't flood the grid with 6 identical cards
        var deduplicated: [CryoProcessItem] = []
        var seenHelperTitles = Set<String>()
        for item in items {
            if !item.isFrozen && item.displayTitle.contains("Helper") {
                if !seenHelperTitles.insert(item.displayTitle).inserted {
                    continue
                }
            }
            deduplicated.append(item)
        }

        malloc_zone_pressure_relief(nil, 0)
        return CryoFreezerSnapshot(items: Array(deduplicated.prefix(24)), lastUpdated: Date())
    }

    private static func thermalSortRank(_ state: CryoThermalState) -> Int {
        switch state {
        case .frozen: return 0
        case .overheating: return 1
        case .warm: return 2
        case .cool: return 3
        }
    }

    public static func classifyThermalState(
        isFrozen: Bool,
        cpuPercent: Double,
        memoryBytes: Int64,
        isMemoryGrowing: Bool
    ) -> CryoThermalState {
        if isFrozen {
            return .frozen
        }
        let memMB = Double(memoryBytes) / 1_048_576.0
        if cpuPercent >= 22.0 || (cpuPercent >= 10.0 && memMB >= 900.0) || (isMemoryGrowing && memMB >= 500.0) {
            return .overheating
        }
        if cpuPercent >= 4.5 || memMB >= 420.0 || isMemoryGrowing {
            return .warm
        }
        return .cool
    }

    /// Evaluates rolling memory samples to detect steady upward memory growth (>= +12 MB increase).
    public static func evaluateMemoryGrowth(history: [Int64], currentBytes: Int64) -> (deltaBytes: Int64, isGrowing: Bool) {
        guard let first = history.first, history.count >= 2 else {
            return (0, false)
        }
        let delta = currentBytes - first
        // Flag as actively growing if memory rose by at least 12 MB across the rolling window
        let threshold: Int64 = 12 * 1_048_576
        if delta >= threshold {
            return (delta, true)
        }
        return (delta, false)
    }

    public static func isProtectedProcess(
        pid: Int32,
        selfPID: Int32 = getpid(),
        processName: String,
        executablePath: String,
        bundleIdentifier: String? = nil
    ) -> Bool {
        if pid <= 100 || pid == selfPID {
            return true
        }
        if protectedProcessNames.contains(processName) {
            return true
        }
        let execLast = (executablePath as NSString).lastPathComponent
        if protectedProcessNames.contains(execLast) {
            return true
        }
        if let bid = bundleIdentifier {
            if bid == "com.apple.finder"
                || bid == "com.apple.dock"
                || bid == "com.apple.systemuiserver"
                || bid == "com.apple.controlcenter"
                || bid == "com.apple.loginwindow"
                || bid == "com.apple.Terminal"
                || bid == "com.resitdc.r-cleaner" {
                return true
            }
        }
        if executablePath.hasPrefix("/System/Library/CoreServices/") {
            return true
        }
        return false
    }

    // MARK: - Pure `ps` Output Parser

    public struct RawPsRow: Equatable, Sendable {
        public let pid: Int32
        public let ppid: Int32
        public let stat: String
        public let cpuPercent: Double
        public let rssKB: Int64
        public let etime: String
        public let executablePath: String
    }

    public static func parsePsTable(_ output: String) -> [RawPsRow] {
        var rows: [RawPsRow] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 6, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count >= 7,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }

            let stat = String(parts[2])
            let cpuStr = String(parts[3]).replacingOccurrences(of: ",", with: ".")
            let cpu = Double(cpuStr) ?? 0.0
            let rss = Int64(parts[4]) ?? 0
            let etime = String(parts[5])
            let comm = String(parts[6]).trimmingCharacters(in: .whitespaces)
            guard pid > 0, !comm.isEmpty else { continue }

            rows.append(RawPsRow(
                pid: pid,
                ppid: ppid,
                stat: stat,
                cpuPercent: cpu,
                rssKB: rss,
                etime: etime,
                executablePath: comm
            ))
        }
        return rows
    }

    // MARK: - Cryo-Freeze (SIGSTOP) & Unfreeze (SIGCONT) Actions

    public struct CryoActionResult: Sendable {
        public let success: Bool
        public let isNowFrozen: Bool
        public let message: String
    }

    /// Suspends a running app/process to 0% CPU using `SIGSTOP`.
    public func freezeProcess(_ item: CryoProcessItem) -> CryoActionResult {
        guard !item.isSystemProtected else {
            return CryoActionResult(
                success: false,
                isNowFrozen: false,
                message: "\(item.displayTitle) is a protected macOS process and cannot be frozen."
            )
        }

        let rc = Darwin.kill(item.pid, SIGSTOP)
        if rc == 0 {
            lock.lock()
            sessionFrozenPIDs.insert(item.pid)
            lock.unlock()
            return CryoActionResult(
                success: true,
                isNowFrozen: true,
                message: "Cryo-froze \(item.displayTitle) (PID \(String(item.pid))) — CPU paused at 0%"
            )
        } else {
            let err = String(cString: strerror(errno))
            return CryoActionResult(
                success: false,
                isNowFrozen: false,
                message: "Could not freeze \(item.displayTitle): \(err)"
            )
        }
    }

    /// Wakes a frozen app/process back up using `SIGCONT`.
    public func unfreezeProcess(_ item: CryoProcessItem) -> CryoActionResult {
        let rc = Darwin.kill(item.pid, SIGCONT)
        lock.lock()
        sessionFrozenPIDs.remove(item.pid)
        lock.unlock()

        if rc == 0 {
            return CryoActionResult(
                success: true,
                isNowFrozen: false,
                message: "Unfroze \(item.displayTitle) (PID \(String(item.pid))) — resumed execution"
            )
        } else {
            let err = String(cString: strerror(errno))
            return CryoActionResult(
                success: false,
                isNowFrozen: false,
                message: "Could not unfreeze \(item.displayTitle): \(err)"
            )
        }
    }

    /// Resumes all currently frozen processes (both session-tracked and any `T`-state items in the snapshot).
    @discardableResult
    public func unfreezeAll(in snapshot: CryoFreezerSnapshot? = nil) -> Int {
        lock.lock()
        var targets = sessionFrozenPIDs
        sessionFrozenPIDs.removeAll()
        lock.unlock()

        if let snap = snapshot {
            for item in snap.items where item.isFrozen {
                targets.insert(item.pid)
            }
        }

        var resumed = 0
        for pid in targets where pid > 100 {
            if Darwin.kill(pid, SIGCONT) == 0 {
                resumed += 1
            }
        }
        return resumed
    }

    // MARK: - App Bundle Resolution Helpers

    private struct GUIAppInfo {
        let name: String
        let bundlePath: String
        let bundleID: String?
    }

    private static func fetchRunningGUIApps() -> [Int32: GUIAppInfo] {
        var map: [Int32: GUIAppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0,
                  app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
            let path = app.bundleURL?.path ?? ""
            guard !name.isEmpty else { continue }
            map[pid] = GUIAppInfo(name: name, bundlePath: path, bundleID: app.bundleIdentifier)
        }
        return map
    }

    private static func resolveAppBundle(fromExecutablePath execPath: String) -> GUIAppInfo? {
        guard let range = execPath.range(of: ".app/Contents/MacOS/") else { return nil }
        let appPath = String(execPath[..<range.lowerBound]) + ".app"
        let appName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return GUIAppInfo(name: appName, bundlePath: appPath, bundleID: nil)
    }
}
