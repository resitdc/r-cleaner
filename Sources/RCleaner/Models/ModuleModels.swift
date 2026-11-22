import Foundation
import SwiftUI

// MARK: - Sidebar Modules Navigation Hierarchy

public enum RCleanerModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case smartCare = "Smart Care"
    case cleanup = "Cleanup"
    case protection = "Protection"
    case performance = "Performance"
    case applications = "Applications"
    case myClutter = "My Clutter"
    case spaceLens = "Space Lens"
    case devAISweeper = "Dev & AI Sweeper"
    case portKiller = "Port Killer"
    case cloudCleanup = "Cloud Cleanup"
    case emailCleanup = "Email Cleanup"
    case myTools = "My Tools"
    case myActivity = "My Activity"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .smartCare: return "Quick maintenance that takes care of the essentials."
        case .cleanup: return "Clean your system to achieve maximum performance and reclaim free space."
        case .protection: return "Check your Mac for all kinds of threats and vulnerabilities."
        case .performance: return "Run recommended maintenance tasks to optimize your Mac's performance."
        case .applications: return "Take control of your applications. Uninstall, update or remove old leftovers."
        case .myClutter: return "Sort through your files and reduce the mess in just a few clicks."
        case .spaceLens: return "Visualize what's taking up the most disk space and clean up quickly."
        case .devAISweeper: return "Sweep stale node_modules, Rust/Swift/Gradle builds, Xcode, Docker, and local AI caches."
        case .portKiller: return "Inspect active TCP ports, identify local dev servers & project folders, and kill stuck ports in one click."
        case .cloudCleanup: return "Tidy up your cloud files to save space and keep your storage in check."
        case .emailCleanup: return "Clear out inbox clutter and unsubscribe from unwanted newsletters."
        case .myTools: return "Quick tools for focused tasks — clean up, protect, and maintain your Mac."
        case .myActivity: return "Track storage freed, malware scans, and total time saved."
        }
    }

    public var iconName: String {
        switch self {
        case .smartCare: return "sparkles"
        case .cleanup: return "trash.circle.fill"
        case .protection: return "shield.lefthalf.filled.badge.checkmark"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .applications: return "square.grid.2x2.fill"
        case .myClutter: return "doc.on.doc.fill"
        case .spaceLens: return "circle.hexagongrid.fill"
        case .devAISweeper: return "terminal.fill"
        case .portKiller: return "network.badge.shield.half.filled"
        case .cloudCleanup: return "icloud.fill"
        case .emailCleanup: return "envelope.badge.fill"
        case .myTools: return "wrench.and.screwdriver.fill"
        case .myActivity: return "chart.bar.xaxis"
        }
    }

    public var badgeText: String? {
        switch self {
        case .devAISweeper, .portKiller: return "New"
        default: return nil
        }
    }

    public var isPrimarySection: Bool {
        switch self {
        case .smartCare, .cleanup, .protection, .performance, .applications, .myClutter:
            return true
        default:
            return false
        }
    }
}

// MARK: - Module Lifecycle Stage

public enum ModuleStage: Equatable {
    case intro
    case scanning
    case resultsOverview
    case dataManager(categoryID: String?)
    case cleaning
    case complete
}

// MARK: - Generic Scan Node & Category

public struct ScanItem: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var path: String
    public var sizeBytes: Int64
    public var subtitle: String
    public var categoryID: String
    public var groupTitle: String
    public var isSelected: Bool
    public var isProtected: Bool
    public var protectionReason: String?
    public var lastModified: Date?
    public var lastAccessed: Date?
    public var badge: String?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        sizeBytes: Int64,
        subtitle: String = "",
        categoryID: String,
        groupTitle: String,
        isSelected: Bool = true,
        isProtected: Bool = false,
        protectionReason: String? = nil,
        lastModified: Date? = nil,
        lastAccessed: Date? = nil,
        badge: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.subtitle = subtitle
        self.categoryID = categoryID
        self.groupTitle = groupTitle
        self.isSelected = isProtected ? false : isSelected
        self.isProtected = isProtected
        self.protectionReason = protectionReason
        self.lastModified = lastModified
        self.lastAccessed = lastAccessed
        self.badge = badge
        self.metadata = metadata
    }
}

