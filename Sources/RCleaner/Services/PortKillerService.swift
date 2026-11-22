import Foundation
import AppKit
import Darwin

/// Live TCP Port & Local Dev Server Inspector and Killer.
/// Combines `lsof -iTCP -sTCP:LISTEN -P -n`, `ps`, and `lsof -d cwd` in a single fast pass (~120ms)
/// to reveal the exact project folder, framework (Vite, Next.js, Node, Bun, PostgreSQL, Ollama, Redis, etc.),
/// LAN exposure (`0.0.0.0` vs `localhost`), memory/CPU footprint, and 1-click graceful or force termination.
public final class PortKillerService: @unchecked Sendable {
    /// Well-known developer ports displayed in the Quick Watch bar.
    public static let watchedDevPorts: [Int] = [
        3000, 3001, 4000, 4200, 5000, 5173, 5174, 5432, 6379, 8000, 8080, 11434
    ]

    public init() {}

    // MARK: - Live Port Discovery & Enrichment

    public func scanListeningPorts() -> PortKillerSnapshot {
        let lsofRes = FileSystemHelpers.runProcess(
            "/usr/sbin/lsof",
            arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"],
            timeout: 4
        )
        guard lsofRes.exitCode == 0 else {
            return PortKillerSnapshot()
        }

        let rawSockets = Self.parseLsofListenTable(lsofRes.stdout)
        guard !rawSockets.isEmpty else {
            return PortKillerSnapshot()
        }

        let uniquePIDs = Array(Set(rawSockets.map(\.pid))).sorted()
        let pidCSV = uniquePIDs.map(String.init).joined(separator: ",")

        let psStats = fetchProcessStats(pidCSV: pidCSV)
        let psArgs = fetchProcessArgs(pidCSV: pidCSV)
        let cwds = fetchWorkingDirectories(pidCSV: pidCSV)
        let selfPID = getpid()

        var items: [ActivePortItem] = []
        items.reserveCapacity(rawSockets.count)

        for sock in rawSockets {
            let stat = psStats[sock.pid]
            let fullCmd = psArgs[sock.pid] ?? stat?.comm ?? sock.commandShort
            let execPath = stat?.comm
            let procName = Self.cleanProcessName(shortCommand: sock.commandShort, execPath: execPath, fullArgs: fullCmd)
            let cwd = cwds[sock.pid]
            let projectName = Self.resolveProjectDisplayName(cwd: cwd, fullArgs: fullCmd)
            let (category, frameworkLabel) = Self.classifyPort(
                port: sock.port,
                processName: procName,
                fullArgs: fullCmd,
                cwd: cwd
            )

            let displayTitle: String
            if let proj = projectName, !proj.isEmpty {
                displayTitle = proj
            } else {
                displayTitle = procName
            }

            let isProtected = sock.pid <= 1
                || sock.pid == selfPID
                || category == .macOSSystem
                || procName == "launchd"
                || procName == "kernel_task"

            items.append(ActivePortItem(
                port: sock.port,
                pid: sock.pid,
                processName: procName,
                displayTitle: displayTitle,
                frameworkLabel: frameworkLabel,
                category: category,
                bindAddress: sock.bindAddress,
                isExposedToLAN: sock.isExposedToLAN,
                workingDirectory: cwd,
                projectDisplayName: projectName,
                commandLine: fullCmd,
                executablePath: execPath,
                cpuPercent: stat?.cpu ?? 0,
                memoryBytes: stat?.memoryBytes ?? 0,
                uptimeLabel: stat?.etime ?? "Active",
                isSystemProtected: isProtected
            ))
        }

        // Sort: Dev Web Servers first, then Databases/AI, then by port ascending
        items.sort { a, b in
            let rankA = Self.categorySortRank(a.category)
            let rankB = Self.categorySortRank(b.category)
            if rankA != rankB { return rankA < rankB }
            return a.port < b.port
        }

        return PortKillerSnapshot(items: items, lastUpdated: Date())
    }

    private static func categorySortRank(_ cat: PortServiceCategory) -> Int {
        switch cat {
        case .devWebServer: return 0
        case .databaseCache: return 1
        case .aiAndMobile: return 2
        case .ideAndTools: return 3
        case .macOSSystem: return 4
        }
    }

    // MARK: - Pure lsof Parser (Deduplicates Dual-Stack IPv4/IPv6 Sockets)

    public struct RawListeningSocket: Equatable, Sendable {
        public let commandShort: String
        public let pid: Int32
        public let user: String
        public let bindAddress: String
        public let port: Int
        public let isExposedToLAN: Bool
    }

