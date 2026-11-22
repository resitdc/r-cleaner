import SwiftUI
import AppKit

/// Futuristic floating Clear Two-Way Voice Command HUD (triggered by ⌘⇧J or the top-right Mic button).
/// Supports live on-device voice transcription, live arc-reactor audio reactivity, typed quick commands,
/// suggested command chips, and interactive live telemetry response cards (e.g. Top CPU / RAM consumers).
public struct ClearCommandOverlay: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var commandService: VoiceCommandService
    @State private var typedCommand: String = ""
    @FocusState private var inputFocused: Bool

    private let suggestedCommands: [(label: String, icon: String, phrase: String)] = [
        ("Run Smart Care", "sparkles", "Run Smart Care"),
        ("Dev & AI Sweeper", "terminal.fill", "Launch Dev & AI Sweeper"),
        ("What's eating my CPU?", "cpu.fill", "What's eating my CPU"),
        ("What's using my RAM?", "memorychip.fill", "What's using my RAM"),
        ("Free Up RAM", "bolt.fill", "Free up RAM"),
        ("Flush DNS", "network", "Flush DNS"),
        ("Scan Space Lens", "circle.hexagongrid.fill", "Scan Space Lens"),
        ("System Briefing", "waveform", "System briefing"),
        ("Screen Cleaning", "display", "Screen cleaning mode"),
        ("Check Updates", "arrow.down.circle.fill", "Check for updates")
    ]

    public init(commandService: VoiceCommandService) {
        self.commandService = commandService
    }

    public var body: some View {
        ZStack {
            // Subtle dim scrim — click outside to dismiss
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.dismissClearCommandDeck()
                }

            VStack(spacing: 18) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: "36E2F8"))
                        Text("CLEAR VOICE COMMAND")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(Color(hex: "36E2F8"))
                    }

                    Spacer()

                    Text("⌘⇧J")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))

                    Button {
                        appState.dismissClearCommandDeck()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                // Live Arc-Reactor Reactive Microphone Orb
                Button {
                    if commandService.isListening {
                        commandService.stopListening(triggerCallback: !commandService.liveTranscript.isEmpty)
                    } else {
                        appState.startClearListening()
                    }
                } label: {
                    ZStack {
                        // Outer voice-reactive holographic halo
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(hex: "36E2F8").opacity(commandService.isListening ? 0.42 : 0.16),
                                        Color(hex: "7B61FF").opacity(commandService.isListening ? 0.24 : 0.08),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 18,
                                    endRadius: 68
                                )
                            )
                            .frame(width: 132, height: 132)
                            .scaleEffect(commandService.isListening ? (1.0 + CGFloat(commandService.audioLevel) * 0.32) : 1.0)
                            .animation(.easeOut(duration: 0.08), value: commandService.audioLevel)

                        // Outer ring
                        Circle()
                            .strokeBorder(
                                AngularGradient(
                                    colors: [Color(hex: "36E2F8"), Color(hex: "00F5D4"), Color(hex: "7B61FF"), Color(hex: "36E2F8")],
                                    center: .center
                                ),
                                lineWidth: commandService.isListening ? 3 : 1.5
                            )
                            .frame(width: 82, height: 82)
                            .shadow(color: Color(hex: "36E2F8").opacity(commandService.isListening ? 0.75 : 0.3), radius: 14)

                        // Core button
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: commandService.isListening
                                        ? [Color(hex: "00D2A0"), Color(hex: "00BBF9")]
                                        : [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)

                        Image(systemName: commandService.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help(commandService.isListening ? "Click to finish speaking" : "Click to start listening")

                // Live Transcript or Status
                VStack(spacing: 5) {
                    if !commandService.liveTranscript.isEmpty {
                        Text("“\(commandService.liveTranscript)”")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    } else {
                        Text(commandService.isListening ? "Listening — speak a command..." : "At your service, \(appState.settings.voiceAddressTitle).")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text(commandService.statusNote)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }

                // Permission Fix Shortcut (only shown if macOS mic/speech denied)
                if commandService.permissionState == .deniedMicrophone || commandService.permissionState == .deniedSpeechRecognition {
                    HStack(spacing: 10) {
                        Button("Open Privacy Settings") {
                            let pane = commandService.permissionState == .deniedMicrophone
                                ? "Privacy_Microphone"
                                : "Privacy_SpeechRecognition"
                            FileSystemHelpers.openPrivacySettings(pane: pane)
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: "FF6B4A").opacity(0.85)))
                        .buttonStyle(.plain)
                    }
                }

                // Live Interactive Telemetry Answer Card (e.g. Top CPU / Top RAM query)
                if let card = commandService.lastResultCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: card.iconName)
                                .foregroundStyle(Color(hex: "36E2F8"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(card.subtitle)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            Spacer()
                        }

                        if !card.processes.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(card.processes.prefix(3)) { proc in
                                    HStack(spacing: 10) {
                                        Text(proc.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(card.metricMode == .cpu
                                             ? String(format: "%.1f%% CPU", proc.cpuPercent)
                                             : ByteFormat.string(proc.memoryBytes))
                                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(hex: "5EFCE8"))
                                        if proc.id > 1 && proc.id != getpid() && proc.name != "kernel_task" && proc.name != "launchd" {
                                            Button("Quit") {
                                                let ok = appState.telemetryService.terminateProcess(pid: proc.id)
                                                appState.showBanner(ok ? "Quit \(proc.name)" : "Could not terminate \(proc.name)")
                                                appState.refreshTelemetry(includeHeavy: true)
                                            }
                                            .font(.system(size: 10.5, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.75)))
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "36E2F8").opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: "36E2F8").opacity(0.32), lineWidth: 1))
                }

                // Typed Command Fallback Input (works silently anywhere!)
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "36E2F8"))
                    TextField("Or type a command (e.g. \"Free up RAM\", \"What's eating my CPU?\")...", text: $typedCommand)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($inputFocused)
                        .onSubmit {
                            let cmd = typedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cmd.isEmpty else { return }
                            typedCommand = ""
                            appState.executeClearVoiceCommand(cmd)
                        }
                    Button("Run") {
                        let cmd = typedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cmd.isEmpty else { return }
                        typedCommand = ""
                        appState.executeClearVoiceCommand(cmd)
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: "00BBF9").opacity(0.78)))
                    .buttonStyle(.plain)
                    .disabled(typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.09)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))

                // Quick Voice Command Chips
                VStack(alignment: .leading, spacing: 6) {
                    Text("TRY SAYING")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.45))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(suggestedCommands, id: \.label) { chip in
                                Button {
                                    appState.executeClearVoiceCommand(chip.phrase)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: chip.icon)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Color(hex: "5EFCE8"))
                                        Text(chip.label)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .lineLimit(1)
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.white.opacity(0.09)))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 580)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "0B1626").opacity(0.96), Color(hex: "111D35").opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(hex: "36E2F8").opacity(0.65), Color(hex: "7B61FF").opacity(0.35), Color.white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.3
                    )
            )
            .shadow(color: Color(hex: "00BBF9").opacity(0.28), radius: 36, y: 12)
        }
    }
}