public struct ScanCategory: Identifiable, Hashable {
    public let id: String
    public var title: String
    public var description: String
    public var iconName: String
    public var badge: String?
    public var groups: [ScanGroup]

    public var totalBytes: Int64 {
        groups.reduce(0) { $0 + $1.totalBytes }
    }

    public var selectedBytes: Int64 {
        groups.reduce(0) { $0 + $1.selectedBytes }
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    public var selectedCount: Int {
        groups.reduce(0) { $0 + $1.selectedCount }
    }

    public var isAllSelected: Bool {
        let selectable = groups.flatMap(\.items).filter { !$0.isProtected }
        return !selectable.isEmpty && selectable.allSatisfy(\.isSelected)
    }

    public init(id: String, title: String, description: String, iconName: String, badge: String? = nil, groups: [ScanGroup] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.iconName = iconName
        self.badge = badge
        self.groups = groups
    }
}

public struct ScanGroup: Identifiable, Hashable {
    public let id: String
    public var title: String
    public var description: String
    public var iconName: String
    public var items: [ScanItem]

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public var selectedBytes: Int64 {
        items.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    public var isAllSelected: Bool {
        let selectable = items.filter { !$0.isProtected }
        return !selectable.isEmpty && selectable.allSatisfy(\.isSelected)
    }

    public init(id: String, title: String, description: String, iconName: String, items: [ScanItem] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.iconName = iconName
        self.items = items
    }
}

// MARK: - Cleanup Log

public struct CleanupLogEntry: Identifiable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let moduleName: String
    public let itemName: String
    public let path: String
    public let sizeBytes: Int64
    public let status: CleanupStatus
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        moduleName: String,
        itemName: String,
        path: String,
        sizeBytes: Int64,
        status: CleanupStatus,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.moduleName = moduleName
        self.itemName = itemName
        self.path = path
        self.sizeBytes = sizeBytes
        self.status = status
        self.errorMessage = errorMessage
    }
}

public enum CleanupStatus: String, Codable, Hashable {
    case cleaned = "Cleaned"
    case failed = "Failed"
    case stopped = "Stopped"
    case skipped = "Skipped"
}

public struct CleanupSummary {
    public var bytesFreed: Int64
    public var itemsProcessed: Int
    public var itemsFailed: Int
    public var logEntries: [CleanupLogEntry]
    public var title: String
    public var subtitle: String

    public init(
        bytesFreed: Int64 = 0,
        itemsProcessed: Int = 0,
        itemsFailed: Int = 0,
        logEntries: [CleanupLogEntry] = [],
        title: String = "Cleanup complete!",
        subtitle: String = "successfully cleaned"
    ) {
        self.bytesFreed = bytesFreed
        self.itemsProcessed = itemsProcessed
        self.itemsFailed = itemsFailed
        self.logEntries = logEntries
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Smart Care Pillar Result

public enum SmartCarePillarID: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case protection = "Protection"
    case performance = "Performance"
    case applications = "Applications"
    case myClutter = "My Clutter"

    public var id: String { rawValue }
}

public struct SmartCarePillarState: Identifiable {
    public let id: SmartCarePillarID
    public var title: String
    public var metricText: String
    public var subtitle: String
    public var status: PillarStatus
    public var iconName: String
    public var targetModule: RCleanerModule
    public var actionSizeBytes: Int64
    public var actionCount: Int
    public var isEnabled: Bool

    public enum PillarStatus: Equatable {
        case waiting
        case scanning
        case found
        case clean
        case running
        case completed
        case disabled
        case failed(String)
    }
}

// MARK: - Malware & Protection Models

public enum MalwareCategory: String, CaseIterable, Codable {
    case adware = "Adware"
    case backdoor = "Backdoor"
    case botnet = "Botnet"
    case dropper = "Dropper"
    case exploit = "Exploit"
    case installer = "Bundled Installer"
    case keylogger = "Keylogger"
    case miner = "Cryptominer"
    case pua = "PUA"
    case ransomware = "Ransomware"
    case riskware = "Riskware"
    case rootkit = "Rootkit"
    case spyware = "Spyware"
    case stealer = "Infostealer"
    case trojan = "Trojan"
    case virus = "Virus"
    case worm = "Worm"
    case other = "Suspicious Item"
}

public struct MalwareThreat: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let category: MalwareCategory
    public let severity: String
    public let reason: String
    public let sizeBytes: Int64
    public var isSelected: Bool = true
}

