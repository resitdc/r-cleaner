import Foundation
import AVFoundation
import Speech

// MARK: - Parsed Jarvis Voice Command Intents

public enum VoiceCommandIntent: Equatable, Sendable {
    case runSmartCare
    case runCleanup
    case runProtection
    case runDevAISweeper
    case scanSpaceLens(folderHint: String?)
    case freeUpRAM
    case flushDNS
    case emptyTrash
    case screenCleaningMode
    case systemBriefing
    case topCPUConsumers
    case topMemoryConsumers
    case checkUpdates
    case openModule(RCleanerModule)
    case stopScan
    case muteVoice
    case unmuteVoice
    case unknown(rawText: String)

    public var displayTitle: String {
        switch self {
        case .runSmartCare: return "Run Smart Care Diagnostics"
        case .runCleanup: return "Scan System Cleanup"
        case .runProtection: return "Run Security & Malware Sweep"
        case .runDevAISweeper: return "Launch Dev & AI Sweeper"
        case .scanSpaceLens(let hint):
            if let hint { return "Scan Space Lens (\(hint))" }
            return "Scan Space Lens"
        case .freeUpRAM: return "Free Up RAM"
        case .flushDNS: return "Flush DNS Cache"
        case .emptyTrash: return "Empty System Trash"
        case .screenCleaningMode: return "Engage Screen Cleaning Mode"
        case .systemBriefing: return "Live System Telemetry Briefing"
        case .topCPUConsumers: return "Inspect Top CPU Consumers"
        case .topMemoryConsumers: return "Inspect Top Memory Consumers"
        case .checkUpdates: return "Check GitHub Releases for Updates"
        case .openModule(let mod): return "Open \(mod.rawValue)"
        case .stopScan: return "Stop Active Scan"
        case .muteVoice: return "Mute Voice AI"
        case .unmuteVoice: return "Enable Voice AI"
        case .unknown: return "Unrecognized Command"
        }
    }
}

public enum VoiceCommandPermissionState: Equatable {
    case unknown
    case authorized
    case deniedMicrophone
    case deniedSpeechRecognition
    case recognizerUnavailable
}

public struct VoiceCommandResultCard: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let processes: [ProcessConsumer]
    public let metricMode: MetricMode

    public enum MetricMode: Equatable {
        case none
        case cpu
        case memory
    }

    public init(
        title: String,
        subtitle: String,
        iconName: String,
        processes: [ProcessConsumer] = [],
        metricMode: MetricMode = .none
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.processes = processes
        self.metricMode = metricMode
    }
}

// MARK: - Natural Language Intent Parser (Pure & Testable)

