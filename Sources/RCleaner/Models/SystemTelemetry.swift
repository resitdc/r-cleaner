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

public struct SystemTelemetrySnapshot {
    public var cpu = CPUReading()
    public var memory = MemoryReading()
    public var storage = StorageReading()
    public var battery = BatteryReading()
    public var network = NetworkReading()
    public var topCPUConsumers: [ProcessConsumer] = []
    public var topMemoryConsumers: [ProcessConsumer] = []
    public var externalDrives: [ExternalDriveInfo] = []
    public var lastUpdated: Date = Date()
}