public struct AppPermissionEntry: Identifiable, Hashable {
    public let id = UUID()
    public let permissionKind: String
    public let permissionDescription: String
    public let iconName: String
    public let appName: String
    public let bundleID: String
    public let statusText: String
    public let isSystemManaged: Bool
    public var isSelected: Bool = false
}

// MARK: - Performance Models

public enum MaintenanceTaskKind: String, CaseIterable, Identifiable {
    case freeUpRAM = "Free Up RAM"
    case flushDNS = "Flush DNS Cache"
    case freeUpPurgeable = "Free Up Purgeable Space"
    case thinTimeMachine = "Thin Time Machine Snapshot"
    case reindexSpotlight = "Reindex Spotlight"
    case periodicScripts = "Run Periodic Scripts"
    case speedUpMail = "Speed Up Mail"
    case repairPermissions = "Repair Disk Permissions"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .freeUpRAM:
            return "Reclaims inactive and purgeable memory so your active apps and files respond faster."
        case .flushDNS:
            return "Clears the local DNS resolver cache to fix sluggish browsing or stale host lookups."
        case .freeUpPurgeable:
            return "Asks macOS to release space marked as purgeable (caches, temporary assets, redownloadable data)."
        case .thinTimeMachine:
            return "Shrinks local APFS Time Machine snapshots without removing or disabling your backups."
        case .reindexSpotlight:
            return "Rebuilds the Spotlight metadata index to restore fast, accurate system search."
        case .periodicScripts:
            return "Rotates system logs, removes temporary items, and runs macOS maintenance routines."
        case .speedUpMail:
            return "Vacuums and reindexes Apple Mail's Envelope Index SQLite database to speed up Inbox search."
        case .repairPermissions:
            return "Verifies user home directory and application support permissions to prevent app launch issues."
        }
    }

    public var iconName: String {
        switch self {
        case .freeUpRAM: return "memorychip"
        case .flushDNS: return "network"
        case .freeUpPurgeable: return "internaldrive"
        case .thinTimeMachine: return "clock.arrow.circlepath"
        case .reindexSpotlight: return "magnifyingglass"
        case .periodicScripts: return "terminal"
        case .speedUpMail: return "envelope.open"
        case .repairPermissions: return "lock.shield"
        }
    }

    public var requiresAdmin: Bool {
        switch self {
        case .flushDNS, .reindexSpotlight, .periodicScripts:
            return true
        default:
            return false
        }
    }
}

public struct MaintenanceTaskItem: Identifiable, Hashable {
    public let id: String
    public let kind: MaintenanceTaskKind
    public var isRecommended: Bool
    public var isSelected: Bool
    public var detailSubtitle: String
    public var lastRunDate: Date?
}

public struct StartupOrBackgroundItem: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let label: String
    public let path: String
    public let domain: String // "User Launch Agent", "System Launch Agent", "System Launch Daemon", "Login Item"
    public let isEnabled: Bool
    public let isLoginItem: Bool
    public var isSelected: Bool = false
}

// MARK: - Applications Models

public enum AppStoreSource: String, CaseIterable, Identifiable {
    case appStore = "App Store"
    case setapp = "Setapp"
    case steam = "Steam"
    case battleNet = "Battle.net"
    case other = "Other"

    public var id: String { rawValue }
}

public enum AppVendorGroup: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case adobe = "Adobe"
    case google = "Google"
    case jetBrains = "JetBrains"
    case microsoft = "Microsoft"
    case other = "Other"

    public var id: String { rawValue }
}

public struct AppResourceFile: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let group: String // Applications, Preferences, Supporting Files, Caches, Logs, Container, Crashes, Login Items, Plugins
    public let sizeBytes: Int64
    public var isSelected: Bool = true
}