    public static func parseLsofListenTable(_ output: String) -> [RawListeningSocket] {
        struct Key: Hashable {
            let pid: Int32
            let port: Int
        }

        var byKey: [Key: RawListeningSocket] = [:]
        var order: [Key] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("COMMAND") else { continue }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 9,
                  let pid = Int32(tokens[1]) else { continue }

            let cmdShort = tokens[0].replacingOccurrences(of: "\\x20", with: " ")
            let user = tokens[2]

            // Find the address:port token right before "(LISTEN)" or at the end of the line
            var endpointToken = tokens.last ?? ""
            if endpointToken == "(LISTEN)", tokens.count >= 2 {
                endpointToken = tokens[tokens.count - 2]
            } else if endpointToken.hasSuffix("(LISTEN)") {
                endpointToken = endpointToken.replacingOccurrences(of: "(LISTEN)", with: "")
            }

            guard let colonIdx = endpointToken.lastIndex(of: ":") else { continue }
            let hostPart = String(endpointToken[..<colonIdx])
            let portPart = String(endpointToken[endpointToken.index(after: colonIdx)...])
            guard let port = Int(portPart), port > 0 && port <= 65535 else { continue }

            let isLAN = (hostPart == "*" || hostPart == "0.0.0.0" || hostPart == "[::]")
            let cleanHost: String
            switch hostPart {
            case "*", "0.0.0.0", "[::]": cleanHost = "0.0.0.0 (All Interfaces)"
            case "127.0.0.1", "[::1]", "[fe80:1::1]": cleanHost = "127.0.0.1 (Localhost)"
            default: cleanHost = hostPart
            }

            let key = Key(pid: pid, port: port)
            if let existing = byKey[key] {
                // If either IPv4 or IPv6 socket is exposed on *, mark the merged entry as LAN-exposed
                if isLAN && !existing.isExposedToLAN {
                    byKey[key] = RawListeningSocket(
                        commandShort: existing.commandShort,
                        pid: pid,
                        user: user,
                        bindAddress: cleanHost,
                        port: port,
                        isExposedToLAN: true
                    )
                }
            } else {
                order.append(key)
                byKey[key] = RawListeningSocket(
                    commandShort: cmdShort,
                    pid: pid,
                    user: user,
                    bindAddress: cleanHost,
                    port: port,
                    isExposedToLAN: isLAN
                )
            }
        }

