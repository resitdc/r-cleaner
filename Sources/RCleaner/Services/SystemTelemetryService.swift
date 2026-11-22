import Foundation
import AppKit
import Darwin
import IOKit
import IOKit.ps
import CoreWLAN

public final class SystemTelemetryService {
    private let stateLock = NSLock()
    private var prevCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNetBytes: (inBytes: UInt64, outBytes: UInt64, timestamp: Date)?
    private var prevProcessNet: (samples: [Int32: (inBytes: Int64, outBytes: Int64)], timestamp: Date)?
    private var cpuHistory: [Double] = Array(repeating: 0, count: 30)

    public init() {}

    public func captureSnapshot(includeProcessesAndDrives: Bool = true) -> SystemTelemetrySnapshot {
        var snap = SystemTelemetrySnapshot()
        snap.cpu = readCPU()
        snap.memory = readMemory()
        snap.storage = readStorage()
        snap.battery = readBattery()
        snap.thermal = readThermal(batteryTemp: snap.battery.temperatureCelsius)
        snap.network = readNetwork()
        if includeProcessesAndDrives {
            let (topCPU, topMem) = readTopProcesses()
            snap.topCPUConsumers = topCPU
            snap.topMemoryConsumers = topMem
            snap.topNetworkConsumers = readPerAppNetworkBandwidth()
            snap.externalDrives = readExternalDrives()
        }
        snap.lastUpdated = Date()
        return snap
    }

    // MARK: - Thermal Pressure (ProcessInfo.thermalState + Low Power Mode)