public struct InstalledAppRecord: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let version: String
    public let path: String
    public let appSizeBytes: Int64
    public var relatedFiles: [AppResourceFile]
    public let lastOpenedDate: Date?
    public let store: AppStoreSource
    public let vendor: AppVendorGroup
    public let isSystemApp: Bool
    public let isAppStoreApp: Bool
    public let isSuspicious: Bool
    public let is32BitOrUnsupported: Bool
    public let isAudioPlugin: Bool
    public let sparkleFeedURL: String?
    public var isSelected: Bool = false

    public var totalSizeBytes: Int64 {
        appSizeBytes + relatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    public var isUnusedOverSixMonths: Bool {
        guard let last = lastOpenedDate else { return false }
        return Date().timeIntervalSince(last) > 180 * 86400
    }
}

public struct AppUpdateRecord: Identifiable, Hashable {
    public let id = UUID()
    public let appName: String
    public let bundleID: String
    public let currentVersion: String
    public let latestVersion: String
    public let source: String
    public let releaseNotes: String
    public let downloadURL: String?
    public let isMacOSUpdate: Bool
    public var isSelected: Bool = true
}

// MARK: - My Clutter Models

public struct DuplicateGroup: Identifiable, Hashable {
    public let id: String
    public let hash: String
    public let fileName: String
    public let fileKind: String
    public let singleFileSize: Int64
    public var copies: [DuplicateFileEntry]

    public var totalWastedBytes: Int64 {
        copies.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }
}

public struct DuplicateFileEntry: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let createdDate: Date?
    public let modifiedDate: Date?
    public var isOriginalRecommended: Bool
    public var isSelected: Bool
}

public struct SimilarImageGroup: Identifiable, Hashable {
    public let id = UUID()
    public let title: String
    public var images: [SimilarImageEntry]

    public var selectedBytes: Int64 {
        images.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }
}

public struct SimilarImageEntry: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let dimensions: String
    public let createdDate: Date?
    public let qualityScore: Double
    public let visualFlaws: [String] // "Blur", "Noise"
    public var isBestToKeep: Bool
    public var isSelected: Bool
}

// MARK: - Space Lens Models

public final class SpaceLensNode: Identifiable, ObservableObject {
    public let id: UUID = UUID()
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let isHidden: Bool
    public let isCloudItem: Bool
    public let isCloudOnlyEvicted: Bool
    public var sizeBytes: Int64
    public var itemCount: Int
    public var children: [SpaceLensNode]
    @Published public var isSelected: Bool = false

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        isHidden: Bool = false,
        isCloudItem: Bool = false,
        isCloudOnlyEvicted: Bool = false,
        sizeBytes: Int64 = 0,
        itemCount: Int = 1,
        children: [SpaceLensNode] = []
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isCloudItem = isCloudItem
        self.isCloudOnlyEvicted = isCloudOnlyEvicted
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.children = children
    }
}

// MARK: - Cloud & Email Cleanup Models

public enum CloudProviderKind: String, CaseIterable, Identifiable, Codable {
    case iCloud = "iCloud Drive"
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"
    case dropbox = "Dropbox"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .iCloud: return "icloud.fill"
        case .googleDrive: return "externaldrive.badge.icloud"
        case .oneDrive: return "cloud.fill"
        case .dropbox: return "shippingbox.fill"
        }
    }
}

public struct CloudAccountStatus: Identifiable, Hashable {
    public let id: String
    public let provider: CloudProviderKind
    public let rootPath: String?
    public var isDetected: Bool
    public var isConnected: Bool
    public var totalScannedBytes: Int64
    public var locallySyncedBytes: Int64
    public var cloudOnlyBytes: Int64
    public var items: [CloudFileItem]
}

public struct CloudFileItem: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let provider: CloudProviderKind
    public let sizeBytes: Int64
    public let isLocallySynced: Bool
    public let lastAccessed: Date?
    public let fileKind: String
    public var isSelected: Bool = false
}

