import Foundation
import SwiftUI
import AppKit

@MainActor
public final class AppState: ObservableObject {
    // Services
    public let telemetryService = SystemTelemetryService()
    public let cleanupService = CleanupScannerService()
    public let protectionService = ProtectionScannerService()
    public let performanceService = PerformanceService()
    public let applicationsService = ApplicationsService()
    public let clutterService = ClutterScannerService()
    public let spaceLensService = SpaceLensService()
    public let devAISweeperService = DevAISweeperService()
    public let portKillerService = PortKillerService()
    public let cloudEmailService = CloudAndEmailService()
    public let assistantService = AssistantService()
    public let voiceService = VoiceAssistantService()
    public let voiceCommandService = VoiceCommandService()
    public let updaterService = AppUpdaterService()

    // Navigation & Global UI
    @Published public var selectedModule: RCleanerModule = .smartCare
    @Published public var showIntroFlow: Bool = true
    @Published public var showAssistantPopover: Bool = false
    @Published public var showSettingsWindow: Bool = false
    @Published public var showUpdateSheet: Bool = false
    @Published public var showClearCommandDeck: Bool = false
    @Published public var isScreenCleaningActive: Bool = false
    @Published public var statusBannerMessage: String? = nil

    // GitHub Releases Updater State
    @Published public var updateState: AppUpdateState = .idle
    @Published public var availableUpdate: AppReleaseInfo? = nil
    @Published public var lastUpdateCheckDate: Date? = nil

    // Persisted Settings & Statistics
    @Published public var settings: RCleanerSettings {
        didSet {
            guard settings != oldValue else { return }
            assistantService.saveSettings(settings)
            refreshHealthScore()
            evaluateSmartGuardAlerts(snapshot: telemetry)
        }
    }
    @Published public var stats: ActivityStatistics {
        didSet {
            guard stats != oldValue else { return }
            assistantService.saveStatistics(stats)
            refreshHealthScore()
        }
    }

    // Live Telemetry & Health
    @Published public var telemetry = SystemTelemetrySnapshot()
    @Published public var healthScore: Int = 92
    @Published public var healthRating: MacHealthRating = .excellent
    @Published public var recommendations: [AssistantRecommendation] = []
    @Published public var activeSmartAlerts: [ClearSmartAlert] = []
    private let smartGuard = ClearSmartGuardEvaluator()
    private var dismissedAlertIDs: Set<String> = []

    // Smart Care State
    @Published public var smartCareStage: ModuleStage = .intro
    @Published public var smartCarePillars: [SmartCarePillarState] = []
    @Published public var smartCareStatusText: String = ""
    @Published public var smartCareProgress: Double = 0
    @Published public var smartCareSummary: CleanupSummary? = nil

    // Cleanup State
    @Published public var cleanupStage: ModuleStage = .intro
    @Published public var cleanupCategories: [ScanCategory] = []
    @Published public var cleanupStatusText: String = ""
    @Published public var cleanupProgress: Double = 0
    @Published public var cleanupSummary: CleanupSummary? = nil
    @Published public var cleanupFocusedCategory: String? = nil

    // Protection State
    @Published public var protectionStage: ModuleStage = .intro
    @Published public var protectionResult = ProtectionScanResult()
    @Published public var protectionStatusText: String = ""
    @Published public var protectionProgress: Double = 0
    @Published public var protectionSummary: CleanupSummary? = nil

    // Performance State
    @Published public var performanceStage: ModuleStage = .intro
    @Published public var performanceResult = PerformanceScanResult()
    @Published public var performanceStatusText: String = ""
    @Published public var performanceProgress: Double = 0
    @Published public var performanceSummary: CleanupSummary? = nil

    // Applications State
    @Published public var applicationsStage: ModuleStage = .intro
    @Published public var applicationsResult = ApplicationsScanResult()
    @Published public var applicationsStatusText: String = ""
    @Published public var applicationsProgress: Double = 0
    @Published public var applicationsSummary: CleanupSummary? = nil

    // My Clutter State
    @Published public var clutterStage: ModuleStage = .intro
    @Published public var clutterResult = ClutterScanResult()
    @Published public var clutterStatusText: String = ""
    @Published public var clutterProgress: Double = 0
    @Published public var clutterSummary: CleanupSummary? = nil
    @Published public var clutterCustomFolder: URL? = nil

    // Space Lens State
    @Published public var spaceLensStage: ModuleStage = .intro
    @Published public var spaceLensRoot: SpaceLensNode? = nil
    @Published public var spaceLensStatusText: String = ""
    @Published public var spaceLensProgress: Double = 0
    @Published public var spaceLensSummary: CleanupSummary? = nil
    @Published public var spaceLensTargetURL: URL = FileManager.default.homeDirectoryForCurrentUser

    // Dev & AI Sweeper State
    @Published public var devAISweeperStage: ModuleStage = .intro
    @Published public var devAISweeperResult = DevAISweeperScanResult()
    @Published public var devAISweeperStatusText: String = ""
    @Published public var devAISweeperProgress: Double = 0
    @Published public var devAISweeperSummary: CleanupSummary? = nil

    // Active Port & Local Server Killer State
    @Published public var portKillerSnapshot = PortKillerSnapshot()
    @Published public var isScanningPorts: Bool = false

    // Cloud Cleanup State
    @Published public var cloudAccounts: [CloudAccountStatus] = []
    @Published public var cloudScanningProvider: CloudProviderKind? = nil
    @Published public var cloudScanProgress: Double = 0
    @Published public var cloudStatusText: String = ""
    @Published public var cloudSummary: CleanupSummary? = nil

    // Email Cleanup State
    @Published public var emailStage: ModuleStage = .intro
    @Published public var emailMessages: [EmailMessageItem] = []
    @Published public var emailStatusText: String = ""
    @Published public var emailProgress: Double = 0
    @Published public var emailConnectedAccount: String? = nil
    @Published public var emailSummary: CleanupSummary? = nil

    private var telemetryTimer: Timer?
    private var activeTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var telemetryTickCount = 0
    private var isRefreshingTelemetry = false

    public var isAnyScanRunning: Bool {
        smartCareStage == .scanning || cleanupStage == .scanning || protectionStage == .scanning
            || performanceStage == .scanning || applicationsStage == .scanning || clutterStage == .scanning
            || spaceLensStage == .scanning || devAISweeperStage == .scanning || emailStage == .scanning || cloudScanningProvider != nil
    }