    private func readThermal(batteryTemp: Double?) -> ThermalReading {
        var reading = ThermalReading()
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: reading.state = .nominal
        case .fair: reading.state = .fair
        case .serious: reading.state = .serious
        case .critical: reading.state = .critical
        @unknown default: reading.state = .nominal
        }
        reading.temperatureCelsius = batteryTemp
        reading.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        return reading
    }

    // MARK: - CPU via Mach host_statistics

    private func readCPU() -> CPUReading {
        var reading = CPUReading()
        reading.uptimeSeconds = ProcessInfo.processInfo.systemUptime
        reading.coreCount = ProcessInfo.processInfo.processorCount

        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        stateLock.lock()
        if kr == KERN_SUCCESS {
            let u = UInt64(load.cpu_ticks.0)
            let s = UInt64(load.cpu_ticks.1)
            let i = UInt64(load.cpu_ticks.2)
            let n = UInt64(load.cpu_ticks.3)

            if let prev = prevCPUTicks {
                let du = u >= prev.user ? u - prev.user : 0
                let ds = s >= prev.system ? s - prev.system : 0
                let di = i >= prev.idle ? i - prev.idle : 0
                let dn = n >= prev.nice ? n - prev.nice : 0
                let total = Double(du + ds + di + dn)
                if total > 0 {
                    reading.userPercent = (Double(du + dn) / total) * 100.0
                    reading.systemPercent = (Double(ds) / total) * 100.0
                    reading.idlePercent = (Double(di) / total) * 100.0
                }
            }
            prevCPUTicks = (u, s, i, n)
        }

        cpuHistory.removeFirst()
        cpuHistory.append(reading.totalLoadPercent)
        reading.history = cpuHistory
        stateLock.unlock()
        return reading
    }

    // MARK: - Memory via Mach host_statistics64 & sysctl swapusage

    private func readMemory() -> MemoryReading {
        var reading = MemoryReading()
        reading.totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)

        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if kr == KERN_SUCCESS {
            let pageSize = Int64(vm_kernel_page_size)
            reading.activeBytes = Int64(vmStat.active_count) * pageSize
            reading.wiredBytes = Int64(vmStat.wire_count) * pageSize
            reading.compressedBytes = Int64(vmStat.compressor_page_count) * pageSize
            reading.freeBytes = Int64(vmStat.free_count + vmStat.inactive_count) * pageSize
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            reading.swapUsedBytes = Int64(swap.xsu_used)
            reading.swapTotalBytes = Int64(swap.xsu_total)
        }

        return reading
    }

    // MARK: - Storage & Trash

    private func readStorage() -> StorageReading {
        var reading = StorageReading()
        let rootURL = URL(fileURLWithPath: "/")
        if let vals = try? rootURL.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey
        ]) {
            reading.volumeName = vals.volumeName ?? "Macintosh HD"
            reading.totalBytes = Int64(vals.volumeTotalCapacity ?? 0)
            let important = vals.volumeAvailableCapacityForImportantUsage ?? Int64(vals.volumeAvailableCapacity ?? 0)
            let direct = Int64(vals.volumeAvailableCapacity ?? 0)
            reading.availableBytes = max(important, direct)
            reading.purgeableBytes = max(0, important - direct)
        }
        let trashURL = URL(fileURLWithPath: FileSystemHelpers.expand("~/.Trash"))
        reading.trashBytes = FileSystemHelpers.directorySize(at: trashURL, maxFiles: 2500)
        return reading
    }

    // MARK: - Battery via IOKit

    private func readBattery() -> BatteryReading {
        var reading = BatteryReading()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return reading
        }

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                reading.isPresent = true
                reading.percentage = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
                reading.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                reading.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
                if let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
                    reading.timeRemainingMinutes = timeToEmpty
                } else if let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
                    reading.timeRemainingMinutes = timeToFull
                }
                reading.condition = desc[kIOPSBatteryHealthKey] as? String ?? "Normal"
                break
            }
        }

        // Pull cycle count, max capacity, and temperature from AppleSmartBattery
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let cycles = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                reading.cycleCount = cycles
            }
            let maxCap = (IORegistryEntryCreateCFProperty(service, "AppleRawMaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int)
                ?? (IORegistryEntryCreateCFProperty(service, "MaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int)
            let designCap = IORegistryEntryCreateCFProperty(service, "DesignCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            if let m = maxCap, let d = designCap, d > 0 {
                reading.healthPercent = min(100, max(1, Int((Double(m) / Double(d)) * 100.0)))
            }
            if let rawTemp = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                // Apple Silicon reports centi-Celsius (e.g. 3132 -> 31.32 C); older Intel Macs may report centi-Kelvin (>20000)
                let celsius = rawTemp > 20_000 ? (Double(rawTemp) / 100.0 - 273.15) : (Double(rawTemp) / 100.0)
                if celsius > -20 && celsius < 110 {
                    reading.temperatureCelsius = celsius
                }
            }
            if let voltageMV = IORegistryEntryCreateCFProperty(service, "Voltage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
               let ampRaw = (IORegistryEntryCreateCFProperty(service, "InstantAmperage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int)
                    ?? (IORegistryEntryCreateCFProperty(service, "Amperage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) {
                let watts = abs(Double(voltageMV) * Double(ampRaw)) / 1_000_000.0
                if watts > 0.1 && watts < 250 {
                    reading.powerWatts = watts
                }
            }
        }

        return reading
    }

    // MARK: - Network Throughput & Wi-Fi Info

    private func readNetwork() -> NetworkReading {
        var reading = NetworkReading()

        var addrs: UnsafeMutablePointer<ifaddrs>?
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var activeIface = "en0"
        var hasUpNonLoopback = false

        if getifaddrs(&addrs) == 0, let first = addrs {
            var ptr: UnsafeMutablePointer<ifaddrs>? = first
            while let current = ptr {
                let flags = Int32(current.pointee.ifa_flags)
                let name = String(cString: current.pointee.ifa_name)
                if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 && name.hasPrefix("en") {
                    if let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                       let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        totalIn += UInt64(data.pointee.ifi_ibytes)
                        totalOut += UInt64(data.pointee.ifi_obytes)
                        if data.pointee.ifi_ibytes > 0 || data.pointee.ifi_obytes > 0 {
                            hasUpNonLoopback = true
                            activeIface = name
                        }
                    }
                }
                ptr = current.pointee.ifa_next
            }
            freeifaddrs(first)
        }

        let now = Date()
        stateLock.lock()
        if let prev = prevNetBytes {
            let dt = max(0.2, now.timeIntervalSince(prev.timestamp))
            let dIn = totalIn >= prev.inBytes ? Double(totalIn - prev.inBytes) : 0
            let dOut = totalOut >= prev.outBytes ? Double(totalOut - prev.outBytes) : 0
            reading.downloadBytesPerSec = dIn / dt
            reading.uploadBytesPerSec = dOut / dt
        }
        prevNetBytes = (totalIn, totalOut, now)
        stateLock.unlock()
        reading.totalDownloadedBytes = Int64(totalIn)
        reading.totalUploadedBytes = Int64(totalOut)
        reading.interfaceName = activeIface
        reading.isConnected = hasUpNonLoopback

        if let wifi = CWWiFiClient.shared().interface() {
            if let ssid = wifi.ssid(), !ssid.isEmpty {
                reading.networkName = ssid
                reading.connectionType = "Wi-Fi"
                let sec = wifi.security()
                switch sec {
                case .wpa3Personal, .wpa3Enterprise, .wpa3Transition, .wpa2Personal, .wpa2Enterprise:
                    reading.securityRating = "Strong"
                case .wpaPersonal, .wpaEnterprise:
                    reading.securityRating = "Good"
                case .none:
                    reading.securityRating = "Open"
                default:
                    reading.securityRating = "Good"
                }
            } else if wifi.powerOn() && hasUpNonLoopback {
                reading.networkName = "Wi-Fi (\(activeIface))"
                reading.connectionType = "Wi-Fi"
            } else if hasUpNonLoopback {
                reading.networkName = "Wired Ethernet"
                reading.connectionType = "Wired"
                reading.securityRating = "Strong"
            }
        }

        return reading
    }

    public func runSpeedTest() async -> Double? {
        // Download a small public test payload (Cloudflare 5MB test) to measure real throughput
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000") else { return nil }
        let start = Date()
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: req)
            let elapsed = max(0.05, Date().timeIntervalSince(start))
            let megabits = (Double(data.count) * 8.0) / 1_000_000.0
            return megabits / elapsed
        } catch {
            return nil
        }
    }

    // MARK: - Per-App Live Bandwidth via macOS nettop

    /// Parses `/usr/bin/nettop -P -L 1 -J bytes_in,bytes_out -x` CSV output into `(pid, name, inBytes, outBytes)`.
    public static func parseNettopOutput(_ output: String) -> [(pid: Int32, name: String, inBytes: Int64, outBytes: Int64)] {
        var rows: [(pid: Int32, name: String, inBytes: Int64, outBytes: Int64)] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(",") else { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }

            let procToken = String(cols[0])
            guard let dotIdx = procToken.lastIndex(of: ".") else { continue }
            let name = String(procToken[..<dotIdx]).trimmingCharacters(in: .whitespaces)
            let pidStr = String(procToken[procToken.index(after: dotIdx)...])
            guard let pid = Int32(pidStr), !name.isEmpty,
                  let bytesIn = Int64(cols[1].trimmingCharacters(in: .whitespaces)),
                  let bytesOut = Int64(cols[2].trimmingCharacters(in: .whitespaces)) else { continue }
            rows.append((pid, name, bytesIn, bytesOut))
        }
        return rows
    }

    private func readPerAppNetworkBandwidth() -> [ProcessNetworkConsumer] {
        let res = FileSystemHelpers.runProcess("/usr/bin/nettop", arguments: ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"], timeout: 3)
        guard res.exitCode == 0 else { return [] }

        let parsed = Self.parseNettopOutput(res.stdout)
        let now = Date()
        var currentMap: [Int32: (inBytes: Int64, outBytes: Int64)] = [:]
        currentMap.reserveCapacity(parsed.count)
        for row in parsed {
            currentMap[row.pid] = (row.inBytes, row.outBytes)
        }

        stateLock.lock()
        let prev = prevProcessNet
        prevProcessNet = (currentMap, now)
        stateLock.unlock()

        let dt = prev.map { max(0.5, now.timeIntervalSince($0.timestamp)) } ?? 0
        var consumers: [ProcessNetworkConsumer] = []
        consumers.reserveCapacity(parsed.count)

        for row in parsed {
            guard row.inBytes > 0 || row.outBytes > 0 else { continue }
            var dlRate: Double = 0
            var ulRate: Double = 0
            if let prevSample = prev?.samples[row.pid], dt > 0 {
                let dIn = row.inBytes >= prevSample.inBytes ? Double(row.inBytes - prevSample.inBytes) : 0
                let dOut = row.outBytes >= prevSample.outBytes ? Double(row.outBytes - prevSample.outBytes) : 0
                dlRate = dIn / dt
                ulRate = dOut / dt
            }
            consumers.append(ProcessNetworkConsumer(
                id: row.pid,
                name: row.name,
                downloadBytesPerSec: dlRate,
                uploadBytesPerSec: ulRate,
                totalInBytes: row.inBytes,
                totalOutBytes: row.outBytes
            ))
        }

        // Prioritize processes actively transferring right now, breaking ties by total session bytes
        return Array(consumers.sorted { a, b in
            if (a.totalRateBytesPerSec > 0) != (b.totalRateBytesPerSec > 0) {
                return a.totalRateBytesPerSec > b.totalRateBytesPerSec
            }
            if abs(a.totalRateBytesPerSec - b.totalRateBytesPerSec) > 10 {
                return a.totalRateBytesPerSec > b.totalRateBytesPerSec
            }
            return (a.totalInBytes + a.totalOutBytes) > (b.totalInBytes + b.totalOutBytes)
        }.prefix(8))
    }

    // MARK: - Top Consumers (CPU & Memory)

    private func readTopProcesses() -> ([ProcessConsumer], [ProcessConsumer]) {
        let res = FileSystemHelpers.runProcess("/bin/ps", arguments: ["-axo", "pid=,pcpu=,rss=,state=,comm="], timeout: 4)
        guard res.exitCode == 0 else { return ([], []) }

        var list: [ProcessConsumer] = []
        for line in res.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard parts.count == 5,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Int64(parts[2]) else { continue }
            let state = String(parts[3])
            let fullCmd = String(parts[4])
            let name = URL(fileURLWithPath: fullCmd).lastPathComponent
            if name.isEmpty || name == "ps" { continue }
            list.append(ProcessConsumer(
                id: pid,
                name: name,
                cpuPercent: cpu,
                memoryBytes: rssKB * 1024,
                isNotResponding: state.contains("U")
            ))
        }

        let topCPU = Array(list.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(6))
        let topMem = Array(list.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(6))
        return (topCPU, topMem)
    }

    public func terminateProcess(pid: Int32, force: Bool = false) -> Bool {
        // Guard against killing kernel/launchd (PID <= 1) or R-Cleaner itself
        guard pid > 1, pid != getpid() else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) {
            return force ? app.forceTerminate() : app.terminate()
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    // MARK: - External Drives

    public func readExternalDrives() -> [ExternalDriveInfo] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey,
                .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey
            ],
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var drives: [ExternalDriveInfo] = []
        for url in urls {
            guard url.path != "/", !url.path.hasPrefix("/System") else { continue }
            guard let vals = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey,
                .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey
            ]) else { continue }
            if vals.volumeIsInternal == true && vals.volumeIsRemovable != true { continue }

            let name = vals.volumeName ?? url.lastPathComponent
            let trashPath = url.appendingPathComponent(".Trashes").path
            let junk = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: trashPath), maxFiles: 500)
            drives.append(ExternalDriveInfo(
                id: url.path,
                name: name,
                mountPath: url.path,
                totalBytes: Int64(vals.volumeTotalCapacity ?? 0),
                availableBytes: Int64(vals.volumeAvailableCapacity ?? 0),
                isReadOnly: vals.volumeIsReadOnly ?? false,
                junkBytes: junk
            ))
        }
        return drives
    }

    public func ejectDrive(at path: String) -> Bool {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Configurable Clear Smart Guard Evaluator

/// Stateful, pure evaluator that tracks runaway CPU durations and alert cooldowns
/// against user-configurable thresholds for Disk, RAM Pressure, Runaway CPU, and Thermal State.
public final class ClearSmartGuardEvaluator {
    private var runawayStartByPID: [Int32: Date] = [:]
    private var lastAlertTimeByKind: [SmartAlertKind: Date] = [:]

    public init() {}

    public func evaluate(
        snapshot: SystemTelemetrySnapshot,
        settings: RCleanerSettings,
        now: Date = Date()
    ) -> (activeAlerts: [ClearSmartAlert], newlyTriggered: [ClearSmartAlert]) {
        guard settings.enableClearSmartAlerts else {
            runawayStartByPID.removeAll()
            return ([], [])
        }

        let cooldownSeconds = TimeInterval(max(1, settings.smartAlertCooldownMinutes) * 60)
        var active: [ClearSmartAlert] = []
        var newlyTriggered: [ClearSmartAlert] = []

        func record(_ alert: ClearSmartAlert) {
            active.append(alert)
            if let last = lastAlertTimeByKind[alert.kind], now.timeIntervalSince(last) < cooldownSeconds {
                return
            }
            lastAlertTimeByKind[alert.kind] = now
            newlyTriggered.append(alert)
        }

        // 1. Low Disk Space Guard (configurable GB threshold)
        if snapshot.storage.totalBytes > 0 {
            let thresholdBytes = Int64(max(1, settings.warnLowDiskSpaceGB)) * 1_000_000_000
            if snapshot.storage.availableBytes < thresholdBytes {
                let freeGB = Double(snapshot.storage.availableBytes) / 1_000_000_000.0
                record(ClearSmartAlert(
                    kind: .lowDisk,
                    title: "Low Disk Space",
                    message: String(format: "Only %.1f GB free (below your %d GB alert threshold).", freeGB, settings.warnLowDiskSpaceGB),
                    iconName: "externaldrive.badge.exclamationmark",
                    accentHex: "FF5E57",
                    triggeredAt: now
                ))
            }
        }

        // 2. RAM Pressure Guard (configurable % threshold)
        if settings.notifyLowRAM, snapshot.memory.totalBytes > 0 {
            let ramThreshold = Double(max(50, min(99, settings.ramAlertThresholdPercent)))
            if snapshot.memory.pressurePercent >= ramThreshold {
                record(ClearSmartAlert(
                    kind: .criticalRAM,
                    title: "High Memory Pressure (\(Int(snapshot.memory.pressurePercent))%)",
                    message: "Memory load exceeded your \(settings.ramAlertThresholdPercent)% threshold. Freeing RAM is recommended.",
                    iconName: "memorychip.fill",
                    accentHex: "A855F7",
                    triggeredAt: now
                ))
            }
        }

        // 3. Runaway CPU Process Guard (configurable % threshold & sustained duration seconds)
        if settings.notifyRunawayCPU {
            let cpuThreshold = Double(max(20, settings.runawayCPUThresholdPercent))
            let requiredSeconds = TimeInterval(max(5, settings.runawayCPUDurationSeconds))
            var hotPIDs = Set<Int32>()

            for proc in snapshot.topCPUConsumers where proc.id > 1 && proc.cpuPercent >= cpuThreshold {
                hotPIDs.insert(proc.id)
                let start = runawayStartByPID[proc.id] ?? now
                if runawayStartByPID[proc.id] == nil {
                    runawayStartByPID[proc.id] = start
                }
                let elapsed = now.timeIntervalSince(start)
                if elapsed >= requiredSeconds {
                    record(ClearSmartAlert(
                        kind: .runawayCPU,
                        title: "Runaway Process: \(proc.name)",
                        message: String(format: "%@ has pegged %.0f%% CPU for %ds (limit: %d%% for %ds).", proc.name, proc.cpuPercent, Int(elapsed), settings.runawayCPUThresholdPercent, settings.runawayCPUDurationSeconds),
                        iconName: "flame.fill",
                        accentHex: "FF6B4A",
                        triggeredAt: now,
                        processID: proc.id,
                        processName: proc.name
                    ))
                    break // Surface the single worst runaway offender at a time
                }
            }
            // Clear streaks for processes that calmed down
            runawayStartByPID = runawayStartByPID.filter { hotPIDs.contains($0.key) }
        } else {
            runawayStartByPID.removeAll()
        }

        // 4. Thermal Pressure Guard (Serious / Critical)
        if settings.notifyThermalPressure, (snapshot.thermal.state == .serious || snapshot.thermal.state == .critical) {
            record(ClearSmartAlert(
                kind: .thermalPressure,
                title: "Thermal Pressure: \(snapshot.thermal.state.rawValue)",
                message: snapshot.thermal.state.descriptionText,
                iconName: "thermometer.high",
                accentHex: snapshot.thermal.state.accentHex,
                triggeredAt: now
            ))
        }

        return (active, newlyTriggered)
    }

    public func resetCooldowns() {
        lastAlertTimeByKind.removeAll()
        runawayStartByPID.removeAll()
    }
}