public enum VoiceCommandParser {
    /// Parses spoken or typed natural-language commands into strongly-typed `VoiceCommandIntent` values.
    public static func parse(_ rawInput: String) -> VoiceCommandIntent {
        var text = rawInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Strip common wake prefixes ("hey jarvis", "jarvis", "okay jarvis", "r-cleaner")
        let prefixes = [
            "hey jarvis,", "hey jarvis", "ok jarvis,", "ok jarvis",
            "okay jarvis,", "okay jarvis", "jarvis,", "jarvis",
            "hey r-cleaner", "r-cleaner", "r cleaner", "please"
        ]
        for p in prefixes {
            if text.hasPrefix(p) {
                text = String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Strip leading punctuation left behind by dictation
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ",.:;!? "))
        guard !text.isEmpty else { return .unknown(rawText: rawInput) }

        // 1. Stop / Cancel
        if text == "stop" || text == "cancel" || text == "abort"
            || text.contains("stop scan") || text.contains("cancel scan") || text.contains("abort scan") {
            return .stopScan
        }

        // 2. Mute / Unmute voice
        if text.contains("unmute") || text.contains("enable voice") || text.contains("turn on voice") {
            return .unmuteVoice
        }
        if text.contains("mute") || text.contains("disable voice") || text.contains("be quiet") || text.contains("shut up") {
            return .muteVoice
        }

        // 3. Screen Cleaning Mode
        if (text.contains("screen") && (text.contains("clean") || text.contains("wipe")))
            || text.contains("lock keyboard") {
            return .screenCleaningMode
        }

        // 4. RAM / Memory optimization vs Top Memory inspection
        if (text.contains("ram") || text.contains("memory"))
            && (text.contains("what") || text.contains("top") || text.contains("eating") || text.contains("using") || text.contains("hog") || text.contains("heavy")) {
            return .topMemoryConsumers
        }
        if (text.contains("free") || text.contains("clear") || text.contains("purge") || text.contains("optimize") || text.contains("boost"))
            && (text.contains("ram") || text.contains("memory")) {
            return .freeUpRAM
        }

        // 5. Top CPU inspection
        if (text.contains("cpu") || text.contains("processor") || text.contains("slow") || text.contains("process") || text.contains("fan"))
            && (text.contains("what") || text.contains("top") || text.contains("eating") || text.contains("using") || text.contains("why") || text.contains("heavy") || text.contains("high")) {
            return .topCPUConsumers
        }

        // 6. DNS flush
        if text.contains("dns") {
            return .flushDNS
        }

        // 7. Empty Trash
        if text.contains("trash") || text.contains("bin") {
            if text.contains("empty") || text.contains("clear") || text.contains("clean") {
                return .emptyTrash
            }
        }

        // 8. Check for updates
        if text.contains("update") && (text.contains("check") || text.contains("app") || text.contains("version") || text.contains("github") || text.contains("latest")) {
            return .checkUpdates
        }

        // 9. Dev & AI Sweeper
        if text.contains("dev") || text.contains("developer") || text.contains("node modules") || text.contains("node_modules")
            || text.contains("docker") || text.contains("xcode") || text.contains("gradle") || text.contains("sweeper")
            || (text.contains("ai") && (text.contains("sweep") || text.contains("model") || text.contains("storage"))) {
            return .runDevAISweeper
        }

        // 10. Space Lens (with optional target folder hint)
        if text.contains("space lens") || text.contains("storage map") || text.contains("bubble map") || text.contains("visualize storage") || text.contains("disk map") {
            if text.contains("working") {
                return .scanSpaceLens(folderHint: "working-directory")
            } else if text.contains("download") {
                return .scanSpaceLens(folderHint: "Downloads")
            } else if text.contains("desktop") {
                return .scanSpaceLens(folderHint: "Desktop")
            } else if text.contains("document") {
                return .scanSpaceLens(folderHint: "Documents")
            } else if text.contains("home") {
                return .scanSpaceLens(folderHint: "Home")
            }
            return .scanSpaceLens(folderHint: nil)
        }

        // 11. Smart Care
        if text.contains("smart care") || text.contains("full scan") || text.contains("check my mac")
            || text.contains("diagnostics") || text.contains("smart scan") || text.contains("checkup") {
            return .runSmartCare
        }

        // 12. Protection / Malware
        if text.contains("malware") || text.contains("virus") || text.contains("security")
            || text.contains("protection") || text.contains("threat") || text.contains("privacy") {
            return .runProtection
        }

        // 13. System Briefing / Status
        if text.contains("briefing") || text.contains("status") || text.contains("health")
            || text.contains("how is my mac") || text.contains("report") || text.contains("telemetry") {
            return .systemBriefing
        }

        // 14. Cleanup / Junk
        if text.contains("cleanup") || text.contains("clean up") || text.contains("junk") || text.contains("cache") {
            return .runCleanup
        }

        // 15. Direct Module Navigation
        if text.contains("application") || text.contains("uninstall") || text.contains("apps") {
            return .openModule(.applications)
        }
        if text.contains("clutter") || text.contains("duplicate") || text.contains("similar photo") || text.contains("large file") {
            return .openModule(.myClutter)
        }
        if text.contains("performance") || text.contains("maintenance") || text.contains("login item") {
            return .openModule(.performance)
        }
        if text.contains("cloud") || text.contains("icloud") || text.contains("google drive") {
            return .openModule(.cloudCleanup)
        }
        if text.contains("email") || text.contains("mail") || text.contains("inbox") {
            return .openModule(.emailCleanup)
        }
        if text.contains("tool") {
            return .openModule(.myTools)
        }
        if text.contains("activity") || text.contains("history") || text.contains("stats") {
            return .openModule(.myActivity)
        }

        return .unknown(rawText: rawInput)
    }
}

// MARK: - Live On-Device Speech Recognition Service

/// Privacy-first, on-device macOS Speech Recognition engine (`SFSpeechRecognizer` + `AVAudioEngine`)
/// with live RMS audio metering and silence auto-execution for Two-Way Jarvis Voice Commands.
@MainActor
public final class VoiceCommandService: ObservableObject {
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var audioLevel: Double = 0.0
    @Published public private(set) var permissionState: VoiceCommandPermissionState = .unknown
    @Published public private(set) var statusNote: String = "Tap the mic or speak a command"
    @Published public var lastResultCard: VoiceCommandResultCard? = nil

    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap: Bool = false
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var onCommandRecognized: ((String) -> Void)?

