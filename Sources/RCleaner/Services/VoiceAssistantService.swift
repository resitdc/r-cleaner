import Foundation
import AVFoundation

public struct VoiceOption: Identifiable, Hashable {
    public let id: String // AVSpeechSynthesisVoice.identifier
    public let name: String
    public let language: String
    public let qualityLabel: String
}

/// Pre-rendered studio British male neural voice cues bundled directly inside R-Cleaner.app
/// so users get a realistic Clear AI voice immediately with zero downloads.
public enum VoiceCue: String, CaseIterable {
    case introMorning = "intro_morning"
    case introAfternoon = "intro_afternoon"
    case introEvening = "intro_evening"
    case smartCareStart = "smart_care_start"
    case smartCareComplete = "smart_care_complete"
    case smartCareClean = "smart_care_clean"
    case cleanupStart = "cleanup_start"
    case cleanupComplete = "cleanup_complete"
    case protectionStart = "protection_start"
    case protectionClean = "protection_clean"
    case ramOptimized = "ram_optimized"
    case screenCleanOn = "screen_clean_on"
    case screenCleanOff = "screen_clean_off"
    case briefingNominal = "briefing_nominal"
    case voiceTest = "voice_test"

    // Modular live system briefing segments (stitched seamlessly in the exact same voice)
    case briefingHealthExcellent = "briefing_health_excellent"
    case briefingHealthGood = "briefing_health_good"
    case briefingHealthFair = "briefing_health_fair"
    case briefingHealthAttention = "briefing_health_attention"
    case briefingStoragePlenty = "briefing_storage_plenty"
    case briefingStorageModerate = "briefing_storage_moderate"
    case briefingStorageLow = "briefing_storage_low"
    case briefingPerfNominal = "briefing_perf_nominal"
    case briefingPerfModerate = "briefing_perf_moderate"
    case briefingPerfHeavy = "briefing_perf_heavy"
    case briefingOutroNominal = "briefing_outro_nominal"
    case briefingOutroThreats = "briefing_outro_threats"

    public var transcript: String {
        switch self {
        case .introMorning:
            return "Good morning sir. R-Cleaner systems are online and ready for diagnostics."
        case .introAfternoon:
            return "Good afternoon sir. R-Cleaner systems are online and ready for diagnostics."
        case .introEvening:
            return "Good evening sir. R-Cleaner systems are online and ready for diagnostics."
        case .smartCareStart:
            return "Initiating full Smart Care diagnostics across all five subsystems."
        case .smartCareComplete:
            return "Diagnostics complete. All scan results are ready for your review sir."
        case .smartCareClean:
            return "All systems are already spotless sir. No further action required."
        case .cleanupStart:
            return "Scanning system caches, logs, and temporary files."
        case .cleanupComplete:
            return "Cleanup complete sir. Reclaimed storage is now available."
        case .protectionStart:
            return "Running security diagnostics and privacy audit."
        case .protectionClean:
            return "Security sweep complete. No active threats detected sir."
        case .ramOptimized:
            return "Memory buffers purged sir. Free RAM has been optimized."
        case .screenCleanOn:
            return "Screen cleaning mode engaged. Keyboard input is temporarily locked. Press Escape to resume."
        case .screenCleanOff:
            return "Screen cleaning mode disengaged. Welcome back sir."
        case .briefingNominal:
            return "All core subsystems are operating within nominal parameters sir."
        case .voiceTest:
            return "At your service sir. Clear voice assistant is online and all R-Cleaner diagnostic systems are ready."
        case .briefingHealthExcellent:
            return "System briefing sir. Overall Mac health is excellent."
        case .briefingHealthGood:
            return "System briefing sir. Overall Mac health is in good condition."
        case .briefingHealthFair:
            return "System briefing sir. Overall Mac health is fair and could use a quick tune-up."
        case .briefingHealthAttention:
            return "System briefing sir. Your Mac requires attention and I recommend running Smart Care."
        case .briefingStoragePlenty:
            return "Storage reserves are plentiful."
        case .briefingStorageModerate:
            return "Storage capacity is moderate."
        case .briefingStorageLow:
            return "Warning. Available disk space is running low."
        case .briefingPerfNominal:
            return "Processor load and memory pressure are both nominal."
        case .briefingPerfModerate:
            return "Processor activity is elevated while memory remains balanced."
        case .briefingPerfHeavy:
            return "System resources are under heavy load. Freeing up memory is advised."
        case .briefingOutroNominal:
            return "All core subsystems are online and operating smoothly."
        case .briefingOutroThreats:
            return "Security sensors flagged potential threats awaiting your review."
        }
    }

