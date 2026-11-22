import SwiftUI

public struct ProtectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ProtectionTab = .malware
    @State private var showConfigureSheet = false
    @State private var permissionFilter: String = "All"
    @State private var showBrowserTerminatorAlert = false
    @State private var blockingBrowserNames: [String] = []
    private let palette = RCleanerTheme.palette(for: .protection)

    enum ProtectionTab: String, CaseIterable {
        case malware = "Malware Removal"
        case privacy = "Privacy"
        case permissions = "App Permissions"
    }

    public init() {}

    public var body: some View {
        switch appState.protectionStage {
        case .intro:
            ModuleIntroHero(
                title: "Protection",
                subtitle: "Check your Mac for malware threats, browser privacy traces, and application permissions.",
                iconName: "shield.lefthalf.filled.badge.checkmark",
                palette: palette,
                features: [
                    ("ant.circle.fill", "Malware Removal", "Scans persistence agents, apps, and downloads across 18 threat categories (\(appState.settings.malwareScanMode.rawValue))."),
                    ("hand.raised.fill", "Privacy Check", "Clean browsing history, cookies, autofill, recent items, and review saved Wi-Fi networks."),
                    ("lock.shield.fill", "Application Permissions", "Audit Camera, Microphone, Screen Recording, Full Disk Access, and Automation grants.")
                ],
                primaryActionTitle: "Scan",
                secondaryActionTitle: "Configure Scan (\(appState.settings.malwareScanMode.rawValue))",
                onPrimaryAction: { appState.startProtectionScan() },
                onSecondaryAction: { showConfigureSheet = true }
            )
            .sheet(isPresented: $showConfigureSheet) {
                configureScanSheet
            }

        case .scanning:
            ScanningProgressView(
                title: "Looking for threats...",
                subtitle: "Scanning for malware, privacy traces, and permission grants.",
                currentPath: appState.protectionStatusText,
                progress: appState.protectionProgress,
                iconName: "shield.lefthalf.filled",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            protectionManagerView
                .onAppear {
                    if let focused = appState.protectionFocusedTab {
                        switch focused {
                        case "privacyItems": selectedTab = .privacy
                        case "applicationPermissions": selectedTab = .permissions
                        default: selectedTab = .malware
                        }
                        appState.protectionFocusedTab = nil
                    }
                }

        case .cleaning:
            ScanningProgressView(
                title: "Securing your Mac...",
                subtitle: "Removing selected items.",
                currentPath: appState.protectionStatusText,
                progress: 0.6,
                iconName: "shield.checkmark.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.protectionSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: { appState.protectionStage = .intro })
            }
        }
    }

    private var protectionManagerView: some View {
        VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "Protection",
                backTitle: "Start Over",
                trailingText: "\(appState.protectionResult.itemsScannedCount) items scanned"
            ) {
                appState.protectionStage = .intro
            }

            // Tab Switcher + Real-Time Protection Status Bar
            HStack(spacing: 10) {
                ForEach(ProtectionTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selectedTab == tab ? palette.primary.opacity(0.8) : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Toggle(isOn: $appState.settings.enableRealTimeMalwareMonitor) {
                    Text("Real-Time Monitor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Group {
                switch selectedTab {
                case .malware: malwareTabView
                case .privacy: privacyTabView
                case .permissions: permissionsTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var malwareTabView: some View {
        VStack(spacing: 14) {
            if appState.protectionResult.threats.isEmpty {
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(palette.primary)
                Text("Your Mac is safe from threats")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Scanned \(appState.protectionResult.itemsScannedCount) locations in \(appState.settings.malwareScanMode.rawValue) mode. No malware or suspicious persistence items found.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Spacer()
                UbiquitousButton(title: "Scan", subtitle: "Again", palette: palette) {
                    appState.startProtectionScan()
                }
                .padding(.bottom, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appState.protectionResult.threats.indices, id: \.self) { idx in
                            let threat = appState.protectionResult.threats[idx]
                            GlassCard(padding: 14, cornerRadius: 14, highlightColor: .red) {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: $appState.protectionResult.threats[idx].isSelected)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 22))
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(threat.name).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                            Text(threat.category.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 7).padding(.vertical, 2)
                                                .background(Capsule().fill(Color.red.opacity(0.35)))
                                                .foregroundStyle(.white)
                                        }
                                        Text(threat.reason).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                                        Text(threat.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                                    }
                                    Spacer()
                                    Button { FileSystemHelpers.revealInFinder(path: threat.path) } label: {
                                        Image(systemName: "magnifyingglass.circle").foregroundStyle(.white.opacity(0.7))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                let selectedThreatsCount = appState.protectionResult.threats.filter(\.isSelected).count
                UbiquitousButton(title: "Remove", subtitle: "Threats", palette: palette, isDisabled: selectedThreatsCount == 0) {
                    Task {
                        appState.protectionStage = .cleaning
                        let res = await appState.protectionService.removeSelectedThreats(appState.protectionResult.threats)
                        let cleanedPaths = Set(res.logEntries.filter { $0.status == .cleaned }.map(\.path))
                        appState.protectionResult.threats.removeAll { cleanedPaths.contains($0.path) }
                        appState.stats.totalThreatsRemoved += res.itemsProcessed
                        appState.protectionSummary = res
                        appState.protectionStage = .complete
                        appState.refreshHealthScore()
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var privacyTabView: some View {
        let selectedCount = appState.protectionResult.privacyCategories.reduce(0) { $0 + $1.selectedCount }

        return VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appState.protectionResult.privacyCategories.indices, id: \.self) { cIdx in
                        let cat = appState.protectionResult.privacyCategories[cIdx]
                        GlassCard(padding: 16, cornerRadius: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: cat.iconName).foregroundStyle(palette.accent)
                                    Text(cat.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                    Spacer()
                                    Text(ByteFormat.string(cat.totalBytes)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                                }
                                Text(cat.description).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))

                                ForEach(appState.protectionResult.privacyCategories[cIdx].groups.indices, id: \.self) { gIdx in
                                    ForEach(appState.protectionResult.privacyCategories[cIdx].groups[gIdx].items.indices, id: \.self) { iIdx in
                                        let item = appState.protectionResult.privacyCategories[cIdx].groups[gIdx].items[iIdx]
                                        HStack {
                                            Toggle("", isOn: $appState.protectionResult.privacyCategories[cIdx].groups[gIdx].items[iIdx].isSelected)
                                                .toggleStyle(.checkbox)
                                                .labelsHidden()
                                                .disabled(item.isProtected)
                                            Text(item.name).font(.system(size: 13)).foregroundStyle(.white)
                                            Spacer()
                                            if item.isProtected {
                                                Button("Wi-Fi Settings") {
                                                    FileSystemHelpers.openPrivacySettings(pane: "Privacy")
                                                }
                                                .font(.system(size: 11))
                                                .buttonStyle(.plain)
                                                .foregroundStyle(palette.accent)
                                            } else {
                                                Text(ByteFormat.string(item.sizeBytes))
                                                    .font(.system(size: 11).monospacedDigit())
                                                    .foregroundStyle(.white.opacity(0.65))
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            UbiquitousButton(title: "Remove", subtitle: "\(selectedCount) selected", palette: palette, isDisabled: selectedCount == 0) {
                let running = appState.protectionService.runningBrowsersBlocking(appState.protectionResult.privacyCategories)
                if !running.isEmpty {
                    blockingBrowserNames = running.compactMap(\.localizedName)
                    showBrowserTerminatorAlert = true
                } else {
                    executePrivacyCleanup(quitBrowsers: false)
                }
            }
            .padding(.bottom, 14)
        }
        .alert("Quit running browsers to clean privacy data?", isPresented: $showBrowserTerminatorAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Anyway") { executePrivacyCleanup(quitBrowsers: false) }
            Button("Quit & Clean", role: .destructive) { executePrivacyCleanup(quitBrowsers: true) }
        } message: {
            Text("The following browsers are open and may lock their SQLite databases: \(blockingBrowserNames.joined(separator: ", ")).")
        }
    }

    private func executePrivacyCleanup(quitBrowsers: Bool) {
        Task {
            appState.protectionStage = .cleaning
            let res = await appState.protectionService.removeSelectedPrivacyItems(appState.protectionResult.privacyCategories, quitRunningBrowsers: quitBrowsers)
            let cleanedPaths = Set(res.logEntries.filter { $0.status == .cleaned }.map(\.path))
            for cIdx in appState.protectionResult.privacyCategories.indices {
                for gIdx in appState.protectionResult.privacyCategories[cIdx].groups.indices {
                    for iIdx in appState.protectionResult.privacyCategories[cIdx].groups[gIdx].items.indices {
                        if cleanedPaths.contains(appState.protectionResult.privacyCategories[cIdx].groups[gIdx].items[iIdx].path) {
                            appState.protectionResult.privacyCategories[cIdx].groups[gIdx].items[iIdx].isSelected = false
                        }
                    }
                }
            }
            appState.protectionSummary = res
            appState.protectionStage = .complete
        }
    }

    private var permissionsTabView: some View {
        let kinds = ["All"] + Array(Set(appState.protectionResult.appPermissions.map(\.permissionKind))).sorted()
        let filtered = appState.protectionResult.appPermissions.filter { permissionFilter == "All" || $0.permissionKind == permissionFilter }

        return VStack(spacing: 12) {
            HStack {
                Text("Review apps granted macOS privacy & device permissions. System-managed TCC grants can be revoked directly in System Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Button("Open Privacy & Security") {
                    let pane: String
                    switch permissionFilter {
                    case "Camera": pane = "Privacy_Camera"
                    case "Microphone": pane = "Privacy_Microphone"
                    case "Screen Recording": pane = "Privacy_ScreenCapture"
                    case "Full Disk Access": pane = "Privacy_AllFiles"
                    case "Accessibility": pane = "Privacy_Accessibility"
                    case "Automation": pane = "Privacy_Automation"
                    default: pane = "Privacy"
                    }
                    FileSystemHelpers.openPrivacySettings(pane: pane)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(palette.primary.opacity(0.75)))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(kinds, id: \.self) { kind in
                        Button {
                            permissionFilter = kind
                        } label: {
                            Text(kind)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(permissionFilter == kind ? palette.primary.opacity(0.75) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { perm in
                        HStack(spacing: 12) {
                            Image(systemName: perm.iconName)
                                .font(.system(size: 16))
                                .foregroundStyle(palette.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perm.appName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("\(perm.permissionKind) • \(perm.bundleID)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Text(perm.statusText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var configureScanSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure Malware Scan")
                .font(.title3.bold())
            Picker("Scan Mode", selection: $appState.settings.malwareScanMode) {
                ForEach(MalwareScanMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Depth: \(appState.settings.malwareScanMode.depthLabel)  •  Speed: \(appState.settings.malwareScanMode.speedLabel)")
                    .font(.callout.bold())
                Text(appState.settings.malwareScanMode.purposeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))

            Toggle("Scan archives", isOn: $appState.settings.scanArchives)
            Toggle("Scan DMG disk images", isOn: $appState.settings.scanDMGImages)
            Toggle("Scan email attachments", isOn: $appState.settings.scanEmailAttachments)
            Toggle("Scan USB drives", isOn: $appState.settings.scanUSBDrives)
            Toggle("Exclude downloaded iCloud files", isOn: $appState.settings.excludeDownloadedICloudFiles)

            HStack {
                Spacer()
                Button("Done") { showConfigureSheet = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