    public init() {
        refreshPermissionStatus()
    }

    public func refreshPermissionStatus() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .denied || mic == .restricted {
            permissionState = .deniedMicrophone
        } else if speech == .denied || speech == .restricted {
            permissionState = .deniedSpeechRecognition
        } else if mic == .authorized && speech == .authorized {
            permissionState = .authorized
        } else {
            permissionState = .unknown
        }
    }

    public func startListening(onRecognized: @escaping (String) -> Void) {
        stopListening(triggerCallback: false)
        self.onCommandRecognized = onRecognized
        self.liveTranscript = ""
        self.audioLevel = 0
        self.statusNote = "Requesting on-device speech access..."

        Task {
            let granted = await ensurePermissions()
            guard granted else { return }
            beginAudioCaptureAndRecognition()
        }
    }

    public func stopListening(triggerCallback: Bool = false) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        if let engine = audioEngine {
            if hasInstalledTap {
                engine.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            if engine.isRunning {
                engine.stop()
            }
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        let captured = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        isListening = false
        audioLevel = 0

        if triggerCallback, !captured.isEmpty, let cb = onCommandRecognized {
            onCommandRecognized = nil
            statusNote = "Executing: \"\(captured)\""
            cb(captured)
        } else {
            onCommandRecognized = nil
        }
    }

    // MARK: - Permissions

    private func ensurePermissions() async -> Bool {
        // 1. Microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            if !ok {
                permissionState = .deniedMicrophone
                statusNote = "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone, or type a command below."
                return false
            }
        } else if micStatus != .authorized {
            permissionState = .deniedMicrophone
            statusNote = "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone, or type a command below."
            return false
        }

        // 2. Speech Recognition permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            let grantedStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
            }
            if grantedStatus != .authorized {
                permissionState = .deniedSpeechRecognition
                statusNote = "Speech Recognition denied. Enable it in System Settings → Privacy & Security → Speech Recognition, or type a command below."
                return false
            }
        } else if speechStatus != .authorized {
            permissionState = .deniedSpeechRecognition
            statusNote = "Speech Recognition denied. Enable it in System Settings → Privacy & Security → Speech Recognition, or type a command below."
            return false
        }

        permissionState = .authorized
        return true
    }

    // MARK: - Audio Engine + SFSpeechRecognizer Pipeline

    private func beginAudioCaptureAndRecognition() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            permissionState = .recognizerUnavailable
            statusNote = "Speech recognizer temporarily unavailable — type any command below."
            return
        }
        self.speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = [
            "Jarvis", "Smart Care", "Space Lens", "Dev and AI Sweeper",
            "Free up RAM", "Flush DNS", "Empty Trash", "Screen Cleaning Mode",
            "node modules", "Docker", "System Briefing", "Check for updates"
        ]
        self.recognitionRequest = request

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            statusNote = "No active audio input device detected — type any command below."
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)

            // Compute smoothed RMS mic amplitude for real-time arc-reactor HUD animation
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sumSq: Float = 0
            for i in stride(from: 0, to: frames, by: 4) {
                let s = channelData[i]
                sumSq += s * s
            }
            let rms = sqrt(sumSq / Float(max(1, frames / 4)))
            let normalized = min(1.0, max(0.0, Double(rms) * 8.5))
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.audioLevel = self.audioLevel * 0.55 + normalized * 0.45
            }
        }
        hasInstalledTap = true

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
            self.isListening = true
            self.statusNote = recognizer.supportsOnDeviceRecognition
                ? "Listening on-device (100% private)..."
                : "Listening..."
        } catch {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
            statusNote = "Could not start microphone: \(error.localizedDescription)"
            return
        }

        // Max capture window (12 seconds) so microphone never stays open indefinitely
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.stopListening(triggerCallback: !self.liveTranscript.isEmpty)
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }

                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.liveTranscript = transcript

                    if result.isFinal {
                        self.stopListening(triggerCallback: true)
                        return
                    }

                    // Auto-execute 1.3s after user stops speaking
                    self.silenceTimer?.invalidate()
                    if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: false) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, self.isListening else { return }
                                self.stopListening(triggerCallback: true)
                            }
                        }
                    }
                }

                if error != nil, self.isListening {
                    let hasWords = !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    self.stopListening(triggerCallback: hasWords)
                }
            }
        }
    }
}