    public init() {
        let loadedSettings = assistantService.loadSettings()
        let loadedStats = assistantService.loadStatistics()
        self.settings = loadedSettings
        self.stats = loadedStats
        self.showIntroFlow = !loadedSettings.hasCompletedIntro
        resetSmartCarePillars()
        startTelemetryTimer()

        // Run initial cloud discovery & telemetry off the Main Thread so launch is instantaneous
        let cloudSvc = cloudEmailService
        Task.detached(priority: .utility) {
            let discovered = cloudSvc.discoverCloudAccounts()
            await MainActor.run {
                self.cloudAccounts = discovered
            }
        }
        refreshTelemetry(includeHeavy: true)

        // Gentle background check for newer GitHub Releases after launch settles
        if loadedSettings.checkUpdatesAutomatically {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self?.checkForUpdates(userInitiated: false)
            }
        }
    }

    // MARK: - Automatic GitHub Releases Updater

    public func checkForUpdates(userInitiated: Bool) {
        updateTask?.cancel()
        if userInitiated {
            NSApp.activate(ignoringOtherApps: true)
            showUpdateSheet = true
            updateState = .checking
        }

        let service = updaterService
        let skipped = settings.skippedUpdateVersion
        updateTask = Task {
            do {
                let outcome = try await service.checkLatestRelease()
                if Task.isCancelled { return }
                await MainActor.run {
                    self.lastUpdateCheckDate = Date()
                    switch outcome {
                    case .updateAvailable(let release):
                        if userInitiated || release.version != skipped {
                            self.availableUpdate = release
                            self.updateState = .updateAvailable(release)
                        } else {
                            self.updateState = .idle
                        }
                    case .upToDate(let latest):
                        self.availableUpdate = nil
                        if userInitiated {
                            self.updateState = .upToDate(latestVersion: latest)
                        }
                    case .noReleasesPublished:
                        self.availableUpdate = nil
                        if userInitiated {
                            self.updateState = .upToDate(latestVersion: AppUpdaterService.currentAppVersion)
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    if userInitiated {
                        self.updateState = .failed(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    public func installAvailableUpdate(_ release: AppReleaseInfo) {
        updateTask?.cancel()
        let service = updaterService
        updateState = .downloading(release: release, progress: 0.01, downloadedBytes: 0, totalBytes: release.preferredAssetSizeBytes)

        updateTask = Task {
            do {
                let outcome = try await service.downloadVerifyAndInstall(
                    release: release,
                    onProgress: { pct, dl, total in
                        Task { @MainActor in
                            self.updateState = .downloading(release: release, progress: pct, downloadedBytes: dl, totalBytes: total)
                        }
                    },
                    onVerifying: {
                        Task { @MainActor in
                            self.updateState = .verifying(release: release)
                        }
                    },
                    onInstalling: {
                        Task { @MainActor in
                            self.updateState = .installing(release: release)
                        }
                    }
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    switch outcome {
                    case .launchedRelaunchScript:
                        // Terminate cleanly so the detached atomic updater script swaps and relaunches R-Cleaner
                        NSApp.terminate(nil)
                    case .revealInFinder(let fileURL, let note):
                        self.updateState = .readyToReveal(release: release, fileURL: fileURL, note: note)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.updateState = .updateAvailable(release)
                }
            } catch {
                await MainActor.run {
                    self.updateState = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    public func skipUpdateVersion(_ version: String) {
        settings.skippedUpdateVersion = AppUpdaterService.normalizeVersion(version)
        availableUpdate = nil
        updateState = .idle
        showBanner("Skipped v\(settings.skippedUpdateVersion)")
    }

    public func cancelUpdateInstall() {
        updateTask?.cancel()
        if let release = availableUpdate {
            updateState = .updateAvailable(release)
        } else {
            updateState = .idle
        }
    }

    // MARK: - Telemetry Loop

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.telemetryTickCount += 1
                self.refreshTelemetry(includeHeavy: self.telemetryTickCount % 3 == 0)
            }
        }
    }

    public func refreshTelemetry(includeHeavy: Bool = true) {
        guard !isRefreshingTelemetry else { return }
        isRefreshingTelemetry = true
        let service = telemetryService
        Task.detached(priority: .utility) {
            let snap = service.captureSnapshot(includeProcessesAndDrives: includeHeavy)
            await MainActor.run {
                var merged = snap
                if !includeHeavy {
                    merged.topCPUConsumers = self.telemetry.topCPUConsumers
                    merged.topMemoryConsumers = self.telemetry.topMemoryConsumers
                    merged.topNetworkConsumers = self.telemetry.topNetworkConsumers
                    merged.externalDrives = self.telemetry.externalDrives
                }
                merged.network.lastSpeedTestMbps = self.telemetry.network.lastSpeedTestMbps
                merged.network.isTestingSpeed = self.telemetry.network.isTestingSpeed
                self.telemetry = merged
                self.isRefreshingTelemetry = false
                self.refreshHealthScore()
                self.evaluateSmartGuardAlerts(snapshot: merged)
            }
        }
    }

    private func evaluateSmartGuardAlerts(snapshot: SystemTelemetrySnapshot) {
        let (active, newlyTriggered) = smartGuard.evaluate(snapshot: snapshot, settings: settings)
        let activeIDs = Set(active.map(\.id))
        // Re-arm dismissed IDs once the condition clears
        dismissedAlertIDs = dismissedAlertIDs.intersection(activeIDs)
        activeSmartAlerts = active.filter { !dismissedAlertIDs.contains($0.id) }

        guard let firstNew = newlyTriggered.first else { return }
        showBanner("\(firstNew.title): \(firstNew.message)")

        if settings.enableVoiceAssistant && !voiceService.isSpeaking && !voiceCommandService.isListening {
            switch firstNew.kind {
            case .lowDisk:
                playVoiceCue(.briefingStorageLow)
            case .criticalRAM, .runawayCPU, .thermalPressure:
                playVoiceCue(.briefingPerfHeavy)
            }
        }
    }

    public func dismissSmartAlert(_ alert: ClearSmartAlert) {
        dismissedAlertIDs.insert(alert.id)
        activeSmartAlerts.removeAll { $0.id == alert.id }
    }

    public func runNetworkSpeedTest() {
        guard !telemetry.network.isTestingSpeed else { return }
        telemetry.network.isTestingSpeed = true
        let service = telemetryService
        Task {
            let mbps = await service.runSpeedTest()
            telemetry.network.lastSpeedTestMbps = mbps
            telemetry.network.isTestingSpeed = false
        }
    }

    public func refreshHealthScore() {
        let eval = assistantService.evaluateHealth(
            telemetry: telemetry,
            stats: stats,
            settings: settings,
            threatsFound: protectionResult.threats.count
        )
        if healthScore != eval.score { healthScore = eval.score }
        if healthRating != eval.rating { healthRating = eval.rating }
        if recommendations != eval.recommendations { recommendations = eval.recommendations }
    }

    // MARK: - Ignore List Helpers

    public func addToIgnoreList(path: String, displayName: String, category: IgnoreListCategory, description: String = "Excluded item") {
        let std = (path as NSString).standardizingPath
        guard !settings.ignoredItems.contains(where: { $0.path == std && $0.category == category }) else { return }
        settings.ignoredItems.append(IgnoredItem(category: category, path: std, displayName: displayName, itemDescription: description))
        showBanner("Added \"\(displayName)\" to Ignore List")
    }

    public func removeIgnoredItem(_ item: IgnoredItem) {
        settings.ignoredItems.removeAll { $0.id == item.id }
    }

    public func showBanner(_ message: String) {
        statusBannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if statusBannerMessage == message {
                statusBannerMessage = nil
            }
        }
    }

    // MARK: - Built-in Clear Voice AI Helpers

    public func speak(_ line: String, interrupt: Bool = true) {
        voiceService.speak(line, settings: settings, interrupt: interrupt)
    }

    public func playVoiceCue(_ cue: VoiceCue, fallbackText: String? = nil, interrupt: Bool = true) {
        voiceService.playCue(cue, settings: settings, fallbackText: fallbackText, interrupt: interrupt)
    }

    public func speakIntroGreeting() {
        let cue = VoiceCue.timeOfDayIntroCue()
        let fallback = VoiceAssistantService.timeOfDayGreeting(address: settings.voiceAddressTitle)
        playVoiceCue(cue, fallbackText: fallback)
    }

    public func speakSystemBriefing() {
        if voiceService.isSpeaking {
            voiceService.stop()
            return
        }
        let cues = VoiceAssistantService.briefingCues(
            telemetry: telemetry,
            healthScore: healthScore,
            threatsCount: protectionResult.threats.count
        )
        let fallbackLine = VoiceAssistantService.systemBriefing(
            telemetry: telemetry,
            healthScore: healthScore,
            address: settings.voiceAddressTitle
        )
        voiceService.playCueSequence(cues, settings: settings, fallbackText: fallbackLine)
    }

    public func testBundledClearVoice() {
        playVoiceCue(.voiceTest)
    }

    public func toggleVoiceAssistant() {
        settings.enableVoiceAssistant.toggle()
        if !settings.enableVoiceAssistant {
            voiceService.stop()
            showBanner("Voice AI muted")
        } else {
            showBanner("Voice AI online")
            playVoiceCue(.voiceTest)
        }
    }

    // MARK: - Two-Way Clear Voice Commands

    public func openClearCommandDeck(startListening: Bool = true) {
        if showIntroFlow {
            completeIntro(startSmartCare: false)
        }
        voiceCommandService.lastResultCard = nil
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            showClearCommandDeck = true
        }
        if startListening {
            startClearListening()
        }
    }

    public func startClearListening() {
        // Silence outgoing Clear speech so the microphone never hears Clear himself
        voiceService.stop()
        voiceCommandService.lastResultCard = nil
        voiceCommandService.startListening { [weak self] transcript in
            self?.executeClearVoiceCommand(transcript)
        }
    }

    public func dismissClearCommandDeck() {
        voiceCommandService.stopListening(triggerCallback: false)
        withAnimation(.easeOut(duration: 0.20)) {
            showClearCommandDeck = false
        }
    }

    public func quickFlushDNS() {
        let service = performanceService
        Task.detached(priority: .userInitiated) {
            let (_, msg) = service.executeSingleTask(.flushDNS)
            await MainActor.run {
                self.stats.totalMaintenanceTasksRun += 1
                self.stats.totalTimeSavedMinutes += 2
                self.showBanner(msg)
                self.playVoiceCue(.briefingNominal)
            }
        }
    }

    public func executeClearVoiceCommand(_ rawText: String) {
        let intent = VoiceCommandParser.parse(rawText)
        voiceCommandService.stopListening(triggerCallback: false)

        switch intent {
        case .runSmartCare:
            dismissClearCommandDeck()
            selectedModule = .smartCare
            startSmartCareScan()

        case .runCleanup:
            dismissClearCommandDeck()
            selectedModule = .cleanup
            startCleanupScan()

        case .runProtection:
            dismissClearCommandDeck()
            selectedModule = .protection
            startProtectionScan()

        case .runDevAISweeper:
            dismissClearCommandDeck()
            selectedModule = .devAISweeper
            startDevAISweeperScan()

        case .scanSpaceLens(let hint):
            dismissClearCommandDeck()
            selectedModule = .spaceLens
            let targetURL: URL
            switch hint {
            case "working-directory":
                let candidate = FileSystemHelpers.expand("~/working-directory")
                targetURL = FileManager.default.fileExists(atPath: candidate)
                    ? URL(fileURLWithPath: candidate)
                    : FileManager.default.homeDirectoryForCurrentUser
            case "Downloads":
                targetURL = URL(fileURLWithPath: FileSystemHelpers.expand("~/Downloads"))
            case "Desktop":
                targetURL = URL(fileURLWithPath: FileSystemHelpers.expand("~/Desktop"))
            case "Documents":
                targetURL = URL(fileURLWithPath: FileSystemHelpers.expand("~/Documents"))
            default:
                targetURL = FileManager.default.homeDirectoryForCurrentUser
            }
            startSpaceLensScan(url: targetURL)
            playVoiceCue(.cleanupStart)

        case .freeUpRAM:
            dismissClearCommandDeck()
            quickFreeUpRAM()

        case .flushDNS:
            dismissClearCommandDeck()
            quickFlushDNS()

        case .emptyTrash:
            dismissClearCommandDeck()
            quickEmptyTrash()
            playVoiceCue(.cleanupComplete)

        case .screenCleaningMode:
            dismissClearCommandDeck()
            launchScreenCleaningMode()

        case .systemBriefing:
            dismissClearCommandDeck()
            speakSystemBriefing()

        case .topCPUConsumers:
            // Keep HUD open and display live top CPU consumers with 1-click Quit
            let svc = telemetryService
            Task.detached(priority: .userInitiated) {
                let snap = svc.captureSnapshot(includeProcessesAndDrives: true)
                await MainActor.run {
                    self.telemetry = snap
                    let top = Array(snap.topCPUConsumers.prefix(3))
                    let summary: String
                    if let first = top.first {
                        summary = "\(first.name) is leading CPU usage at \(String(format: "%.1f%%", first.cpuPercent))."
                    } else {
                        summary = "CPU load is calm across all processes."
                    }
                    self.voiceCommandService.lastResultCard = VoiceCommandResultCard(
                        title: "Top CPU Consumers (\(Int(snap.cpu.totalLoadPercent))% Total)",
                        subtitle: summary,
                        iconName: "cpu.fill",
                        processes: top,
                        metricMode: .cpu
                    )
                    self.playVoiceCue(snap.cpu.totalLoadPercent >= 70 ? .briefingPerfHeavy : .briefingPerfNominal)
                }
            }

        case .topMemoryConsumers:
            let svc = telemetryService
            Task.detached(priority: .userInitiated) {
                let snap = svc.captureSnapshot(includeProcessesAndDrives: true)
                await MainActor.run {
                    self.telemetry = snap
                    let top = Array(snap.topMemoryConsumers.prefix(3))
                    let summary: String
                    if let first = top.first {
                        summary = "\(first.name) is using \(ByteFormat.string(first.memoryBytes)) of memory."
                    } else {
                        summary = "Memory usage is balanced."
                    }
                    self.voiceCommandService.lastResultCard = VoiceCommandResultCard(
                        title: "Top Memory Consumers (\(ByteFormat.string(snap.memory.availableBytes)) Free)",
                        subtitle: summary,
                        iconName: "memorychip.fill",
                        processes: top,
                        metricMode: .memory
                    )
                    self.playVoiceCue(snap.memory.pressurePercent >= 85 ? .briefingPerfHeavy : .briefingPerfNominal)
                }
            }

        case .checkUpdates:
            dismissClearCommandDeck()
            checkForUpdates(userInitiated: true)

        case .openModule(let module):
            dismissClearCommandDeck()
            selectedModule = module
            showBanner("Opened \(module.rawValue)")

        case .stopScan:
            dismissClearCommandDeck()
            stopCurrentTask()
            showBanner("Active scan stopped")

        case .muteVoice:
            dismissClearCommandDeck()
            if settings.enableVoiceAssistant { toggleVoiceAssistant() }

        case .unmuteVoice:
            dismissClearCommandDeck()
            if !settings.enableVoiceAssistant { toggleVoiceAssistant() }

        case .unknown(let raw):
            voiceCommandService.lastResultCard = VoiceCommandResultCard(
                title: "Command Not Recognized",
                subtitle: "I heard “\(raw)”. Try saying “Run Smart Care”, “Dev & AI Sweeper”, “Free up RAM”, “Flush DNS”, or “What's eating my CPU?”.",
                iconName: "questionmark.circle.fill"
            )
        }
    }

    public func completeIntro(startSmartCare: Bool) {
        settings.hasCompletedIntro = true
        withAnimation(.easeInOut(duration: 0.42)) {
            showIntroFlow = false
        }
        if startSmartCare {
            selectedModule = .smartCare
            startSmartCareScan()
        }
    }

    public func replayIntro() {
        withAnimation(.easeInOut(duration: 0.35)) {
            showIntroFlow = true
        }
    }

    // MARK: - Quick Actions (Assistant / Menu Bar)

    public func quickFreeUpRAM() {
        let service = performanceService
        Task.detached(priority: .userInitiated) {
            let (_, msg) = service.executeSingleTask(.freeUpRAM)
            await MainActor.run {
                self.stats.totalMaintenanceTasksRun += 1
                self.stats.totalTimeSavedMinutes += 3
                self.refreshTelemetry(includeHeavy: true)
                self.showBanner(msg)
                self.playVoiceCue(.ramOptimized)
            }
        }
    }

    public func quickEmptyTrash() {
        Task.detached(priority: .userInitiated) {
            let trashDir = FileSystemHelpers.expand("~/.Trash")
            let sizeBefore = FileSystemHelpers.directorySize(at: URL(fileURLWithPath: trashDir))
            if let files = try? FileManager.default.contentsOfDirectory(atPath: trashDir) {
                for f in files {
                    _ = FileSystemHelpers.safeRemoveItem(at: (trashDir as NSString).appendingPathComponent(f), moveToTrash: false)
                }
            }
            await MainActor.run {
                self.stats.totalSystemJunkCleanedBytes += sizeBefore
                self.stats.monthlyCleanedBytes += sizeBefore
                self.stats.totalTimeSavedMinutes += 2
                self.refreshTelemetry(includeHeavy: true)
                self.showBanner("Trash emptied (\(ByteFormat.string(sizeBefore)) freed)")
                FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            }
        }
    }

    public func handleRecommendation(_ rec: AssistantRecommendation) {
        showAssistantPopover = false
        if let special = rec.specialAction {
            switch special {
            case "screenCleaning":
                launchScreenCleaningMode()
                return
            case "emptyTrash":
                quickEmptyTrash()
                return
            case "openFDA":
                FileSystemHelpers.openPrivacySettings(pane: "Privacy_AllFiles")
                return
            case "freeRAM":
                quickFreeUpRAM()
                return
            default:
                break
            }
        }
        if let mod = rec.targetModule {
            selectedModule = mod
        }
    }

    public func launchScreenCleaningMode() {
        isScreenCleaningActive = true
        playVoiceCue(.screenCleanOn)
        ScreenCleaningWindowController.shared.present(
            onComplete: { [weak self] in
                Task { @MainActor in
                    self?.isScreenCleaningActive = false
                    self?.stats.lastScreenCleanDate = Date()
                    self?.playVoiceCue(.screenCleanOff)
                }
            }
        )
    }

    // MARK: - Smart Care Unified Orchestration

    public func resetSmartCarePillars() {
        smartCarePillars = [
            SmartCarePillarState(id: .cleanup, title: "Cleanup", metricText: "Waiting...", subtitle: "Junk & AI Clutter", status: settings.smartCareCleanupEnabled ? .waiting : .disabled, iconName: "trash.circle.fill", targetModule: .cleanup, actionSizeBytes: 0, actionCount: 0, isEnabled: settings.smartCareCleanupEnabled),
            SmartCarePillarState(id: .protection, title: "Protection", metricText: "Waiting...", subtitle: "Malware & Privacy", status: settings.smartCareProtectionEnabled ? .waiting : .disabled, iconName: "shield.lefthalf.filled.badge.checkmark", targetModule: .protection, actionSizeBytes: 0, actionCount: 0, isEnabled: settings.smartCareProtectionEnabled),
            SmartCarePillarState(id: .performance, title: "Performance", metricText: "Waiting...", subtitle: "Maintenance Tasks", status: settings.smartCarePerformanceEnabled ? .waiting : .disabled, iconName: "gauge.with.dots.needle.67percent", targetModule: .performance, actionSizeBytes: 0, actionCount: 0, isEnabled: settings.smartCarePerformanceEnabled),
            SmartCarePillarState(id: .applications, title: "Applications", metricText: "Waiting...", subtitle: "Leftovers & Updates", status: settings.smartCareApplicationsEnabled ? .waiting : .disabled, iconName: "square.grid.2x2.fill", targetModule: .applications, actionSizeBytes: 0, actionCount: 0, isEnabled: settings.smartCareApplicationsEnabled),
            SmartCarePillarState(id: .myClutter, title: "My Clutter", metricText: "Waiting...", subtitle: "Duplicates & Large Files", status: settings.smartCareMyClutterEnabled ? .waiting : .disabled, iconName: "doc.on.doc.fill", targetModule: .myClutter, actionSizeBytes: 0, actionCount: 0, isEnabled: settings.smartCareMyClutterEnabled)
        ]
    }

    public func startSmartCareScan() {
        activeTask?.cancel()
        resetSmartCarePillars()
        smartCareStage = .scanning
        smartCareProgress = 0.05
        smartCareStatusText = "Starting Smart Care checkup..."
        playVoiceCue(.smartCareStart)

        let currentSettings = settings
        let currentTelemetry = telemetry

        activeTask = Task {
            // 1. Cleanup
            if currentSettings.smartCareCleanupEnabled {
                updatePillar(.cleanup, status: .scanning, metric: "Scanning...", subtitle: "Looking for junk...")
                let cats = await cleanupService.scanAll(settings: currentSettings) { msg, pct in
                    Task { @MainActor in
                        self.smartCareStatusText = msg
                        self.smartCareProgress = 0.05 + pct * 0.22
                    }
                }
                if Task.isCancelled { return }
                self.cleanupCategories = cats
                self.cleanupStage = .resultsOverview
                let totalBytes = cats.reduce(0) { $0 + $1.selectedBytes }
                updatePillar(
                    .cleanup,
                    status: totalBytes > 0 ? .found : .clean,
                    metric: totalBytes > 0 ? ByteFormat.string(totalBytes) : "Nothing",
                    subtitle: totalBytes > 0 ? "of junk to clean" : "Your Mac is clean",
                    bytes: totalBytes,
                    count: cats.reduce(0) { $0 + $1.selectedCount }
                )
            }

            // 2. Protection
            if currentSettings.smartCareProtectionEnabled {
                updatePillar(.protection, status: .scanning, metric: "Scanning...", subtitle: "Checking for threats...")
                let prot = await protectionService.scanAll(settings: currentSettings) { msg, pct in
                    Task { @MainActor in
                        self.smartCareStatusText = msg
                        self.smartCareProgress = 0.27 + pct * 0.20
                    }
                }
                if Task.isCancelled { return }
                self.protectionResult = prot
                self.protectionStage = .resultsOverview
                self.stats.totalMalwareItemsScanned += prot.itemsScannedCount
                self.stats.lastMalwareScanDate = Date()
                updatePillar(
                    .protection,
                    status: prot.threats.isEmpty ? .clean : .found,
                    metric: prot.threats.isEmpty ? "No threats" : "\(prot.threats.count) Threats",
                    subtitle: prot.threats.isEmpty ? "Your Mac is safe" : "to remove",
                    bytes: prot.threats.reduce(0) { $0 + $1.sizeBytes },
                    count: prot.threats.count
                )
            }

            // 3. Performance
            if currentSettings.smartCarePerformanceEnabled {
                updatePillar(.performance, status: .scanning, metric: "Checking...", subtitle: "Preparing tasks...")
                let perf = await performanceService.scanAll(telemetry: currentTelemetry) { msg, pct in
                    Task { @MainActor in
                        self.smartCareStatusText = msg
                        self.smartCareProgress = 0.47 + pct * 0.16
                    }
                }
                if Task.isCancelled { return }
                self.performanceResult = perf
                self.performanceStage = .resultsOverview
                let recCount = perf.maintenanceTasks.filter(\.isRecommended).count
                updatePillar(
                    .performance,
                    status: recCount > 0 ? .found : .clean,
                    metric: recCount > 0 ? "\(recCount) Tasks" : "OK",
                    subtitle: recCount > 0 ? "recommended to run" : "Performance is OK",
                    bytes: perf.purgeableBytes,
                    count: recCount
                )
            }

            // 4. Applications
            if currentSettings.smartCareApplicationsEnabled {
                updatePillar(.applications, status: .scanning, metric: "Checking...", subtitle: "Scanning apps & leftovers...")
                let apps = await applicationsService.scanAll(settings: currentSettings, checkUpdatesOnline: false) { msg, pct in
                    Task { @MainActor in
                        self.smartCareStatusText = msg
                        self.smartCareProgress = 0.63 + pct * 0.18
                    }
                }
                if Task.isCancelled { return }
                self.applicationsResult = apps
                self.applicationsStage = .resultsOverview
                let leftoverBytes = apps.leftovers.reduce(0) { $0 + $1.sizeBytes } + apps.installers.reduce(0) { $0 + $1.sizeBytes }
                let count = apps.leftovers.count + apps.installers.count
                updatePillar(
                    .applications,
                    status: count > 0 ? .found : .clean,
                    metric: count > 0 ? ByteFormat.string(leftoverBytes) : "Up to date",
                    subtitle: count > 0 ? "\(count) leftovers & installers" : "Applications in shape",
                    bytes: leftoverBytes,
                    count: count
                )
            }

            // 5. My Clutter
            if currentSettings.smartCareMyClutterEnabled {
                updatePillar(.myClutter, status: .scanning, metric: "Analyzing...", subtitle: "Finding duplicates & large files...")
                let clutter = await clutterService.scanAll(rootURL: URL(fileURLWithPath: FileSystemHelpers.expand("~/Downloads")), settings: currentSettings) { msg, pct in
                    Task { @MainActor in
                        self.smartCareStatusText = msg
                        self.smartCareProgress = 0.81 + pct * 0.19
                    }
                }
                if Task.isCancelled { return }
                self.clutterResult = clutter
                self.clutterStage = .resultsOverview
                let dupBytes = clutter.totalDuplicatesBytes
                let dupCount = clutter.duplicateGroups.flatMap(\.copies).filter(\.isSelected).count
                updatePillar(
                    .myClutter,
                    status: dupCount > 0 ? .found : .clean,
                    metric: dupCount > 0 ? ByteFormat.string(dupBytes) : "Tidy",
                    subtitle: dupCount > 0 ? "\(dupCount) duplicate downloads" : "Nothing to tidy up",
                    bytes: dupBytes,
                    count: dupCount
                )
            }

            self.smartCareProgress = 1.0
            self.smartCareStage = .resultsOverview
            self.stats.lastSmartCareDate = Date()
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            let totalJunk = self.cleanupCategories.reduce(0) { $0 + $1.selectedBytes }
            let threats = self.protectionResult.threats.count
            if threats == 0 && totalJunk == 0 {
                self.playVoiceCue(.smartCareClean)
            } else {
                self.playVoiceCue(.smartCareComplete)
            }
        }
    }

    public func runSmartCareActions() {
        activeTask?.cancel()
        smartCareStage = .cleaning
        smartCareProgress = 0.1

        activeTask = Task {
            var totalFreed: Int64 = 0
            var totalProcessed = 0
            var totalFailed = 0
            var allLogs: [CleanupLogEntry] = []

            if settings.smartCareCleanupEnabled {
                updatePillar(.cleanup, status: .running, metric: "Cleaning...", subtitle: "Removing junk...")
                let res = await cleanupService.cleanSelected(categories: cleanupCategories) { msg, pct in
                    Task { @MainActor in self.smartCareStatusText = msg; self.smartCareProgress = 0.1 + pct * 0.35 }
                }
                totalFreed += res.bytesFreed
                totalProcessed += res.itemsProcessed
                totalFailed += res.itemsFailed
                allLogs.append(contentsOf: res.logEntries)
                stats.totalSystemJunkCleanedBytes += res.bytesFreed
                updatePillar(.cleanup, status: .completed, metric: ByteFormat.string(res.bytesFreed), subtitle: "Cleaned")
            }

            if settings.smartCareProtectionEnabled && !protectionResult.threats.isEmpty {
                updatePillar(.protection, status: .running, metric: "Removing...", subtitle: "Removing threats...")
                let res = await protectionService.removeSelectedThreats(protectionResult.threats)
                totalFreed += res.bytesFreed
                totalProcessed += res.itemsProcessed
                totalFailed += res.itemsFailed
                allLogs.append(contentsOf: res.logEntries)
                stats.totalThreatsRemoved += res.itemsProcessed
                updatePillar(.protection, status: .completed, metric: "\(res.itemsProcessed)", subtitle: "Threats removed")
            }

            if settings.smartCarePerformanceEnabled {
                updatePillar(.performance, status: .running, metric: "Running...", subtitle: "Optimizing Mac...")
                let res = await performanceService.runMaintenanceTasks(performanceResult.maintenanceTasks) { msg, pct in
                    Task { @MainActor in self.smartCareStatusText = msg; self.smartCareProgress = 0.55 + pct * 0.25 }
                }
                totalProcessed += res.itemsProcessed
                totalFailed += res.itemsFailed
                allLogs.append(contentsOf: res.logEntries)
                stats.totalMaintenanceTasksRun += res.itemsProcessed
                updatePillar(.performance, status: .completed, metric: "\(res.itemsProcessed) Done", subtitle: "Tasks complete")
            }

            if settings.smartCareMyClutterEnabled {
                let dupesToRemove = clutterResult.duplicateGroups.flatMap(\.copies).filter(\.isSelected).map { ($0.name, $0.path, $0.sizeBytes) }
                if !dupesToRemove.isEmpty {
                    updatePillar(.myClutter, status: .running, metric: "Decluttering...", subtitle: "Removing duplicates...")
                    let res = await clutterService.removeFiles(paths: dupesToRemove)
                    totalFreed += res.bytesFreed
                    totalProcessed += res.itemsProcessed
                    totalFailed += res.itemsFailed
                    allLogs.append(contentsOf: res.logEntries)
                    stats.totalPersonalFilesCleanedBytes += res.bytesFreed
                    stats.totalDuplicatesRemoved += res.itemsProcessed
                    updatePillar(.myClutter, status: .completed, metric: ByteFormat.string(res.bytesFreed), subtitle: "Removed")
                }
            }

            stats.monthlyCleanedBytes += totalFreed
            stats.totalTimeSavedMinutes += max(5, totalProcessed)
            smartCareSummary = CleanupSummary(
                bytesFreed: totalFreed,
                itemsProcessed: totalProcessed,
                itemsFailed: totalFailed,
                logEntries: allLogs,
                title: "Well done! Your Mac is in great shape!",
                subtitle: "Smart Care actions completed"
            )
            smartCareStage = .complete
            refreshTelemetry(includeHeavy: true)
            FileSystemHelpers.playCompletionSound(enabled: settings.playSounds)
            playVoiceCue(.cleanupComplete)
        }
    }

    private func updatePillar(_ id: SmartCarePillarID, status: SmartCarePillarState.PillarStatus, metric: String, subtitle: String, bytes: Int64? = nil, count: Int? = nil) {
        if let idx = smartCarePillars.firstIndex(where: { $0.id == id }) {
            smartCarePillars[idx].status = status
            smartCarePillars[idx].metricText = metric
            smartCarePillars[idx].subtitle = subtitle
            if let bytes { smartCarePillars[idx].actionSizeBytes = bytes }
            if let count { smartCarePillars[idx].actionCount = count }
        }
    }

    public func stopCurrentTask() {
        activeTask?.cancel()
        activeTask = nil
        if smartCareStage == .scanning || smartCareStage == .cleaning { smartCareStage = .intro }
        if cleanupStage == .scanning || cleanupStage == .cleaning { cleanupStage = .intro }
        if protectionStage == .scanning || protectionStage == .cleaning { protectionStage = .intro }
        if performanceStage == .scanning || performanceStage == .cleaning { performanceStage = .intro }
        if applicationsStage == .scanning || applicationsStage == .cleaning { applicationsStage = .intro }
        if clutterStage == .scanning || clutterStage == .cleaning { clutterStage = .intro }
        if spaceLensStage == .scanning || spaceLensStage == .cleaning { spaceLensStage = .intro }
        if devAISweeperStage == .scanning || devAISweeperStage == .cleaning { devAISweeperStage = .intro }
        if emailStage == .scanning || emailStage == .cleaning { emailStage = .intro }
        cloudScanningProvider = nil
    }

    // MARK: - Individual Module Scan & Clean Triggers

    public func startCleanupScan(focusedCategory: String? = nil) {
        activeTask?.cancel()
        cleanupFocusedCategory = focusedCategory
        cleanupStage = .scanning
        cleanupProgress = 0.05
        playVoiceCue(.cleanupStart)
        let currentSettings = settings

        activeTask = Task {
            let cats = await cleanupService.scanAll(settings: currentSettings, focusedCategory: focusedCategory) { msg, pct in
                Task { @MainActor in
                    self.cleanupStatusText = msg
                    self.cleanupProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.cleanupCategories = cats
            self.cleanupStage = focusedCategory != nil ? .dataManager(categoryID: focusedCategory) : .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    public func runCleanupClean() {
        activeTask?.cancel()
        cleanupStage = .cleaning
        cleanupProgress = 0.05
        let cats = cleanupCategories

        activeTask = Task {
            let summary = await cleanupService.cleanSelected(categories: cats) { msg, pct in
                Task { @MainActor in
                    self.cleanupStatusText = msg
                    self.cleanupProgress = pct
                }
            }
            self.cleanupSummary = summary
            self.stats.totalSystemJunkCleanedBytes += summary.bytesFreed
            self.stats.monthlyCleanedBytes += summary.bytesFreed
            self.stats.totalTimeSavedMinutes += max(3, summary.itemsProcessed)
            self.cleanupStage = .complete
            self.refreshTelemetry(includeHeavy: true)
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            self.playVoiceCue(.cleanupComplete)
        }
    }

    public func startProtectionScan() {
        activeTask?.cancel()
        protectionStage = .scanning
        protectionProgress = 0.05
        playVoiceCue(.protectionStart)
        let currentSettings = settings

        activeTask = Task {
            let res = await protectionService.scanAll(settings: currentSettings) { msg, pct in
                Task { @MainActor in
                    self.protectionStatusText = msg
                    self.protectionProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.protectionResult = res
            self.stats.totalMalwareItemsScanned += res.itemsScannedCount
            self.stats.lastMalwareScanDate = Date()
            self.protectionStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            if res.threats.isEmpty {
                self.playVoiceCue(.protectionClean)
            }
        }
    }

    public func startPerformanceScan() {
        activeTask?.cancel()
        performanceStage = .scanning
        performanceProgress = 0.05
        let snap = telemetry

        activeTask = Task {
            let res = await performanceService.scanAll(telemetry: snap) { msg, pct in
                Task { @MainActor in
                    self.performanceStatusText = msg
                    self.performanceProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.performanceResult = res
            self.performanceStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    public func runSelectedMaintenanceTasks() {
        activeTask?.cancel()
        performanceStage = .cleaning
        performanceProgress = 0.1
        let tasks = performanceResult.maintenanceTasks

        activeTask = Task {
            let summary = await performanceService.runMaintenanceTasks(tasks) { msg, pct in
                Task { @MainActor in
                    self.performanceStatusText = msg
                    self.performanceProgress = pct
                }
            }
            self.performanceSummary = summary
            self.stats.totalMaintenanceTasksRun += summary.itemsProcessed
            self.stats.totalTimeSavedMinutes += max(4, summary.itemsProcessed * 3)
            self.performanceStage = .complete
            self.refreshTelemetry(includeHeavy: true)
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            self.playVoiceCue(.cleanupComplete)
        }
    }

    public func startApplicationsScan(checkUpdatesOnline: Bool = false) {
        activeTask?.cancel()
        applicationsStage = .scanning
        applicationsProgress = 0.05
        let currentSettings = settings

        activeTask = Task {
            let res = await applicationsService.scanAll(settings: currentSettings, checkUpdatesOnline: checkUpdatesOnline) { msg, pct in
                Task { @MainActor in
                    self.applicationsStatusText = msg
                    self.applicationsProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.applicationsResult = res
            self.applicationsStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    public func startClutterScan(customFolder: URL? = nil) {
        activeTask?.cancel()
        clutterCustomFolder = customFolder
        clutterStage = .scanning
        clutterProgress = 0.05
        let currentSettings = settings

        activeTask = Task {
            let res = await clutterService.scanAll(rootURL: customFolder, settings: currentSettings) { msg, pct in
                Task { @MainActor in
                    self.clutterStatusText = msg
                    self.clutterProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.clutterResult = res
            self.clutterStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    public func startSpaceLensScan(url: URL? = nil) {
        activeTask?.cancel()
        let target = url ?? spaceLensTargetURL
        spaceLensTargetURL = target
        spaceLensStage = .scanning
        spaceLensProgress = 0.05

        activeTask = Task {
            let root = await spaceLensService.buildTree(at: target, maxDepth: 4) { msg, pct in
                Task { @MainActor in
                    self.spaceLensStatusText = msg
                    self.spaceLensProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.spaceLensRoot = root
            self.spaceLensStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    public func addDevWorkspaceFolder(_ path: String) {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !FileSystemHelpers.isProtectedSystemPath(std) else {
            showBanner("Please pick a project subfolder rather than a protected root directory.")
            return
        }
        if !settings.devCustomWorkspacePaths.contains(std) {
            settings.devCustomWorkspacePaths.append(std)
            showBanner("Added workspace: \(URL(fileURLWithPath: std).lastPathComponent)")
        }
    }

    public func startDevAISweeperScan() {
        activeTask?.cancel()
        devAISweeperStage = .scanning
        devAISweeperProgress = 0.05
        devAISweeperStatusText = "Discovering developer workspaces..."
        playVoiceCue(.cleanupStart)
        let currentSettings = settings

        activeTask = Task {
            let res = await devAISweeperService.scanAll(settings: currentSettings) { msg, pct in
                Task { @MainActor in
                    self.devAISweeperStatusText = msg
                    self.devAISweeperProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.devAISweeperResult = res
            self.devAISweeperStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            self.playVoiceCue(res.items.isEmpty ? .smartCareClean : .smartCareComplete)
        }
    }

    public func cleanSelectedDevAIItems(moveToTrash: Bool = true) {
        activeTask?.cancel()
        devAISweeperStage = .cleaning
        devAISweeperProgress = 0.05
        let itemsToProcess = devAISweeperResult.items

        activeTask = Task {
            let summary = await devAISweeperService.cleanSelected(items: itemsToProcess, moveToTrash: moveToTrash) { msg, pct in
                Task { @MainActor in
                    self.devAISweeperStatusText = msg
                    self.devAISweeperProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.stats.totalSystemJunkCleanedBytes += summary.bytesFreed
            self.stats.monthlyCleanedBytes += summary.bytesFreed
            self.stats.totalTimeSavedMinutes += max(5, summary.itemsProcessed * 2)
            self.devAISweeperSummary = summary
            self.devAISweeperStage = .complete
            self.refreshTelemetry(includeHeavy: true)
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
            self.playVoiceCue(.cleanupComplete)
        }
    }

    // MARK: - Active Port & Local Server Killer Actions

    public func refreshListeningPorts(silent: Bool = false) {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        let service = portKillerService
        let prevSelectedIDs = Set(portKillerSnapshot.items.filter(\.isSelected).map(\.id))

        Task.detached(priority: .userInitiated) {
            var snap = service.scanListeningPorts()
            for idx in snap.items.indices {
                if prevSelectedIDs.contains(snap.items[idx].id) {
                    snap.items[idx].isSelected = true
                }
            }
            let updatedSnap = snap
            await MainActor.run {
                self.portKillerSnapshot = updatedSnap
                self.isScanningPorts = false
            }
        }
    }

    public func togglePortItemSelection(id: String) {
        if let idx = portKillerSnapshot.items.firstIndex(where: { $0.id == id }),
           !portKillerSnapshot.items[idx].isSystemProtected {
            portKillerSnapshot.items[idx].isSelected.toggle()
        }
    }

    public func selectPortItems(category: PortServiceCategory) {
        for idx in portKillerSnapshot.items.indices where !portKillerSnapshot.items[idx].isSystemProtected {
            portKillerSnapshot.items[idx].isSelected = (portKillerSnapshot.items[idx].category == category)
        }
    }

    public func clearPortSelection() {
        for idx in portKillerSnapshot.items.indices {
            portKillerSnapshot.items[idx].isSelected = false
        }
    }

    public func killListeningPort(_ item: ActivePortItem, force: Bool) {
        let service = portKillerService
        Task.detached(priority: .userInitiated) {
            let res = service.terminatePort(item, force: force)
            await MainActor.run {
                self.showBanner(res.message)
                if res.success {
                    self.stats.totalMaintenanceTasksRun += 1
                    self.stats.totalTimeSavedMinutes += 2
                }
                self.refreshListeningPorts()
            }
        }
    }

    public func killPortByNumber(_ port: Int, force: Bool) {
        let service = portKillerService
        let currentSnap = portKillerSnapshot
        Task.detached(priority: .userInitiated) {
            let res = service.terminatePortNumber(port, in: currentSnap, force: force)
            await MainActor.run {
                self.showBanner(res.message)
                if res.success {
                    self.stats.totalMaintenanceTasksRun += 1
                    self.stats.totalTimeSavedMinutes += 2
                }
                self.refreshListeningPorts()
            }
        }
    }

    public func killSelectedPorts(force: Bool) {
        let targets = portKillerSnapshot.items.filter { $0.isSelected && !$0.isSystemProtected }
        guard !targets.isEmpty else { return }
        let service = portKillerService
        Task.detached(priority: .userInitiated) {
            var killed = 0
            for item in targets {
                if service.terminatePort(item, force: force).success {
                    killed += 1
                }
            }
            let count = killed
            await MainActor.run {
                self.showBanner("\(force ? "Force-killed" : "Stopped") \(count) of \(targets.count) selected port(s)")
                self.stats.totalMaintenanceTasksRun += count
                self.stats.totalTimeSavedMinutes += max(2, count * 2)
                self.refreshListeningPorts()
            }
        }
    }

    public func scanCloudProvider(_ account: CloudAccountStatus) {
        activeTask?.cancel()
        cloudScanningProvider = account.provider
        cloudScanProgress = 0.05
        activeTask = Task {
            let updated = await cloudEmailService.scanCloudAccount(account) { msg, pct in
                Task { @MainActor in
                    self.cloudStatusText = msg
                    self.cloudScanProgress = pct
                }
            }
            if Task.isCancelled { return }
            if let idx = self.cloudAccounts.firstIndex(where: { $0.id == updated.id }) {
                self.cloudAccounts[idx] = updated
            }
            self.cloudScanningProvider = nil
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    public func startEmailScan() {
        activeTask?.cancel()
        emailStage = .scanning
        emailProgress = 0.05

        activeTask = Task {
            let items = await cloudEmailService.scanLocalAppleMail { msg, pct in
                Task { @MainActor in
                    self.emailStatusText = msg
                    self.emailProgress = pct
                }
            }
            if Task.isCancelled { return }
            self.emailMessages = items
            self.emailConnectedAccount = items.isEmpty ? nil : "Apple Mail (Local)"
            self.emailStage = .resultsOverview
            FileSystemHelpers.playCompletionSound(enabled: self.settings.playSounds)
        }
    }

    // MARK: - Launch Quick Tool from My Tools

    public func launchQuickTool(_ tool: QuickToolItem) {
        if tool.focusedFlowID == "screenCleaning" {
            launchScreenCleaningMode()
            return
        }
        selectedModule = tool.targetModule
        switch tool.focusedFlowID {
        case "systemJunk": startCleanupScan(focusedCategory: "systemJunk")
        case "mailAttachments": startCleanupScan(focusedCategory: "mailAttachments")
        case "trashBins": startCleanupScan(focusedCategory: "trashBins")
        case "aiClutter": startCleanupScan(focusedCategory: "aiClutter")
        case "malwareFinder", "privacyItems", "applicationPermissions": startProtectionScan()
        case "maintenanceTasks", "loginItems", "backgroundItems", "timeMachine": startPerformanceScan()
        case "uninstaller", "appUpdater", "appLeftovers": startApplicationsScan(checkUpdatesOnline: tool.focusedFlowID == "appUpdater")
        case "duplicateFinder", "similarImages", "largeAndOld", "downloads": startClutterScan()
        case "spaceLens": startSpaceLensScan()
        case "devAISweeper": startDevAISweeperScan()
        case "portKiller": refreshListeningPorts()
        case "emailCleanup": startEmailScan()
        default: break
        }
    }
}