public enum EmailCleanupCategory: String, CaseIterable, Identifiable {
    case smartCleanup = "Smart Cleanup"
    case newsletters = "Newsletters & Promotions"
    case subscriptions = "Subscriptions"
    case senders = "Senders"
    case drafts = "Drafts"
    case spam = "Spam"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .smartCleanup: return "wand.and.stars"
        case .newsletters: return "newspaper.fill"
        case .subscriptions: return "bell.slash.fill"
        case .senders: return "person.2.fill"
        case .drafts: return "doc.text.fill"
        case .spam: return "exclamationmark.octagon.fill"
        }
    }

    public var description: String {
        switch self {
        case .smartCleanup: return "Find emails worth cleaning up with ready-made suggestions."
        case .newsletters: return "Review promotional emails and newsletters you rarely read."
        case .subscriptions: return "Review your email subscriptions and unsubscribe from those you no longer read."
        case .senders: return "Review senders and clean up emails you no longer need."
        case .drafts: return "Review unfinished or unused drafts and free up email storage."
        case .spam: return "Clear out unwanted emails already marked as spam."
        }
    }
}

public struct EmailMessageItem: Identifiable, Hashable {
    public let id = UUID()
    public let subject: String
    public let senderName: String
    public let senderEmail: String
    public let snippet: String
    public let date: Date
    public let sizeBytes: Int64
    public let hasAttachments: Bool
    public let isUnread: Bool
    public let hasUnsubscribeHeader: Bool
    public let category: EmailCleanupCategory
    public let suggestionTag: String
    public let filePath: String?
    public var isSelected: Bool = false
}

// MARK: - Activity Statistics & Assistant Health Models

public enum MacHealthRating: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case requiresAttention = "Requires Attention"
    case critical = "Critical"

    public var descriptionText: String {
        switch self {
        case .excellent: return "Your Mac is doing great. Run regular maintenance to keep it this way."
        case .good: return "Your Mac is in good shape. Run some maintenance to make it perform even better."
        case .fair: return "Your Mac is OK, but some maintenance activities are recommended."
        case .requiresAttention: return "Your Mac is not doing well. Run some maintenance to bring it back into shape."
        case .critical: return "We strongly recommend taking action to bring your Mac back to normal."
        }
    }
}

public struct AssistantRecommendation: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let actionTitle: String
    public let iconName: String
    public let severity: Int // 0 info, 1 medium, 2 high
    public let targetModule: RCleanerModule?
    public let specialAction: String? // "screenCleaning", "emptyTrash", "openFDA", "freeRAM"
}

public struct ActivityStatistics: Codable, Equatable {
    public var firstUsedDate: Date
    public var totalSystemJunkCleanedBytes: Int64
    public var totalPersonalFilesCleanedBytes: Int64
    public var totalApplicationsCleanedBytes: Int64
    public var totalCloudCleanedBytes: Int64
    public var monthlyCleanedBytes: Int64
    public var totalMalwareItemsScanned: Int
    public var totalThreatsRemoved: Int
    public var totalMaintenanceTasksRun: Int
    public var totalAppsUninstalled: Int
    public var totalDuplicatesRemoved: Int
    public var totalTimeSavedMinutes: Int
    public var lastSmartCareDate: Date?
    public var lastMalwareScanDate: Date?
    public var lastScreenCleanDate: Date?

    public var totalLocalCleanedBytes: Int64 {
        totalSystemJunkCleanedBytes + totalPersonalFilesCleanedBytes + totalApplicationsCleanedBytes
    }

    public static let empty = ActivityStatistics(
        firstUsedDate: Date(),
        totalSystemJunkCleanedBytes: 0,
        totalPersonalFilesCleanedBytes: 0,
        totalApplicationsCleanedBytes: 0,
        totalCloudCleanedBytes: 0,
        monthlyCleanedBytes: 0,
        totalMalwareItemsScanned: 0,
        totalThreatsRemoved: 0,
        totalMaintenanceTasksRun: 0,
        totalAppsUninstalled: 0,
        totalDuplicatesRemoved: 0,
        totalTimeSavedMinutes: 0,
        lastSmartCareDate: nil,
        lastMalwareScanDate: nil,
        lastScreenCleanDate: nil
    )
}

// MARK: - Quick Tool (Toolbox / My Tools)

