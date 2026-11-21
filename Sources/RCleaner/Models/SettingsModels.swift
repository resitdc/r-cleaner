import Foundation

public enum MalwareScanMode: String, CaseIterable, Codable, Identifiable {
    case quick = "Quick Scan"
    case balanced = "Balanced Scan"
    case deep = "Deep Scan"

    public var id: String { rawValue }

    public var depthLabel: String {
        switch self {
        case .quick: return "Surface-level"
        case .balanced: return "Intermediate"
        case .deep: return "Comprehensive"
        }
    }

    public var speedLabel: String {
        switch self {
        case .quick: return "Fastest"
        case .balanced: return "Moderate"
        case .deep: return "Slowest"
        }
    }

    public var purposeDescription: String {
        switch self {
        case .quick:
            return "Scans the most vulnerable areas of your system (LaunchAgents, Login Items, Downloads, Applications) for immediate threats."
        case .balanced:
            return "Offers a blend of speed and thoroughness across system persistence locations, user libraries, and downloads."
        case .deep:
            return "Conducts an exhaustive examination across your home folder, applications, libraries, and mounted volumes."
        }
    }
}

public enum IgnoreListCategory: String, CaseIterable, Codable, Identifiable {
    case systemJunk = "System Junk"
    case aiClutter = "AI Clutter"
    case devAISweeper = "Dev & AI Sweeper"
    case mailAttachments = "Mail Attachments"
    case malwareRemoval = "Malware Removal"
    case uninstaller = "Uninstaller"
    case updater = "Updater"
    case duplicates = "Duplicates"
    case similar = "Similar"
    case largeAndOldFiles = "Large & Old Files"
    case downloads = "Downloads"

    public var id: String { rawValue }
}

public struct IgnoredItem: Identifiable, Hashable, Codable {
    public let id: UUID
    public let category: IgnoreListCategory
    public let path: String
    public let displayName: String
    public let itemDescription: String
    public let addedDate: Date

    public init(
        id: UUID = UUID(),
        category: IgnoreListCategory,
        path: String,
        displayName: String,
        itemDescription: String = "Excluded item",
        addedDate: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.path = path
        self.displayName = displayName
        self.itemDescription = itemDescription
        self.addedDate = addedDate
    }
}

public enum ReminderFrequency: String, CaseIterable, Codable, Identifiable {
    case threeDays = "Once in 3 Days"
    case weekly = "Weekly"
    case biweekly = "Every 2 Weeks"
    case monthly = "Monthly"

    public var id: String { rawValue }
}

public struct RCleanerSettings: Codable, Equatable {
    // General
    public var hasCompletedIntro: Bool = false
    public var playSounds: Bool = true
    public var reduceMotion: Bool = false
    public var showAssistantRecommendations: Bool = true
    public var enableSmartInsights: Bool = true
    public var checkUpdatesAutomatically: Bool = true

    // Voice AI System (Bundled Neural Voice Pack + Built-in macOS TTS)
    public var enableVoiceAssistant: Bool = true
    public var useBundledVoicePack: Bool = true
    public var enableVoiceHudEffects: Bool = true
    public var voiceIdentifier: String = ""
    public var voiceRate: Double = 0.49
    public var voicePitch: Double = 0.92
    public var voiceAddressTitle: String = "sir"

    // Smart Care Modules Enabled
    public var smartCareCleanupEnabled: Bool = true
    public var smartCareProtectionEnabled: Bool = true
    public var smartCarePerformanceEnabled: Bool = true
    public var smartCareApplicationsEnabled: Bool = true
    public var smartCareMyClutterEnabled: Bool = true

    // Cleanup Categories Enabled
    public var scanSystemJunk: Bool = true
    public var scanMailAttachments: Bool = true
    public var scanTrashBins: Bool = true
    public var scanAIClutter: Bool = true

    // Protection
    public var malwareScanMode: MalwareScanMode = .balanced
    public var enableRealTimeMalwareMonitor: Bool = true
    public var enableBackgroundScan: Bool = true
    public var scanArchives: Bool = true
    public var scanDMGImages: Bool = false
    public var scanEmailAttachments: Bool = true
    public var scanUSBDrives: Bool = true
    public var excludeDownloadedICloudFiles: Bool = true

    // Uninstaller
    public var ignoreSystemApplications: Bool = true

