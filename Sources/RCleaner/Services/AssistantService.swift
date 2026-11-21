import Foundation

public final class AssistantService {
    private let supportFolderURL: URL
    private let settingsURL: URL
    private let statsURL: URL
    private let ioQueue = DispatchQueue(label: "com.resitdc.rcleaner.persistence", qos: .utility)

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.supportFolderURL = appSupport.appendingPathComponent("R-Cleaner", isDirectory: true)
        self.settingsURL = supportFolderURL.appendingPathComponent("settings.json")
        self.statsURL = supportFolderURL.appendingPathComponent("activity_stats.json")
        try? FileManager.default.createDirectory(at: supportFolderURL, withIntermediateDirectories: true)
    }

    public func loadSettings() -> RCleanerSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(RCleanerSettings.self, from: data) else {
            return RCleanerSettings()
        }
        return decoded
    }

    public func saveSettings(_ settings: RCleanerSettings) {
        let url = settingsURL
        ioQueue.async {
            if let data = try? JSONEncoder().encode(settings) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func loadStatistics() -> ActivityStatistics {
        guard let data = try? Data(contentsOf: statsURL),
              let decoded = try? JSONDecoder().decode(ActivityStatistics.self, from: data) else {
            return .empty
        }
        return decoded
    }

    public func saveStatistics(_ stats: ActivityStatistics) {
        let url = statsURL
        ioQueue.async {
            if let data = try? JSONEncoder().encode(stats) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Mac Health Score & Recommendations Engine

    public func evaluateHealth(
        telemetry: SystemTelemetrySnapshot,
        stats: ActivityStatistics,
        settings: RCleanerSettings,
        threatsFound: Int
    ) -> (score: Int, rating: MacHealthRating, recommendations: [AssistantRecommendation]) {
        var score = 100
        var recs: [AssistantRecommendation] = []

        if threatsFound > 0 {
            score -= 40
            recs.append(AssistantRecommendation(
                id: "malwareDetected",
                title: "React to found threats!",
                subtitle: "\(threatsFound) threat(s) detected. Take immediate action to stay protected.",
                actionTitle: "Review and Remove",
                iconName: "exclamationmark.shield.fill",
                severity: 2,
                targetModule: .protection,
                specialAction: nil
            ))
        }

        if !settings.enableRealTimeMalwareMonitor {
            score -= 10
            recs.append(AssistantRecommendation(
                id: "malwareMonitorOff",
                title: "Malware monitoring is off",
                subtitle: "Enable real-time monitoring to watch for threats the moment they appear.",
                actionTitle: "Open Protection",
                iconName: "shield.slash.fill",
                severity: 1,
                targetModule: .protection,
                specialAction: nil
            ))
        }

        let freeGB = Double(telemetry.storage.availableBytes) / 1_073_741_824.0
        if telemetry.storage.totalBytes > 0 && freeGB < Double(settings.warnLowDiskSpaceGB) {
            score -= 22
            recs.append(AssistantRecommendation(
                id: "lowDiskSpace",
                title: "You are low on disk space",
                subtitle: "Only \(ByteFormat.string(telemetry.storage.availableBytes)) of available storage left. Run Smart Care to reclaim space.",
                actionTitle: "Run Smart Care",
                iconName: "externaldrive.fill.badge.exclamationmark",
                severity: 2,
                targetModule: .smartCare,
                specialAction: nil
            ))
        }

        let trashGB = Double(telemetry.storage.trashBytes) / 1_073_741_824.0
        if trashGB >= Double(settings.notifyTrashExceedsGB) || telemetry.storage.trashBytes > 500 * 1024 * 1024 {
            score -= 8
            recs.append(AssistantRecommendation(
                id: "emptyTrash",
                title: "Empty your Trash",
                subtitle: "Your Trash Bin holds \(ByteFormat.string(telemetry.storage.trashBytes)) of deleted files.",
                actionTitle: "Empty Trash",
                iconName: "trash.fill",
                severity: 1,
                targetModule: .cleanup,
                specialAction: "emptyTrash"
            ))
        }

        if telemetry.memory.pressurePercent > 80 {
            score -= 12
            recs.append(AssistantRecommendation(
                id: "highMemory",
                title: "Heavy memory usage",
                subtitle: "RAM pressure is at \(Int(telemetry.memory.pressurePercent))%. Free up memory to keep apps snappy.",
                actionTitle: "Free Up RAM",
                iconName: "memorychip",
                severity: 1,
                targetModule: .performance,
                specialAction: "freeRAM"
            ))
        }

        if telemetry.battery.isPresent && telemetry.battery.healthPercent < 80 {
            score -= 12
            recs.append(AssistantRecommendation(
                id: "batteryHealth",
                title: "Battery health degraded",
                subtitle: "Battery maximum capacity is \(telemetry.battery.healthPercent)% (\(telemetry.battery.cycleCount) cycles).",
                actionTitle: "Check Battery",
                iconName: "battery.25",
                severity: 1,
                targetModule: nil,
                specialAction: nil
            ))
        }

        if telemetry.cpu.uptimeSeconds > 7 * 86400 {
            score -= 5
            recs.append(AssistantRecommendation(
                id: "uptimeRestart",
                title: "Restart your Mac once in a while",
                subtitle: "It's been \(ByteFormat.uptime(telemetry.cpu.uptimeSeconds)) since your last restart.",
                actionTitle: "Performance",
                iconName: "arrow.clockwise.circle.fill",
                severity: 0,
                targetModule: .performance,
                specialAction: nil
            ))
        }

        if !FileSystemHelpers.hasFullDiskAccess() {
            score -= 6
            recs.append(AssistantRecommendation(
                id: "allowFDA",
                title: "Allow Full Disk Access",
                subtitle: "Grant Full Disk Access in System Settings so R-Cleaner can inspect Mail, Safari, and protected caches.",
                actionTitle: "Allow Access…",
                iconName: "lock.open.fill",
                severity: 1,
                targetModule: nil,
                specialAction: "openFDA"
            ))
        }

        if stats.lastSmartCareDate == nil {
            score -= 10
            recs.append(AssistantRecommendation(
                id: "firstSmartCare",
                title: "You haven't run Smart Care yet",
                subtitle: "Start with a thorough scan of your entire Mac and breathe fresh air into it.",
                actionTitle: "Run Smart Care",
                iconName: "sparkles",
                severity: 1,
                targetModule: .smartCare,
                specialAction: nil
            ))
        } else if let last = stats.lastSmartCareDate, Date().timeIntervalSince(last) > 14 * 86400 {
            score -= 8
            recs.append(AssistantRecommendation(
                id: "regularSmartCare",
                title: "It's time to care for your Mac!",
                subtitle: "It's been over two weeks since your last Smart Care scan.",
                actionTitle: "Run Smart Care",
                iconName: "sparkles",
                severity: 1,
                targetModule: .smartCare,
                specialAction: nil
            ))
        }

        recs.append(AssistantRecommendation(
            id: "screenCleaning",
            title: "Your screen deserves some care",
            subtitle: "Keep your Mac clean inside and out with Screen Cleaning Mode.",
            actionTitle: "Try Screen Cleaning Mode",
            iconName: "display",
            severity: 0,
            targetModule: nil,
            specialAction: "screenCleaning"
        ))

        let clamped = max(10, min(100, score))
        let rating: MacHealthRating
        switch clamped {
        case 90...100: rating = .excellent
        case 75..<90: rating = .good
        case 60..<75: rating = .fair
        case 40..<60: rating = .requiresAttention
        default: rating = .critical
        }

        return (clamped, rating, recs.sorted { $0.severity > $1.severity })
    }
}