    public static func timeOfDayIntroCue(date: Date = Date()) -> VoiceCue {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return .introMorning
        case 12..<18: return .introAfternoon
        default: return .introEvening
        }
    }
}

/// Hybrid Clear Voice AI engine:
/// 1. Plays bundled studio British male neural voice clips (`VoicePack/*.m4a`) routed through a
///    real-time `AVAudioEngine` HUD DSP chain (warm baritone EQ + subtle holographic room ambience +
///    procedural HUD chime) — zero downloads required.
/// 2. Falls back seamlessly to macOS built-in `AVSpeechSynthesizer` for dynamic telemetry readouts
///    (real-time CPU %, RAM GB, free disk space) or custom user address titles.
@MainActor
public final class VoiceAssistantService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    // Real-time HUD audio engine (lazily configured on first playback)
    private var audioEngine: AVAudioEngine?
    private var voicePlayerNode: AVAudioPlayerNode?
    private var chimePlayerNode: AVAudioPlayerNode?
    private var timePitchUnit: AVAudioUnitTimePitch?
    private var eqUnit: AVAudioUnitEQ?
    private var reverbUnit: AVAudioUnitReverb?
    private var fallbackQueueLinks: [URL] = []
    private var fallbackAudioPlayer: AVAudioPlayer?
    private var playbackGeneration: Int = 0

    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var lastSpokenLine: String = ""
    @Published public private(set) var availableVoices: [VoiceOption] = []

    /// Preferred British / refined male macOS TTS voices in priority order (for live dynamic readouts).
    private let preferredVoiceNames = ["Daniel", "Oliver", "Arthur", "Jamie", "Malcolm", "Eddy", "Reed"]

    public override init() {
        super.init()
        synthesizer.delegate = self
        reloadVoices()
    }

    // MARK: - Bundled Voice Pack Resolution

    public static func bundledClipURL(for cue: VoiceCue) -> URL? {
        if let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "m4a", subdirectory: "VoicePack") {
            return url
        }
        if let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "m4a", subdirectory: "Resources/VoicePack") {
            return url
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "m4a", subdirectory: "VoicePack") {
            return url
        }
        if let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "m4a", subdirectory: "Resources/VoicePack") {
            return url
        }
        #endif
        return nil
    }

    public static var bundledClipCount: Int {
        VoiceCue.allCases.filter { bundledClipURL(for: $0) != nil }.count
    }

    // MARK: - macOS Built-in Voice Discovery

    public func reloadVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        let mapped: [VoiceOption] = all.map { v in
            let q: String
            switch v.quality {
            case .premium: q = "Premium"
            case .enhanced: q = "Enhanced"
            default: q = "Standard"
            }
            return VoiceOption(id: v.identifier, name: v.name, language: v.language, qualityLabel: q)
        }

        availableVoices = mapped.sorted { a, b in
            let aPref = preferredRank(a)
            let bPref = preferredRank(b)
            if aPref != bPref { return aPref < bPref }
            if a.language != b.language {
                if a.language == "en-GB" { return true }
                if b.language == "en-GB" { return false }
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func preferredRank(_ opt: VoiceOption) -> Int {
        if let idx = preferredVoiceNames.firstIndex(where: { opt.name.localizedCaseInsensitiveContains($0) }) {
            let qualityBonus = opt.qualityLabel == "Premium" ? 0 : (opt.qualityLabel == "Enhanced" ? 1 : 2)
            let ukBonus = opt.language == "en-GB" ? 0 : 10
            return idx * 20 + ukBonus + qualityBonus
        }
        return 999
    }

    public func resolveVoice(preferredIdentifier: String) -> AVSpeechSynthesisVoice? {
        if !preferredIdentifier.isEmpty, let exact = AVSpeechSynthesisVoice(identifier: preferredIdentifier) {
            return exact
        }
        if let top = availableVoices.first, let voice = AVSpeechSynthesisVoice(identifier: top.id) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Playback API

    /// Plays a bundled studio Clear neural voice clip with HUD audio DSP, falling back to TTS
    /// if the user customized their address title or disabled the bundled voice pack.
    public func playCue(_ cue: VoiceCue, settings: RCleanerSettings, fallbackText: String? = nil, interrupt: Bool = true) {
        playCueSequence([cue], settings: settings, fallbackText: fallbackText, interrupt: interrupt)
    }

    /// Plays a seamless sequence of bundled studio Clear voice clips (e.g., live telemetry briefing)
    /// so the voice stays 100% consistent across the entire app with zero voice switching.
    public func playCueSequence(_ cues: [VoiceCue], settings: RCleanerSettings, fallbackText: String? = nil, interrupt: Bool = true) {
        guard settings.enableVoiceAssistant, !cues.isEmpty else { return }

        if settings.useBundledVoicePack {
            let urls = cues.compactMap { Self.bundledClipURL(for: $0) }
            if urls.count == cues.count {
                let transcript = cues.map(\.transcript).joined(separator: " ")
                playBundledAudioSequence(urls: urls, transcript: transcript, settings: settings, interrupt: interrupt)
                return
            }
        }

        let fallback = fallbackText
            ?? cues.map(\.transcript).joined(separator: " ")
                .replacingOccurrences(of: "sir", with: settings.voiceAddressTitle)
        speak(fallback, settings: settings, interrupt: interrupt)
    }

    /// Selects the exact real-time studio Clear briefing segments matching current Mac telemetry.
    public static func briefingCues(
        telemetry: SystemTelemetrySnapshot,
        healthScore: Int,
        threatsCount: Int
    ) -> [VoiceCue] {
        let healthCue: VoiceCue
        switch healthScore {
        case 85...100: healthCue = .briefingHealthExcellent
        case 70..<85: healthCue = .briefingHealthGood
        case 50..<70: healthCue = .briefingHealthFair
        default: healthCue = .briefingHealthAttention
        }

        let freeGB = Double(telemetry.storage.availableBytes) / 1_000_000_000.0
        let storageCue: VoiceCue
        if freeGB >= 50 {
            storageCue = .briefingStoragePlenty
        } else if freeGB >= 15 {
            storageCue = .briefingStorageModerate
        } else {
            storageCue = .briefingStorageLow
        }

        let cpu = telemetry.cpu.totalLoadPercent
        let pressure = telemetry.memory.pressureLabel.lowercased()
        let perfCue: VoiceCue
        if cpu >= 80 || pressure.contains("high") || pressure.contains("critical") {
            perfCue = .briefingPerfHeavy
        } else if cpu >= 50 || pressure.contains("moderate") || pressure.contains("warn") {
            perfCue = .briefingPerfModerate
        } else {
            perfCue = .briefingPerfNominal
        }

        let outroCue: VoiceCue = threatsCount > 0 ? .briefingOutroThreats : .briefingOutroNominal
        return [healthCue, storageCue, perfCue, outroCue]
    }

    /// Speaks dynamic text (such as live system telemetry numbers) using macOS built-in speech synthesis.
    public func speak(_ text: String, settings: RCleanerSettings, interrupt: Bool = true) {
        guard settings.enableVoiceAssistant else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if interrupt {
            stop()
        }

        if settings.enableVoiceHudEffects {
            playSubtleHUDChime(settings: settings)
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = resolveVoice(preferredIdentifier: settings.voiceIdentifier)
        utterance.rate = Float(max(0.35, min(0.62, settings.voiceRate)))
        utterance.pitchMultiplier = Float(max(0.75, min(1.25, settings.voicePitch)))
        utterance.volume = 0.92
        utterance.preUtteranceDelay = settings.enableVoiceHudEffects ? 0.08 : 0.04
        utterance.postUtteranceDelay = 0.05

        lastSpokenLine = cleaned
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    public func stop() {
        playbackGeneration += 1
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        voicePlayerNode?.stop()
        chimePlayerNode?.stop()
        fallbackAudioPlayer?.stop()
        fallbackAudioPlayer = nil
        fallbackQueueLinks.removeAll()
        isSpeaking = false
    }

    // MARK: - Real-Time AVAudioEngine HUD DSP Pipeline

    private func applyVoiceTuning(settings: RCleanerSettings) {
        let hudEffectsEnabled = settings.enableVoiceHudEffects
        reverbUnit?.wetDryMix = hudEffectsEnabled ? 9.0 : 0.0
        eqUnit?.bypass = !hudEffectsEnabled

        // Default rate = 0.49 -> 1.0x studio speed; Default pitch = 0.92 -> 0 cents studio pitch.
        let clampedRate = max(0.38, min(0.58, settings.voiceRate))
        let clampedPitch = max(0.80, min(1.15, settings.voicePitch))
        let relativeRate = Float(clampedRate / 0.49)
        let relativeCents = Float((clampedPitch - 0.92) * 900.0)
        timePitchUnit?.rate = abs(relativeRate - 1.0) < 0.025 ? 1.0 : relativeRate
        timePitchUnit?.pitch = abs(relativeCents) < 15.0 ? 0.0 : relativeCents
    }

    private func teardownAudioEngine() {
        voicePlayerNode?.stop()
        chimePlayerNode?.stop()
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
        voicePlayerNode = nil
        chimePlayerNode = nil
        timePitchUnit = nil
        eqUnit = nil
        reverbUnit = nil
    }

    private func ensureAudioEngine(settings: RCleanerSettings) -> Bool {
        if let engine = audioEngine {
            applyVoiceTuning(settings: settings)
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    // Audio device or sample-rate changed (e.g. after mic session); rebuild graph cleanly
                    teardownAudioEngine()
                }
            }
            if let runningEngine = audioEngine, runningEngine.isRunning {
                return true
            }
        }

        let engine = AVAudioEngine()
        let vPlayer = AVAudioPlayerNode()
        let cPlayer = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let reverb = AVAudioUnitReverb()

        // Band 0: High-pass filter at 80 Hz for crisp, clean HUD voice clarity
        eq.bands[0].filterType = .highPass
        eq.bands[0].frequency = 80
        eq.bands[0].bypass = false

        // Band 1: Subtle warm British baritone presence at 180 Hz
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 180
        eq.bands[1].bandwidth = 1.1
        eq.bands[1].gain = 2.2
        eq.bands[1].bypass = false

        // Band 2: Crisp holographic vocal articulation at 3.2 kHz
        eq.bands[2].filterType = .parametric
        eq.bands[2].frequency = 3200
        eq.bands[2].bandwidth = 1.0
        eq.bands[2].gain = 1.8
        eq.bands[2].bypass = false
        eq.bypass = !settings.enableVoiceHudEffects

        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = settings.enableVoiceHudEffects ? 9.0 : 0.0

        engine.attach(vPlayer)
        engine.attach(cPlayer)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(reverb)

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(vPlayer, to: timePitch, format: nil)
        engine.connect(timePitch, to: eq, format: nil)
        engine.connect(eq, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        if format.sampleRate > 0 && format.channelCount > 0 {
            engine.connect(cPlayer, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(cPlayer, to: engine.mainMixerNode, format: nil)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.voicePlayerNode = vPlayer
            self.chimePlayerNode = cPlayer
            self.timePitchUnit = timePitch
            self.eqUnit = eq
            self.reverbUnit = reverb
            applyVoiceTuning(settings: settings)
            return true
        } catch {
            return false
        }
    }

    private func playBundledAudioSequence(urls: [URL], transcript: String, settings: RCleanerSettings, interrupt: Bool) {
        if interrupt {
            stop()
        }

        let files = urls.compactMap { try? AVAudioFile(forReading: $0) }
        guard files.count == urls.count, !files.isEmpty else {
            speak(transcript, settings: settings, interrupt: interrupt)
            return
        }

        guard ensureAudioEngine(settings: settings),
              let player = voicePlayerNode else {
            // Direct AVAudioPlayer fallback so it still plays the bundled Clear neural voice clip
            playDirectAudioFallback(urls: urls, transcript: transcript)
            return
        }

        if settings.enableVoiceHudEffects {
            playSubtleHUDChime(settings: settings)
        }

        playbackGeneration += 1
        let gen = playbackGeneration
        lastSpokenLine = transcript
        isSpeaking = true

        player.stop()
        for (idx, file) in files.enumerated() {
            if idx == files.count - 1 {
                player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.playbackGeneration == gen else { return }
                        self.isSpeaking = false
                    }
                }
            } else {
                player.scheduleFile(file, at: nil, completionHandler: nil)
            }
        }
        player.volume = 1.0
        player.play()
    }

    /// Fallback player that plays the exact bundled `.m4a` neural voice files directly if AVAudioEngine is busy.
    private func playDirectAudioFallback(urls: [URL], transcript: String) {
        guard let first = urls.first,
              let directPlayer = try? AVAudioPlayer(contentsOf: first) else {
            isSpeaking = false
            return
        }
        playbackGeneration += 1
        let gen = playbackGeneration
        lastSpokenLine = transcript
        isSpeaking = true
        fallbackAudioPlayer = directPlayer
        directPlayer.volume = 1.0
        directPlayer.play()
        let durationNs = UInt64(max(0.5, directPlayer.duration + 0.12) * 1_000_000_000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: durationNs)
            guard let self, self.playbackGeneration == gen else { return }
            self.isSpeaking = false
        }
    }

    /// Procedurally generates a soft 75ms dual-harmonic cyan HUD chime (880 Hz + 1320 Hz).
    private func playSubtleHUDChime(settings: RCleanerSettings) {
        guard ensureAudioEngine(settings: settings),
              let engine = audioEngine,
              let chimeNode = chimePlayerNode else { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.085)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else { return }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let env = exp(-t * 42.0) * min(1.0, t / 0.005)
            let s1 = sin(2.0 * .pi * 880.0 * t) * 0.55
            let s2 = sin(2.0 * .pi * 1320.0 * t) * 0.30
            let sample = Float((s1 + s2) * env * 0.14)
            for ch in 0..<channels {
                channelData[ch][frame] = sample
            }
        }

        chimeNode.stop()
        chimeNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        chimeNode.play()
    }

    // MARK: - Composed Stark-Style Dialogue Builders

    public static func timeOfDayGreeting(address: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let period: String
        switch hour {
        case 5..<12: period = "Good morning"
        case 12..<18: period = "Good afternoon"
        default: period = "Good evening"
        }
        let suffix = address.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " \(address)"
        return "\(period)\(suffix). R-Cleaner systems are online and ready for diagnostics."
    }

    public static func systemBriefing(telemetry: SystemTelemetrySnapshot, healthScore: Int, address: String) -> String {
        let suffix = address.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " \(address)"
        let freeSpace = ByteFormat.string(telemetry.storage.availableBytes)
        let ramAvail = ByteFormat.string(telemetry.memory.availableBytes)
        let cpuLoad = Int(telemetry.cpu.totalLoadPercent.rounded())
        return "System briefing\(suffix). Overall Mac health is at \(healthScore) percent. Available storage is \(freeSpace). CPU load is \(cpuLoad) percent, with \(ramAvail) of free memory and \(telemetry.memory.pressureLabel.lowercased()) pressure. All core subsystems are nominal."
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