        return order.compactMap { byKey[$0] }
    }

    // MARK: - Process Metadata Enrichment (ps + lsof -d cwd)

    private struct PSStat {
        let cpu: Double
        let memoryBytes: Int64
        let etime: String
        let comm: String
    }

    private func fetchProcessStats(pidCSV: String) -> [Int32: PSStat] {
        guard !pidCSV.isEmpty else { return [:] }
        let res = FileSystemHelpers.runProcess(
            "/bin/ps",
            arguments: ["-p", pidCSV, "-o", "pid=,pcpu=,rss=,etime=,comm="],
            timeout: 2
        )
        guard res.exitCode == 0 else { return [:] }

        var map: [Int32: PSStat] = [:]
        for line in res.stdout.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Int64(parts[2]) else { continue }
            let etime = Self.formatElapsed(String(parts[3]))
            let comm = String(parts[4])
            map[pid] = PSStat(cpu: cpu, memoryBytes: rssKB * 1024, etime: etime, comm: comm)
        }
        return map
    }

    private func fetchProcessArgs(pidCSV: String) -> [Int32: String] {
        guard !pidCSV.isEmpty else { return [:] }
        let res = FileSystemHelpers.runProcess(
            "/bin/ps",
            arguments: ["-p", pidCSV, "-o", "pid=,args="],
            timeout: 2
        )
        guard res.exitCode == 0 else { return [:] }

        var map: [Int32: String] = [:]
        for line in res.stdout.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            map[pid] = String(parts[1])
        }
        return map
    }

    private func fetchWorkingDirectories(pidCSV: String) -> [Int32: String] {
        guard !pidCSV.isEmpty else { return [:] }
        let res = FileSystemHelpers.runProcess(
            "/usr/sbin/lsof",
            arguments: ["-a", "-p", pidCSV, "-d", "cwd", "-F", "pn"],
            timeout: 2
        )
        guard res.exitCode == 0 else { return [:] }

        var map: [Int32: String] = [:]
        var currentPID: Int32?
        for line in res.stdout.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
            } else if line.hasPrefix("n"), let pid = currentPID {
                let path = String(line.dropFirst())
                if !path.isEmpty && path != "/" {
                    map[pid] = path
                }
            }
        }
        return map
    }

    // MARK: - Smart Framework & Project Classification

    private static func cleanProcessName(shortCommand: String, execPath: String?, fullArgs: String) -> String {
        if let execPath, !execPath.isEmpty {
            let base = URL(fileURLWithPath: execPath).lastPathComponent
            if !base.isEmpty && base.count >= shortCommand.count {
                return base
            }
        }
        if let firstToken = fullArgs.split(separator: " ").first {
            let base = URL(fileURLWithPath: String(firstToken)).lastPathComponent
            if !base.isEmpty && base.count >= shortCommand.count {
                return base
            }
        }
        return shortCommand
    }

    private static func resolveProjectDisplayName(cwd: String?, fullArgs: String) -> String? {
        let home = FileSystemHelpers.homeDirectory
        if let cwd, cwd != "/", cwd != home, !cwd.hasPrefix("/System"), !cwd.hasPrefix("/usr") {
            if cwd.hasPrefix("/opt/homebrew/var/") {
                return URL(fileURLWithPath: cwd).lastPathComponent
            }
            let url = URL(fileURLWithPath: cwd)
            let leaf = url.lastPathComponent
            let parent = url.deletingLastPathComponent().lastPathComponent
            if !parent.isEmpty && parent != "/" && parent != URL(fileURLWithPath: home).lastPathComponent && parent != "projects" && parent != "working-directory" {
                return "\(parent) / \(leaf)"
            }
            return leaf
        }

        // Fallback: extract project folder from full CLI path inside home/working-directory
        if let range = fullArgs.range(of: "/projects/") {
            let after = fullArgs[range.upperBound...]
            let comps = after.split(separator: "/").prefix(2).map(String.init)
            if !comps.isEmpty {
                return comps.joined(separator: " / ")
            }
        }
        return nil
    }

    public static func classifyPort(
        port: Int,
        processName: String,
        fullArgs: String,
        cwd: String?
    ) -> (category: PortServiceCategory, frameworkLabel: String) {
        let lowerProc = processName.lowercased()
        let lowerArgs = fullArgs.lowercased()

        // 1. macOS Built-in Services
        if lowerProc.hasPrefix("controlce") || lowerProc.hasPrefix("rapportd") || lowerProc.hasPrefix("sharingd")
            || lowerProc.hasPrefix("apsd") || lowerProc.hasPrefix("identityservice") || lowerProc.hasPrefix("mDNSResponder".lowercased()) {
            let label = lowerProc.hasPrefix("controlce") ? "macOS AirPlay / Control Center" : "macOS System Service"
            return (.macOSSystem, label)
        }

        // 2. Databases & Cache Engines
        if lowerProc.contains("postgres") || port == 5432 {
            return (.databaseCache, "PostgreSQL")
        }
        if lowerProc.contains("mysqld") || lowerProc.contains("mariadbd") || port == 3306 || port == 33060 {
            return (.databaseCache, "MySQL / MariaDB")
        }
        if lowerProc.contains("redis") || lowerProc.contains("valkey") || port == 6379 {
            return (.databaseCache, "Redis")
        }
        if lowerProc.contains("mongod") || port == 27017 {
            return (.databaseCache, "MongoDB")
        }
        if lowerProc.contains("memcached") || port == 11211 {
            return (.databaseCache, "Memcached")
        }
        if lowerProc.contains("clickhouse") || port == 8123 || port == 9000 {
            if lowerProc.contains("clickhouse") { return (.databaseCache, "ClickHouse") }
        }

        // 3. AI & Mobile Toolchains
        if lowerProc.contains("ollama") || port == 11434 {
            return (.aiAndMobile, "Ollama LLM Server")
        }
        if lowerProc.contains("lmstudio") || lowerArgs.contains("lm studio") || port == 1234 {
            if lowerProc.contains("lm") || port == 1234 { return (.aiAndMobile, "LM Studio Server") }
        }
        if lowerProc == "adb" || port == 5037 {
            return (.aiAndMobile, "Android Debug Bridge (ADB)")
        }
        if lowerProc.hasPrefix("qemu") || port == 5555 {
            return (.aiAndMobile, "Android Emulator (QEMU)")
        }

        // 4. Web & Dev Servers (Node, Vite, Next, Nuxt, Bun, Deno, Python, Go, Rust, PHP, Ruby, Java)
        if lowerProc == "node" || lowerProc == "bun" || lowerProc == "deno" {
            if lowerArgs.contains("vite") || port == 5173 || port == 5174 || port == 4173 {
                return (.devWebServer, "Vite • \(processName)")
            }
            if lowerArgs.contains("next") {
                return (.devWebServer, "Next.js • \(processName)")
            }
            if lowerArgs.contains("nuxt") {
                return (.devWebServer, "Nuxt • \(processName)")
            }
            if lowerArgs.contains("nest") {
                return (.devWebServer, "NestJS • \(processName)")
            }
            if lowerArgs.contains("astro") || port == 4321 {
                return (.devWebServer, "Astro • \(processName)")
            }
            if lowerArgs.contains("ts-node") || lowerArgs.contains("tsx") {
                return (.devWebServer, "TypeScript • \(processName)")
            }
            if lowerArgs.contains("react-scripts") || lowerArgs.contains("webpack") {
                return (.devWebServer, "Webpack / React • \(processName)")
            }
            return (.devWebServer, "Node.js Server")
        }

        if lowerProc.hasPrefix("python") || lowerProc == "uvicorn" || lowerProc == "gunicorn" || lowerProc == "flask" {
            if lowerArgs.contains("uvicorn") || lowerArgs.contains("fastapi") {
                return (.devWebServer, "FastAPI / Uvicorn")
            }
            if lowerArgs.contains("manage.py") || lowerArgs.contains("django") {
                return (.devWebServer, "Django Server")
            }
            if lowerArgs.contains("flask") {
                return (.devWebServer, "Flask Server")
            }
            return (.devWebServer, "Python Server")
        }

        if lowerProc == "ruby" || lowerProc == "puma" || lowerProc == "rails" {
            return (.devWebServer, "Ruby / Rails Server")
        }
        if lowerProc == "php" || lowerArgs.contains("artisan serve") {
            return (.devWebServer, lowerArgs.contains("artisan") ? "Laravel / PHP" : "PHP Dev Server")
        }
        if lowerProc == "go" || lowerProc == "air" || lowerProc == "hugo" {
            return (.devWebServer, "Go Server")
        }
        if lowerProc == "cargo" || lowerProc == "trunk" {
            return (.devWebServer, "Rust Dev Server")
        }
        if lowerProc == "nginx" || lowerProc == "caddy" || lowerProc == "httpd" {
            return (.devWebServer, "Web Proxy (\(processName))")
        }

        // Standard dev server ports (3000..9999) when not an IDE high port
        let commonDevPorts: Set<Int> = [3000, 3001, 3002, 4000, 4200, 5173, 5174, 8000, 8080, 8081, 8787, 8888, 9000]
        if commonDevPorts.contains(port) {
            return (.devWebServer, "\(processName) Dev Server")
        }

        // 5. IDEs & Desktop Apps
        if lowerProc.hasPrefix("studio") || lowerProc.hasPrefix("intellij") || lowerProc.hasPrefix("webstorm") || lowerProc.hasPrefix("pycharm") {
            return (.ideAndTools, "JetBrains / Android Studio")
        }
        if lowerProc.hasPrefix("antigravi") || lowerProc == "agy" || lowerProc.contains("cursor") || lowerProc.contains("code") {
            return (.ideAndTools, "AI Coding IDE")
        }
        if lowerProc.contains("docker") || lowerProc.contains("com.docker") || lowerProc.contains("orbstack") {
            return (.aiAndMobile, "Docker / Container Engine")
        }

        return (.ideAndTools, processName)
    }

    private static func formatElapsed(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Active" }
        // ps etime format: [[dd-]hh:]mm:ss
        if let dashIdx = trimmed.firstIndex(of: "-") {
            let days = trimmed[..<dashIdx]
            let rest = trimmed[trimmed.index(after: dashIdx)...].split(separator: ":")
            let hours = rest.first ?? "0"
            return "\(days)d \(hours)h"
        }
        let comps = trimmed.split(separator: ":")
        if comps.count == 3 {
            let h = Int(comps[0]) ?? 0
            let m = Int(comps[1]) ?? 0
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        } else if comps.count == 2 {
            let m = Int(comps[0]) ?? 0
            let s = Int(comps[1]) ?? 0
            return m > 0 ? "\(m)m \(s)s" : "\(s)s"
        }
        return trimmed
    }

    // MARK: - Kill / Terminate Port Process

    public func terminatePort(_ item: ActivePortItem, force: Bool) -> (success: Bool, message: String) {
        guard item.pid > 1, item.pid != getpid() else {
            return (false, "Protected system process cannot be terminated.")
        }

        let sig: Int32 = force ? SIGKILL : SIGTERM
        if kill(item.pid, sig) == 0 {
            // Brief wait so lsof immediately reflects the freed port on refresh
            usleep(120_000)
            let actionVerb = force ? "Force-killed" : "Stopped"
            return (true, "\(actionVerb) :\(item.port) (\(item.displayTitle), PID \(item.pid))")
        }

        let err = String(cString: strerror(errno))
        return (false, "Could not terminate PID \(item.pid) on :\(item.port) (\(err))")
    }

    public func terminatePortNumber(_ port: Int, in snapshot: PortKillerSnapshot, force: Bool) -> (success: Bool, message: String) {
        let matches = snapshot.items.filter { $0.port == port }
        guard !matches.isEmpty else {
            return (false, "No listening process found on port :\(port)")
        }
        var killed = 0
        var lastMsg = ""
        for item in matches {
            let res = terminatePort(item, force: force)
            if res.success { killed += 1 }
            lastMsg = res.message
        }
        return (killed > 0, lastMsg)
    }
}