public struct QuickToolItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let description: String
    public let iconName: String
    public let keywords: [String]
    public let badge: String?
    public let targetModule: RCleanerModule
    public let focusedFlowID: String
    public let accentHex: String
}

// MARK: - Dev & AI Storage Sweeper Models

public enum DevAISweeperCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case projectArtifacts = "Project Artifacts"
    case xcodeMobile = "Xcode & Mobile"
    case packageCaches = "Package Caches"
    case dockerContainers = "Docker & Containers"
    case aiModelsAndCaches = "AI & Models"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .projectArtifacts: return "folder.badge.gearshape"
        case .xcodeMobile: return "hammer.fill"
        case .packageCaches: return "shippingbox.fill"
        case .dockerContainers: return "cube.transparent.fill"
        case .aiModelsAndCaches: return "brain.head.profile"
        }
    }

    public var accentHex: String {
        switch self {
        case .projectArtifacts: return "00F5D4"
        case .xcodeMobile: return "38BDF8"
        case .packageCaches: return "FFB703"
        case .dockerContainers: return "60A5FA"
        case .aiModelsAndCaches: return "C77DFF"
        }
    }

    public var summaryDescription: String {
        switch self {
        case .projectArtifacts: return "Regenerable build folders (node_modules, target, .build, .venv, Pods, Gradle build)."
        case .xcodeMobile: return "Xcode DerivedData, DeviceSupport, Simulators, and Android SDK / AVD caches."
        case .packageCaches: return "Global package manager stores and download caches (npm, pnpm, Cargo, Gradle, Go, Homebrew, uv)."
        case .dockerContainers: return "Reclaimable Docker & OrbStack build caches, dangling images, and stopped containers."
        case .aiModelsAndCaches: return "Local LLM weights (Ollama, LM Studio, HuggingFace) and AI coding tool caches."
        }
    }
}

public enum DevAIActionKind: Hashable, Codable, Sendable {
    case filesystemPath
    case ollamaModel(blobPaths: [String])
    case dockerPrune(binaryPath: String, arguments: [String])
}

public struct DevAIArtifactItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var projectName: String
    public var ecosystem: String
    public var category: DevAISweeperCategory
    public var path: String
    public var sizeBytes: Int64
    public var itemCount: Int
    public var ageDays: Int?
    public var rebuildHint: String
    public var badge: String?
    public var isSafeAutoSelect: Bool
    public var isSelected: Bool
    public var actionKind: DevAIActionKind

    public init(
        id: UUID = UUID(),
        name: String,
        projectName: String,
        ecosystem: String,
        category: DevAISweeperCategory,
        path: String,
        sizeBytes: Int64,
        itemCount: Int = 0,
        ageDays: Int? = nil,
        rebuildHint: String,
        badge: String? = nil,
        isSafeAutoSelect: Bool = false,
        isSelected: Bool = false,
        actionKind: DevAIActionKind = .filesystemPath
    ) {
        self.id = id
        self.name = name
        self.projectName = projectName
        self.ecosystem = ecosystem
        self.category = category
        self.path = path
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.ageDays = ageDays
        self.rebuildHint = rebuildHint
        self.badge = badge
        self.isSafeAutoSelect = isSafeAutoSelect
        self.isSelected = isSelected
        self.actionKind = actionKind
    }
}

public struct DevAISweeperScanResult: Sendable {
    public var items: [DevAIArtifactItem] = []
    public var scannedWorkspaces: [String] = []
    public var scanDurationSeconds: Double = 0
    public var dockerDetected: Bool = false
    public var dockerStatusNote: String? = nil

    public init() {}

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var selectedBytes: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes } }
    public var selectedCount: Int { items.filter(\.isSelected).count }

    public func bytes(for category: DevAISweeperCategory) -> Int64 {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.sizeBytes }
    }

    public func count(for category: DevAISweeperCategory) -> Int {
        items.filter { $0.category == category }.count
    }
}

// MARK: - Active Port & Local Server Killer Models

