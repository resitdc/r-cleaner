import SwiftUI
import AppKit

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIgnoreCat: IgnoreListCategory = .systemJunk

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                voiceAITab
                    .tabItem { Label("Voice AI", systemImage: "waveform") }
                scanningTab
                    .tabItem { Label("Scanning", systemImage: "magnifyingglass.circle") }
                protectionTab
                    .tabItem { Label("Protection", systemImage: "shield.lefthalf.filled") }
                ignoreListTab
                    .tabItem { Label("Ignore List", systemImage: "hand.raised") }
                menuTab
                    .tabItem { Label("Menu", systemImage: "menubar.rectangle") }
                notificationsTab
                    .tabItem { Label("Notifications", systemImage: "bell.badge") }
            }
            .padding(16)

            Divider()

            HStack {
                Text("R-Cleaner v\(AppUpdaterService.currentAppVersion) • Native macOS Care Suite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    private var generalTab: some View {
        Form {
            Section("Interface & Audio") {
                Toggle("Play sounds for main R-Cleaner actions", isOn: $appState.settings.playSounds)
                Toggle("Reduce Motion (disable animated live background)", isOn: $appState.settings.reduceMotion)
                Toggle("Show Assistant recommendations", isOn: $appState.settings.showAssistantRecommendations)
                Toggle("Enable Smart Insights", isOn: $appState.settings.enableSmartInsights)
                HStack {
                    Text("Onboarding & Intro Animation")
                    Spacer()
                    Button("Replay Intro Tour") {
                        dismiss()
                        appState.replayIntro()
                    }
                }
            }

            Section("Software Updates (GitHub Releases)") {
                Toggle("Automatically check for new releases on launch", isOn: $appState.settings.checkUpdatesAutomatically)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let update = appState.availableUpdate {
                            Text("Update Available: \(update.tagName)")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(hex: "00D2A0"))
                            Text("Installed: v\(AppUpdaterService.currentAppVersion) • Verified via GitHub Releases SHA-256")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Installed Version: v\(AppUpdaterService.currentAppVersion) (build \(AppUpdaterService.currentBuildNumber))")
                                .fontWeight(.semibold)
                            if let checked = appState.lastUpdateCheckDate {
                                Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Checks github.com/\(AppUpdaterService.repoOwner)/\(AppUpdaterService.repoName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if let update = appState.availableUpdate {
                        Button("Install \(update.tagName)") {
                            dismiss()
                            appState.updateState = .updateAvailable(update)
                            appState.showUpdateSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Check Now") {
                            dismiss()
                            appState.checkForUpdates(userInitiated: true)
                        }
                    }
                }
            }

            Section("macOS System Permissions") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Full Disk Access")
                            .fontWeight(.semibold)
                        Text(FileSystemHelpers.hasFullDiskAccess() ? "Enabled for R-Cleaner" : "Disabled — grant to inspect Safari, Mail, and protected caches")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") { FileSystemHelpers.openPrivacySettings(pane: "Privacy_AllFiles") }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Accessibility (Screen Cleaning Mode)")
                            .fontWeight(.semibold)
                        Text(FileSystemHelpers.hasAccessibilityPermission() ? "Enabled — keyboard lock active during Screen Cleaning Mode" : "Disabled — required to lock keyboard while wiping screen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") { FileSystemHelpers.openPrivacySettings(pane: "Privacy_Accessibility") }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var voiceAITab: some View {
        Form {
            Section("Built-in Jarvis Voice Core (Included — No Download Needed)") {
                Toggle("Enable Voice AI Assistant", isOn: $appState.settings.enableVoiceAssistant)
                Toggle("Use Bundled Neural Jarvis Voice Pack (\(VoiceAssistantService.bundledClipCount) studio clips included)", isOn: $appState.settings.useBundledVoicePack)
                Toggle("Enable Futuristic HUD Audio Processing & Chime", isOn: $appState.settings.enableVoiceHudEffects)

                HStack {
                    Button("Test Built-in Jarvis Voice") {
                        appState.testBundledJarvisVoice()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Speak Live Telemetry Briefing") {
                        appState.speakSystemBriefing()
                    }

                    Button("Stop") {
                        appState.voiceService.stop()
                    }
                    .disabled(!appState.voiceService.isSpeaking)
                }
            }

            Section("Two-Way Jarvis Voice Commands (On-Device Speech Recognition)") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hands-Free Command Deck (⌘⇧J)")
                            .fontWeight(.semibold)
                        Text("Runs privately on-device via macOS Speech Recognition. Say “Run Smart Care”, “Dev & AI Sweeper”, “Free up RAM”, or “What's eating my CPU?”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Command Bar") {
                        dismiss()
                        appState.openJarvisCommandDeck(startListening: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Live Telemetry Speech (macOS Built-in TTS)") {
                TextField("Address me as (e.g., sir, boss, your name)", text: $appState.settings.voiceAddressTitle)

                Picker("Dynamic Speech Voice", selection: $appState.settings.voiceIdentifier) {
                    Text("Auto (Best British Male — Daniel en-GB)").tag("")
                    ForEach(appState.voiceService.availableVoices) { v in
                        Text("\(v.name) (\(v.language) • \(v.qualityLabel))").tag(v.id)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Speech Cadence (Rate)")
                        Spacer()
                        Text(String(format: "%.2f", appState.settings.voiceRate)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.settings.voiceRate, in: 0.38...0.58)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Vocal Pitch (Lower = Deeper)")
                        Spacer()
                        Text(String(format: "%.2f", appState.settings.voicePitch)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.settings.voicePitch, in: 0.80...1.15)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var scanningTab: some View {
        Form {
            Section("Modules to scan using Smart Care") {
                Toggle("Cleanup (System Junk, Mail, Trash, AI Clutter)", isOn: $appState.settings.smartCareCleanupEnabled)
                Toggle("Protection (Malware & Privacy)", isOn: $appState.settings.smartCareProtectionEnabled)
                Toggle("Performance (Maintenance Tasks)", isOn: $appState.settings.smartCarePerformanceEnabled)
                Toggle("Applications (Leftovers & Installers)", isOn: $appState.settings.smartCareApplicationsEnabled)
                Toggle("My Clutter (Duplicate Downloads)", isOn: $appState.settings.smartCareMyClutterEnabled)
            }

            Section("Categories to scan using Cleanup") {
                Toggle("System Junk", isOn: $appState.settings.scanSystemJunk)
                Toggle("Mail Attachments", isOn: $appState.settings.scanMailAttachments)
                Toggle("Trash Bins", isOn: $appState.settings.scanTrashBins)
                Toggle("AI Clutter & Local Models", isOn: $appState.settings.scanAIClutter)
            }

            Section("Uninstaller") {
                Toggle("Ignore system applications (/System/Applications)", isOn: $appState.settings.ignoreSystemApplications)
            }
        }
        .formStyle(.grouped)
    }

    private var protectionTab: some View {
        Form {
            Section("Malware Monitoring Configuration") {
                Toggle("Enable Real-Time Malware Monitor", isOn: $appState.settings.enableRealTimeMalwareMonitor)
                Toggle("Look for threats in the background", isOn: $appState.settings.enableBackgroundScan)
            }

            Section("Scan Options") {
                Picker("Scan Mode", selection: $appState.settings.malwareScanMode) {
                    ForEach(MalwareScanMode.allCases) { mode in
                        Text("\(mode.rawValue) (\(mode.depthLabel))").tag(mode)
                    }
                }
                Text(appState.settings.malwareScanMode.purposeDescription)
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Scan archives", isOn: $appState.settings.scanArchives)
                Toggle("Scan DMG disk images", isOn: $appState.settings.scanDMGImages)
                Toggle("Scan email attachments", isOn: $appState.settings.scanEmailAttachments)
                Toggle("Scan USB drives", isOn: $appState.settings.scanUSBDrives)
                Toggle("Exclude downloaded iCloud files", isOn: $appState.settings.excludeDownloadedICloudFiles)
            }
        }
        .formStyle(.grouped)
    }

    private var ignoreListTab: some View {
        let filtered = appState.settings.ignoredItems.filter { $0.category == selectedIgnoreCat }

        return HStack(spacing: 12) {
            List(IgnoreListCategory.allCases, selection: $selectedIgnoreCat) { cat in
                Text(cat.rawValue).tag(cat)
            }
            .frame(width: 190)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(selectedIgnoreCat.rawValue) Ignore List")
                        .font(.headline)
                    Spacer()
                    Button("Add Path...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.addToIgnoreList(path: url.path, displayName: url.lastPathComponent, category: selectedIgnoreCat)
                        }
                    }
                    Button("Reset Category") {
                        appState.settings.ignoredItems.removeAll { $0.category == selectedIgnoreCat }
                    }
                    .disabled(filtered.isEmpty)
                }

                if filtered.isEmpty {
                    ContentUnavailableView("No Ignored Items", systemImage: "hand.raised", description: Text("Right-click any scan item or click 'Add Path...' to exclude items from \(selectedIgnoreCat.rawValue)."))
                } else {
                    List {
                        ForEach(filtered) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName).fontWeight(.medium)
                                    Text(item.path).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    appState.removeIgnoredItem(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var menuTab: some View {
        Form {
            Section("R-Cleaner Menu") {
                Toggle("Enable Menu Bar Monitor", isOn: $appState.settings.enableMenuMonitor)
                Toggle("Open at Login", isOn: $appState.settings.openMenuAtLogin)
                Toggle("Enable recommendations in Menu", isOn: $appState.settings.enableMenuRecommendations)
            }
            Section("External Drives") {
                Toggle("Clean up junk automatically on ejection", isOn: $appState.settings.autoCleanExternalDrivesOnEject)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            Section("Reminders") {
                Toggle("Remind to run regular Smart Care", isOn: $appState.settings.remindSmartCare)
                if appState.settings.remindSmartCare {
                    Picker("Frequency", selection: $appState.settings.smartCareReminderFrequency) {
                        ForEach(ReminderFrequency.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                }
                Toggle("Remind to wipe your Mac screen (Every 2 weeks)", isOn: $appState.settings.remindScreenCleaning)
            }

            Section("Jarvis Smart Alerts & Configurable Thresholds") {
                Toggle("Enable Jarvis Smart Alerts (HUD + Voice AI)", isOn: $appState.settings.enableJarvisSmartAlerts)

                Stepper("Low disk space alert below \(appState.settings.warnLowDiskSpaceGB) GB", value: $appState.settings.warnLowDiskSpaceGB, in: 1...100, step: 1)
                    .disabled(!appState.settings.enableJarvisSmartAlerts)

                Toggle("Alert when RAM pressure exceeds threshold", isOn: $appState.settings.notifyLowRAM)
                    .disabled(!appState.settings.enableJarvisSmartAlerts)
                if appState.settings.notifyLowRAM {
                    Stepper("RAM pressure threshold: \(appState.settings.ramAlertThresholdPercent)%", value: $appState.settings.ramAlertThresholdPercent, in: 60...98, step: 5)
                        .disabled(!appState.settings.enableJarvisSmartAlerts)
                }

                Toggle("Alert when a runaway process pegs CPU", isOn: $appState.settings.notifyRunawayCPU)
                    .disabled(!appState.settings.enableJarvisSmartAlerts)
                if appState.settings.notifyRunawayCPU {
                    Stepper("Runaway CPU threshold: ≥ \(appState.settings.runawayCPUThresholdPercent)%", value: $appState.settings.runawayCPUThresholdPercent, in: 50...300, step: 10)
                        .disabled(!appState.settings.enableJarvisSmartAlerts)
                    Stepper("Sustained duration before alert: \(appState.settings.runawayCPUDurationSeconds) sec", value: $appState.settings.runawayCPUDurationSeconds, in: 15...300, step: 15)
                        .disabled(!appState.settings.enableJarvisSmartAlerts)
                }

                Toggle("Alert on Serious / Critical thermal throttling", isOn: $appState.settings.notifyThermalPressure)
                    .disabled(!appState.settings.enableJarvisSmartAlerts)

                Stepper("Minimum cooldown between repeated alerts: \(appState.settings.smartAlertCooldownMinutes) min", value: $appState.settings.smartAlertCooldownMinutes, in: 1...60, step: 1)
                    .disabled(!appState.settings.enableJarvisSmartAlerts)
            }

            Section("Additional System Notifications") {
                Stepper("Notify if Trash size exceeds \(appState.settings.notifyTrashExceedsGB) GB", value: $appState.settings.notifyTrashExceedsGB, in: 1...50)
                Toggle("Notify when Chrome uses too much memory", isOn: $appState.settings.notifyHeavyChrome)
                Toggle("Notify about hung applications", isOn: $appState.settings.notifyHungApps)
                Toggle("Offer to uninstall trashed applications correctly", isOn: $appState.settings.notifyTrashedApps)
                Toggle("Warn when Bluetooth device batteries are low", isOn: $appState.settings.notifyBluetoothLowBattery)
            }
        }
        .formStyle(.grouped)
    }
}
