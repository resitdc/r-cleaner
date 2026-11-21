import SwiftUI
import AppKit

public struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var isBrandHovered = false

    public init() {}

    public var body: some View {
        ZStack {
            if appState.showIntroFlow {
                IntroFlowView()
                    .environmentObject(appState)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                HStack(spacing: 0) {
                    sidebar
                    Divider().overlay(Color.white.opacity(0.08))
                    detailArea
                }
                .background(
                    LiveBackgroundView(
                        module: appState.selectedModule,
                        isActiveScan: appState.isAnyScanRunning,
                        reduceMotion: appState.settings.reduceMotion
                    )
                )
                .overlay(alignment: .top) {
                    if let message = appState.statusBannerMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: "2ED573"))
                            Text(message)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(radius: 12)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay {
                    if appState.showJarvisCommandDeck {
                        JarvisCommandOverlay(commandService: appState.voiceCommandService)
                            .environmentObject(appState)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.showIntroFlow)
        .frame(minWidth: 1060, minHeight: 680)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showSettingsWindow) {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 780, height: 540)
        }
        .sheet(isPresented: $appState.showUpdateSheet) {
            AppUpdateSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - Translucent Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Brand Header with frameless resitdc.svg Logo (clickable -> https://resitdc.id)
            Button {
                if let url = URL(string: "https://resitdc.id") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    ResitdcLogoMark(height: 24, glow: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("R-Cleaner")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        HStack(spacing: 3) {
                            Text("by resitdc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color(hex: "19F8FF").opacity(isBrandHovered ? 1.0 : 0.8))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(hex: "19F8FF").opacity(isBrandHovered ? 0.95 : 0.0))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isBrandHovered ? Color.white.opacity(0.09) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isBrandHovered = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isBrandHovered {
                    NSCursor.pop()
                    isBrandHovered = false
                }
            }
            .help("Visit https://resitdc.id")
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(RCleanerModule.allCases.filter(\.isPrimarySection)) { module in
                        SidebarRowView(
                            module: module,
                            isSelected: appState.selectedModule == module
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                appState.selectedModule = module
                            }
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.10))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                    ForEach(RCleanerModule.allCases.filter { !$0.isPrimarySection }) { module in
                        SidebarRowView(
                            module: module,
                            isSelected: appState.selectedModule == module
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                appState.selectedModule = module
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // Bottom Disk Pill + Quick Settings + Screen Cleaning
            VStack(spacing: 8) {
                // Compact storage indicator
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(appState.telemetry.storage.volumeName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("\(ByteFormat.string(appState.telemetry.storage.availableBytes)) free")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "36E2F8"), Color(hex: "FF4FD8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * CGFloat(appState.telemetry.storage.usedPercent / 100.0)))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))

                HStack(spacing: 8) {
                    Button {
                        appState.showSettingsWindow = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.launchScreenCleaningMode()
                    } label: {
                        Image(systemName: "display")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 34, height: 28)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Screen Cleaning Mode")
                }
            }
            .padding(12)
        }
        .frame(width: 226)
        .background(RCleanerTheme.sidebarBackground)
    }

    // MARK: - Main Content Area + Top-Right Assistant Pill

    private var detailArea: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch appState.selectedModule {
                case .smartCare: SmartCareView()
                case .cleanup: CleanupView()
                case .protection: ProtectionView()
                case .performance: PerformanceView()
                case .applications: ApplicationsView()
                case .myClutter: MyClutterView()
                case .spaceLens: SpaceLensView()
                case .devAISweeper: DevAISweeperView()
                case .cloudCleanup: CloudCleanupView()
                case .emailCleanup: EmailCleanupView()
                case .myTools: MyToolsView()
                case .myActivity: MyActivityDashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top-Right Frosted Glass Cluster: Update Badge (when available) + Voice AI Pill + Assistant Health Pill
            let activePalette = RCleanerTheme.palette(for: appState.selectedModule)
            HStack(spacing: 8) {
                if let update = appState.availableUpdate {
                    Button {
                        appState.updateState = .updateAvailable(update)
                        appState.showUpdateSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(Color(hex: "00F5D4"))
                            Text("Update \(update.tagName)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(hex: "00D2A0").opacity(0.45), Color(hex: "00BBF9").opacity(0.40)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .overlay(Capsule().strokeBorder(Color(hex: "5EFCE8").opacity(0.65), lineWidth: 1))
                        .shadow(color: Color(hex: "00D2A0").opacity(0.35), radius: 8)
                    }
                    .buttonStyle(.plain)
                    .help("New R-Cleaner release \(update.tagName) is available on GitHub")
                }

                VoiceHUDButton(
                    voiceService: appState.voiceService,
                    commandService: appState.voiceCommandService,
                    isEnabled: appState.settings.enableVoiceAssistant,
                    accentColor: activePalette.accent
                ) {
                    appState.speakSystemBriefing()
                } onVoiceCommand: {
                    appState.openJarvisCommandDeck(startListening: true)
                } onToggleMute: {
                    appState.toggleVoiceAssistant()
                }

                if appState.settings.showAssistantRecommendations {
                    Button {
                        appState.showAssistantPopover.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(healthColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: healthColor.opacity(0.8), radius: 4)
                            Text("Assistant")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(appState.healthScore)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.11)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $appState.showAssistantPopover, arrowEdge: .bottom) {
                        AssistantPopoverView()
                            .environmentObject(appState)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 18)
        }
    }

    private var healthColor: Color {
        switch appState.healthRating {
        case .excellent, .good: return Color(hex: "2ED573")
        case .fair: return Color(hex: "FFD166")
        case .requiresAttention, .critical: return Color(hex: "FF5E57")
        }
    }
}

private struct SidebarRowView: View {
    let module: RCleanerModule
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let palette = RCleanerTheme.palette(for: module)

        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: module.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : palette.accent.opacity(0.9))
                }

                Text(module.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.78))

                Spacer()

                if let badge = module.badgeText {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.primary.opacity(0.85)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.15)
                            : (isHovered ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(colors: [Color.white.opacity(0.28), palette.accent.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Frosted-glass Voice AI pill in the top-right bar, harmonized with the active module's palette.
/// Includes one-click live System Briefing, two-way Jarvis Voice Command mic trigger (⌘⇧J), and mute toggle.
private struct VoiceHUDButton: View {
    @ObservedObject var voiceService: VoiceAssistantService
    @ObservedObject var commandService: VoiceCommandService
    let isEnabled: Bool
    let accentColor: Color
    let onBriefing: () -> Void
    let onVoiceCommand: () -> Void
    let onToggleMute: () -> Void

    var body: some View {
        let isActive = voiceService.isSpeaking || commandService.isListening
        let borderColor: Color = isActive ? accentColor.opacity(0.80) : Color.white.opacity(0.20)
        let glowColor: Color = isActive ? accentColor.opacity(0.38) : .clear

        HStack(spacing: 2) {
            Button(action: onBriefing) {
                HStack(spacing: 7) {
                    if voiceService.isSpeaking {
                        equalizerBars
                    } else {
                        Image(systemName: isEnabled ? "waveform" : "speaker.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isEnabled ? accentColor : Color.white.opacity(0.5))
                    }

                    Text(statusTitle)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.55))
                }
                .padding(.leading, 11)
                .padding(.trailing, 6)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .help(voiceService.isSpeaking ? "Click to stop speaking" : "Click for live spoken System Briefing")

            Divider()
                .frame(height: 12)
                .overlay(Color.white.opacity(0.18))

            Button(action: onVoiceCommand) {
                Image(systemName: commandService.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(commandService.isListening ? Color(hex: "00F5D4") : accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .help("Jarvis Voice Command (⌘⇧J) — Speak or type commands")

            Divider()
                .frame(height: 12)
                .overlay(Color.white.opacity(0.18))

            Button(action: onToggleMute) {
                Image(systemName: isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isEnabled ? Color.white.opacity(0.85) : Color.white.opacity(0.45))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .help(isEnabled ? "Mute Voice AI" : "Enable Voice AI")
        }
        .background(Capsule().fill(Color.white.opacity(0.11)))
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
        .shadow(color: glowColor, radius: 10)
    }

    private var statusTitle: String {
        if commandService.isListening { return "Listening" }
        if voiceService.isSpeaking { return "Speaking" }
        return isEnabled ? "Voice AI" : "Muted"
    }

    private var equalizerBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let h = 4.0 + abs(sin(t * 7.5 + Double(i) * 1.1)) * 10.0
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 2.5, height: CGFloat(h))
                }
            }
            .frame(height: 14)
        }
    }
}