    // Menu
    public var enableMenuMonitor: Bool = true
    public var openMenuAtLogin: Bool = false
    public var enableMenuRecommendations: Bool = true
    public var autoCleanExternalDrivesOnEject: Bool = false

    // Notifications
    public var remindSmartCare: Bool = true
    public var smartCareReminderFrequency: ReminderFrequency = .weekly
    public var remindScreenCleaning: Bool = false
    public var warnLowDiskSpaceGB: Int = 15
    public var notifyTrashExceedsGB: Int = 2
    public var notifyLowRAM: Bool = true
    public var notifyHeavyChrome: Bool = true
    public var notifyHungApps: Bool = true
    public var notifyTrashedApps: Bool = true
    public var notifyBluetoothLowBattery: Bool = true

    // Dev & AI Sweeper
    public var devCustomWorkspacePaths: [String] = []
    public var devStaleDaysThreshold: Int = 30

    // Ignore list
    public var ignoredItems: [IgnoredItem] = []

    // Favorite quick tools
    public var favoriteToolIDs: [String] = [
        "devAISweeper", "systemJunk", "aiClutter", "malwareFinder", "maintenanceTasks", "uninstaller", "screenCleaning"
    ]

    public init() {}

    /// Resilient decoder: missing keys from older settings.json versions fall back to defaults
    /// instead of wiping all saved user settings and Ignore List entries on app upgrade.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RCleanerSettings()
        hasCompletedIntro = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedIntro)) ?? d.hasCompletedIntro
        playSounds = (try? c.decodeIfPresent(Bool.self, forKey: .playSounds)) ?? d.playSounds
        reduceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reduceMotion)) ?? d.reduceMotion
        showAssistantRecommendations = (try? c.decodeIfPresent(Bool.self, forKey: .showAssistantRecommendations)) ?? d.showAssistantRecommendations
        enableSmartInsights = (try? c.decodeIfPresent(Bool.self, forKey: .enableSmartInsights)) ?? d.enableSmartInsights
        checkUpdatesAutomatically = (try? c.decodeIfPresent(Bool.self, forKey: .checkUpdatesAutomatically)) ?? d.checkUpdatesAutomatically

        enableVoiceAssistant = (try? c.decodeIfPresent(Bool.self, forKey: .enableVoiceAssistant)) ?? d.enableVoiceAssistant
        useBundledVoicePack = (try? c.decodeIfPresent(Bool.self, forKey: .useBundledVoicePack)) ?? d.useBundledVoicePack
        enableVoiceHudEffects = (try? c.decodeIfPresent(Bool.self, forKey: .enableVoiceHudEffects)) ?? d.enableVoiceHudEffects
        voiceIdentifier = (try? c.decodeIfPresent(String.self, forKey: .voiceIdentifier)) ?? d.voiceIdentifier
        voiceRate = (try? c.decodeIfPresent(Double.self, forKey: .voiceRate)) ?? d.voiceRate
        voicePitch = (try? c.decodeIfPresent(Double.self, forKey: .voicePitch)) ?? d.voicePitch
        voiceAddressTitle = (try? c.decodeIfPresent(String.self, forKey: .voiceAddressTitle)) ?? d.voiceAddressTitle

        smartCareCleanupEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .smartCareCleanupEnabled)) ?? d.smartCareCleanupEnabled
        smartCareProtectionEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .smartCareProtectionEnabled)) ?? d.smartCareProtectionEnabled
        smartCarePerformanceEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .smartCarePerformanceEnabled)) ?? d.smartCarePerformanceEnabled
        smartCareApplicationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .smartCareApplicationsEnabled)) ?? d.smartCareApplicationsEnabled
        smartCareMyClutterEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .smartCareMyClutterEnabled)) ?? d.smartCareMyClutterEnabled

        scanSystemJunk = (try? c.decodeIfPresent(Bool.self, forKey: .scanSystemJunk)) ?? d.scanSystemJunk
        scanMailAttachments = (try? c.decodeIfPresent(Bool.self, forKey: .scanMailAttachments)) ?? d.scanMailAttachments
        scanTrashBins = (try? c.decodeIfPresent(Bool.self, forKey: .scanTrashBins)) ?? d.scanTrashBins
        scanAIClutter = (try? c.decodeIfPresent(Bool.self, forKey: .scanAIClutter)) ?? d.scanAIClutter

        malwareScanMode = (try? c.decodeIfPresent(MalwareScanMode.self, forKey: .malwareScanMode)) ?? d.malwareScanMode
        enableRealTimeMalwareMonitor = (try? c.decodeIfPresent(Bool.self, forKey: .enableRealTimeMalwareMonitor)) ?? d.enableRealTimeMalwareMonitor
        enableBackgroundScan = (try? c.decodeIfPresent(Bool.self, forKey: .enableBackgroundScan)) ?? d.enableBackgroundScan
        scanArchives = (try? c.decodeIfPresent(Bool.self, forKey: .scanArchives)) ?? d.scanArchives
        scanDMGImages = (try? c.decodeIfPresent(Bool.self, forKey: .scanDMGImages)) ?? d.scanDMGImages
        scanEmailAttachments = (try? c.decodeIfPresent(Bool.self, forKey: .scanEmailAttachments)) ?? d.scanEmailAttachments
        scanUSBDrives = (try? c.decodeIfPresent(Bool.self, forKey: .scanUSBDrives)) ?? d.scanUSBDrives
        excludeDownloadedICloudFiles = (try? c.decodeIfPresent(Bool.self, forKey: .excludeDownloadedICloudFiles)) ?? d.excludeDownloadedICloudFiles

        ignoreSystemApplications = (try? c.decodeIfPresent(Bool.self, forKey: .ignoreSystemApplications)) ?? d.ignoreSystemApplications

        enableMenuMonitor = (try? c.decodeIfPresent(Bool.self, forKey: .enableMenuMonitor)) ?? d.enableMenuMonitor
        openMenuAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .openMenuAtLogin)) ?? d.openMenuAtLogin
        enableMenuRecommendations = (try? c.decodeIfPresent(Bool.self, forKey: .enableMenuRecommendations)) ?? d.enableMenuRecommendations
        autoCleanExternalDrivesOnEject = (try? c.decodeIfPresent(Bool.self, forKey: .autoCleanExternalDrivesOnEject)) ?? d.autoCleanExternalDrivesOnEject

        remindSmartCare = (try? c.decodeIfPresent(Bool.self, forKey: .remindSmartCare)) ?? d.remindSmartCare
        smartCareReminderFrequency = (try? c.decodeIfPresent(ReminderFrequency.self, forKey: .smartCareReminderFrequency)) ?? d.smartCareReminderFrequency
        remindScreenCleaning = (try? c.decodeIfPresent(Bool.self, forKey: .remindScreenCleaning)) ?? d.remindScreenCleaning
        warnLowDiskSpaceGB = (try? c.decodeIfPresent(Int.self, forKey: .warnLowDiskSpaceGB)) ?? d.warnLowDiskSpaceGB
        notifyTrashExceedsGB = (try? c.decodeIfPresent(Int.self, forKey: .notifyTrashExceedsGB)) ?? d.notifyTrashExceedsGB
        notifyLowRAM = (try? c.decodeIfPresent(Bool.self, forKey: .notifyLowRAM)) ?? d.notifyLowRAM
        notifyHeavyChrome = (try? c.decodeIfPresent(Bool.self, forKey: .notifyHeavyChrome)) ?? d.notifyHeavyChrome
        notifyHungApps = (try? c.decodeIfPresent(Bool.self, forKey: .notifyHungApps)) ?? d.notifyHungApps
        notifyTrashedApps = (try? c.decodeIfPresent(Bool.self, forKey: .notifyTrashedApps)) ?? d.notifyTrashedApps
        notifyBluetoothLowBattery = (try? c.decodeIfPresent(Bool.self, forKey: .notifyBluetoothLowBattery)) ?? d.notifyBluetoothLowBattery

        devCustomWorkspacePaths = (try? c.decodeIfPresent([String].self, forKey: .devCustomWorkspacePaths)) ?? d.devCustomWorkspacePaths
        devStaleDaysThreshold = (try? c.decodeIfPresent(Int.self, forKey: .devStaleDaysThreshold)) ?? d.devStaleDaysThreshold

        ignoredItems = (try? c.decodeIfPresent([IgnoredItem].self, forKey: .ignoredItems)) ?? d.ignoredItems
        favoriteToolIDs = (try? c.decodeIfPresent([String].self, forKey: .favoriteToolIDs)) ?? d.favoriteToolIDs
    }
}