public enum PortServiceCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case devWebServer = "Dev & Web Servers"
    case databaseCache = "Databases & Cache"
    case aiAndMobile = "AI & Mobile SDKs"
    case ideAndTools = "IDE & Desktop Apps"
    case macOSSystem = "macOS Services"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .devWebServer: return "Dev Servers"
        case .databaseCache: return "Databases"
        case .aiAndMobile: return "AI & Mobile"
        case .ideAndTools: return "IDEs & Apps"
        case .macOSSystem: return "macOS"
        }
    }

    public var iconName: String {
        switch self {
        case .devWebServer: return "globe"
        case .databaseCache: return "cylinder.split.1x2.fill"
        case .aiAndMobile: return "cpu.fill"
        case .ideAndTools: return "hammer.fill"
        case .macOSSystem: return "apple.logo"
        }
    }

    public var accentHex: String {
        switch self {
        case .devWebServer: return "00F5D4"
        case .databaseCache: return "FFB703"
        case .aiAndMobile: return "C77DFF"
        case .ideAndTools: return "38BDF8"
        case .macOSSystem: return "94A3B8"
        }
    }
}

public struct ActivePortItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(pid)-\(port)" }
    public let port: Int
    public let pid: Int32
    public let processName: String
    public let displayTitle: String
    public let frameworkLabel: String
    public let category: PortServiceCategory
    public let bindAddress: String
    public let isExposedToLAN: Bool
    public let workingDirectory: String?
    public let projectDisplayName: String?
    public let commandLine: String
    public let executablePath: String?
    public let cpuPercent: Double
    public let memoryBytes: Int64
    public let uptimeLabel: String
    public let isSystemProtected: Bool
    public var isSelected: Bool

    public var localWebURL: URL? {
        // Common HTTP/web server ports or dev servers
        let webPorts: Set<Int> = [80, 443, 3000, 3001, 3002, 4000, 4173, 4200, 4321, 5000, 5173, 5174, 5175, 5500, 8000, 8080, 8081, 8787, 8888, 9000, 11434]
        if category == .devWebServer || webPorts.contains(port) || (port >= 3000 && port <= 9999 && category != .databaseCache) {
            return URL(string: "http://localhost:\(port)")
        }
        return nil
    }

    public init(
        port: Int,
        pid: Int32,
        processName: String,
        displayTitle: String,
        frameworkLabel: String,
        category: PortServiceCategory,
        bindAddress: String,
        isExposedToLAN: Bool,
        workingDirectory: String?,
        projectDisplayName: String?,
        commandLine: String,
        executablePath: String?,
        cpuPercent: Double,
        memoryBytes: Int64,
        uptimeLabel: String,
        isSystemProtected: Bool,
        isSelected: Bool = false
    ) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.displayTitle = displayTitle
        self.frameworkLabel = frameworkLabel
        self.category = category
        self.bindAddress = bindAddress
        self.isExposedToLAN = isExposedToLAN
        self.workingDirectory = workingDirectory
        self.projectDisplayName = projectDisplayName
        self.commandLine = commandLine
        self.executablePath = executablePath
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.uptimeLabel = uptimeLabel
        self.isSystemProtected = isSystemProtected
        self.isSelected = isSelected
    }
}

public struct PortKillerSnapshot: Sendable {
    public var items: [ActivePortItem] = []
    public var lastUpdated: Date = Date()

    public init(items: [ActivePortItem] = [], lastUpdated: Date = Date()) {
        self.items = items
        self.lastUpdated = lastUpdated
    }

    public var totalMemoryBytes: Int64 {
        // Sum unique PIDs so a process listening on 2 ports isn't double-counted
        var seen = Set<Int32>()
        var sum: Int64 = 0
        for item in items where seen.insert(item.pid).inserted {
            sum += item.memoryBytes
        }
        return sum
    }

    public var devServersCount: Int {
        items.filter { $0.category == .devWebServer }.count
    }

    public var databasesAndAICount: Int {
        items.filter { $0.category == .databaseCache || $0.category == .aiAndMobile }.count
    }

    public var lanExposedCount: Int {
        items.filter(\.isExposedToLAN).count
    }

    public func count(for category: PortServiceCategory) -> Int {
        items.filter { $0.category == category }.count
    }
}
