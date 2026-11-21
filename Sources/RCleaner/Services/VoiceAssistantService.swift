import Foundation
import AVFoundation

public struct VoiceOption: Identifiable, Hashable {
    public let id: String // AVSpeechSynthesisVoice.identifier
    public let name: String
    public let language: String
    public let qualityLabel: String
}

/// Built-in macOS AVSpeechSynthesizer voice engine tuned for a calm, composed,
/// British AI-assistant cadence (prioritizing Daniel en-GB / Enhanced / Premium voices).
@MainActor
public final class VoiceAssistantService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var lastSpokenLine: String = ""
    @Published public private(set) var availableVoices: [VoiceOption] = []

    /// Preferred British / refined male voices in priority order.
    private let preferredVoiceNames = ["Daniel", "Oliver", "Arthur", "Jamie", "Malcolm", "Eddy", "Reed"]

    public override init() {
        super.init()
        synthesizer.delegate = self
        reloadVoices()
    }

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

        // Sort: preferred British male voices first, then Premium/Enhanced, then en-GB, then alphabetical
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

    public func speak(_ text: String, settings: RCleanerSettings, interrupt: Bool = true) {
        guard settings.enableVoiceAssistant else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if interrupt && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = resolveVoice(preferredIdentifier: settings.voiceIdentifier)
        utterance.rate = Float(max(0.35, min(0.62, settings.voiceRate)))
        utterance.pitchMultiplier = Float(max(0.75, min(1.25, settings.voicePitch)))
        utterance.volume = 0.92
        utterance.preUtteranceDelay = 0.04
        utterance.postUtteranceDelay = 0.05

        lastSpokenLine = cleaned
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
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
        let suffix = address.trimmingCharacters(in: .whitespaces).isEmpty ? "" : ", \(address)"
        return "\(period)\(suffix). R-Cleaner systems are online and ready for diagnostics."
    }

    public static func systemBriefing(telemetry: SystemTelemetrySnapshot, healthScore: Int, address: String) -> String {
        let suffix = address.trimmingCharacters(in: .whitespaces).isEmpty ? "" : ", \(address)"
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
