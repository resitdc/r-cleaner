import Foundation

public struct CPUReading {
    public var userPercent: Double = 0
    public var systemPercent: Double = 0
    public var idlePercent: Double = 100
    public var totalLoadPercent: Double { min(100, userPercent + systemPercent) }
    public var uptimeSeconds: TimeInterval = 0
    public var coreCount: Int = ProcessInfo.processInfo.processorCount
    public var history: [Double] = Array(repeating: 0, count: 30)
}

public struct MemoryReading {
    public var totalBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    public var activeBytes: Int64 = 0
    public var wiredBytes: Int64 = 0
    public var compressedBytes: Int64 = 0
    public var freeBytes: Int64 = 0
    public var swapUsedBytes: Int64 = 0
    public var swapTotalBytes: Int64 = 0

    public var usedBytes: Int64 {
        max(0, activeBytes + wiredBytes + compressedBytes)
    }

    public var availableBytes: Int64 {
        max(0, totalBytes - usedBytes)
    }

    public var pressurePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, (Double(usedBytes) / Double(totalBytes)) * 100.0)
    }

    public var pressureLabel: String {
        switch pressurePercent {
        case 0..<65: return "Normal"
        case 65..<85: return "Moderate"
        default: return "High"
        }
    }
}

public struct StorageReading {
    public var volumeName: String = "Macintosh HD"
    public var totalBytes: Int64 = 0
    public var availableBytes: Int64 = 0
    public var purgeableBytes: Int64 = 0
    public var trashBytes: Int64 = 0

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, (Double(usedBytes) / Double(totalBytes)) * 100.0)
    }
}

public struct BatteryReading {
    public var isPresent: Bool = false
    public var percentage: Int = 100
    public var isCharging: Bool = false
    public var isCharged: Bool = false
    public var timeRemainingMinutes: Int? = nil
    public var cycleCount: Int = 0
    public var healthPercent: Int = 100
    public var condition: String = "Normal"
    public var temperatureCelsius: Double? = nil
    public var powerWatts: Double? = nil

    public var statusText: String {
        if !isPresent { return "AC Power" }
        if isCharged { return "Fully Charged" }
        if isCharging {
            if let m = timeRemainingMinutes, m > 0 {
                return "Charging • \(m / 60)h \(m % 60)m until full"
            }
            return "Charging"
        }
        if let m = timeRemainingMinutes, m > 0 {
            return "\(m / 60)h \(m % 60)m remaining"
        }
        return "Discharging"
    }
}

public struct NetworkReading {
    public var isConnected: Bool = true
    public var connectionType: String = "Wi-Fi"
    public var interfaceName: String = "en0"
    public var networkName: String = "Connected Network"
    public var securityRating: String = "Strong"
    public var downloadBytesPerSec: Double = 0
    public var uploadBytesPerSec: Double = 0
    public var totalDownloadedBytes: Int64 = 0
    public var totalUploadedBytes: Int64 = 0
    public var lastSpeedTestMbps: Double? = nil
    public var isTestingSpeed: Bool = false
}

public struct ProcessConsumer: Identifiable, Hashable {
    public let id: Int32 // pid
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: Int64
    public let isNotResponding: Bool
}

public struct ExternalDriveInfo: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let mountPath: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let isReadOnly: Bool
    public var junkBytes: Int64
}

public enum ThermalStateLevel: String, Codable, Sendable {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"

    public var shortLabel: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Throttling"
        }
    }

    public var descriptionText: String {
        switch self {
        case .nominal: return "Cool & optimal thermal headroom"
        case .fair: return "Slightly warm under active load"
        case .serious: return "High thermal pressure — fans / throttling active"
        case .critical: return "Critical heat — performance throttled"
        }
    }

    public var accentHex: String {
        switch self {
        case .nominal: return "2ED573"
        case .fair: return "FFD166"
        case .serious: return "FF9F43"
        case .critical: return "FF5E57"
        }
    }
}

public struct ThermalReading: Sendable {
    public var state: ThermalStateLevel = .nominal
    public var temperatureCelsius: Double? = nil
    public var isLowPowerMode: Bool = false
}

public struct ProcessNetworkConsumer: Identifiable, Hashable, Sendable {
    public let id: Int32 // pid
    public let name: String
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let totalInBytes: Int64
    public let totalOutBytes: Int64

    public var totalRateBytesPerSec: Double {
        downloadBytesPerSec + uploadBytesPerSec
    }
}

public enum SmartAlertKind: String, Hashable, Sendable {
    case lowDisk
    case criticalRAM
    case runawayCPU
    case thermalPressure
}

public struct JarvisSmartAlert: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: SmartAlertKind
    public let title: String
    public let message: String
    public let iconName: String
    public let accentHex: String
    public let triggeredAt: Date
    public let processID: Int32?
    public let processName: String?

    public init(
        kind: SmartAlertKind,
        title: String,
        message: String,
        iconName: String,
        accentHex: String,
        triggeredAt: Date = Date(),
        processID: Int32? = nil,
        processName: String? = nil
    ) {
        self.id = kind.rawValue + (processID.map { "-\($0)" } ?? "")
        self.kind = kind
        self.title = title
        self.message = message
        self.iconName = iconName
        self.accentHex = accentHex
        self.triggeredAt = triggeredAt
        self.processID = processID
        self.processName = processName
    }
}

public struct SystemTelemetrySnapshot {
    public var cpu = CPUReading()
    public var memory = MemoryReading()
    public var storage = StorageReading()
    public var battery = BatteryReading()
    public var thermal = ThermalReading()
    public var network = NetworkReading()
    public var topCPUConsumers: [ProcessConsumer] = []
    public var topMemoryConsumers: [ProcessConsumer] = []
    public var topNetworkConsumers: [ProcessNetworkConsumer] = []
    public var externalDrives: [ExternalDriveInfo] = []
    public var lastUpdated: Date = Date()
}
