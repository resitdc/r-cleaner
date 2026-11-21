import SwiftUI

public struct PerformanceView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: PerfTab = .maintenance
    private let palette = RCleanerTheme.palette(for: .performance)

    enum PerfTab: String, CaseIterable {
        case maintenance = "Maintenance Tasks"
        case loginItems = "Login Items"
        case backgroundItems = "Background Items"
    }

    public init() {}

    public var body: some View {
        switch appState.performanceStage {
        case .intro:
            ModuleIntroHero(
                title: "Performance",
                subtitle: "Run recommended maintenance tasks and manage startup & background processes to keep your Mac fast.",
                iconName: "gauge.with.dots.needle.67percent",
                palette: palette,
                features: [
                    ("wrench.and.screwdriver.fill", "Maintenance Tasks", "Free Up RAM, Flush DNS Cache, Thin Time Machine Snapshots, Reindex Spotlight, Speed Up Mail & more."),
                    ("power.circle.fill", "Login Items", "Control which applications launch automatically when you sign in."),
                    ("cpu.fill", "Background Items", "Inspect and manage Launch Agents and Launch Daemons running in the background.")
                ],
                primaryActionTitle: "Scan",
                onPrimaryAction: { appState.startPerformanceScan() }
            )

        case .scanning:
            ScanningProgressView(
                title: "Examining your system...",
                subtitle: "Preparing tasks for performance optimization.",
                currentPath: appState.performanceStatusText,
                progress: appState.performanceProgress,
                iconName: "gauge.with.dots.needle.67percent",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            performanceManagerView

        case .cleaning:
            ScanningProgressView(
                title: "Running maintenance tasks...",
                subtitle: "Optimizing macOS performance.",
                currentPath: appState.performanceStatusText,
                progress: appState.performanceProgress,
                iconName: "bolt.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.performanceSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: { appState.performanceStage = .intro })
            }
        }
    }

    private var performanceManagerView: some View {
        VStack(spacing: 0) {
            ModuleHeaderBar(title: "Performance", backTitle: "Start Over") {
                appState.performanceStage = .intro
            }

            HStack(spacing: 10) {
                ForEach(PerfTab.allCases, id: \.self) { tab in
                    let count: Int = {
                        switch tab {
                        case .maintenance: return appState.performanceResult.maintenanceTasks.count
                        case .loginItems: return appState.performanceResult.loginItems.count
                        case .backgroundItems: return appState.performanceResult.backgroundItems.count
                        }
                    }()
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.rawValue)
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selectedTab == tab ? palette.primary.opacity(0.8) : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                if selectedTab == .loginItems || selectedTab == .backgroundItems {
                    Button("Open Login Items Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            switch selectedTab {
            case .maintenance: maintenanceList
            case .loginItems: startupItemsList(isLogin: true)
            case .backgroundItems: startupItemsList(isLogin: false)
            }
        }
    }

    private var maintenanceList: some View {
        let selectedCount = appState.performanceResult.maintenanceTasks.filter(\.isSelected).count

        return VStack(spacing: 10) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.performanceResult.maintenanceTasks.indices, id: \.self) { idx in
                        let task = appState.performanceResult.maintenanceTasks[idx]
                        GlassCard(padding: 14, cornerRadius: 14, highlightColor: task.isSelected ? palette.primary : nil) {
                            HStack(spacing: 12) {
                                Toggle("", isOn: $appState.performanceResult.maintenanceTasks[idx].isSelected)
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()

                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(palette.primary.opacity(0.22))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: task.kind.iconName)
                                        .font(.system(size: 17))
                                        .foregroundStyle(palette.accent)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(task.kind.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                        if task.isRecommended {
                                            Text("Recommended")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(palette.primary.opacity(0.8)))
                                        }
                                    }
                                    Text(task.detailSubtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.68))
                                }

                                Spacer()

                                Button("Run Now") {
                                    Task {
                                        let (_, msg) = appState.performanceService.executeSingleTask(task.kind)
                                        appState.stats.totalMaintenanceTasksRun += 1
                                        appState.showBanner("\(task.kind.rawValue): \(msg)")
                                        appState.refreshTelemetry(includeHeavy: true)
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            UbiquitousButton(title: "Run", subtitle: "\(selectedCount) Tasks", palette: palette, isDisabled: selectedCount == 0) {
                appState.runSelectedMaintenanceTasks()
            }
            .padding(.bottom, 14)
        }
    }

    private func startupItemsList(isLogin: Bool) -> some View {
        let binding = isLogin ? $appState.performanceResult.loginItems : $appState.performanceResult.backgroundItems
        let items = isLogin ? appState.performanceResult.loginItems : appState.performanceResult.backgroundItems
        let selectedCount = items.filter(\.isSelected).count

        return VStack(spacing: 10) {
            if items.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color(hex: "2ED573"))
                Text(isLogin ? "No Login Items found" : "No Background Items found")
                    .font(.title3.bold()).foregroundStyle(.white)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(binding.indices, id: \.self) { idx in
                            let item = items[idx]
                            HStack(spacing: 12) {
                                Toggle("", isOn: binding[idx].isSelected)
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()

                                Image(systemName: isLogin ? "app.badge.checkmark" : "gearshape.fill")
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("\(item.domain) • \(item.label)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                Spacer()

                                if !isLogin && item.domain == "User Launch Agent" {
                                    Button(item.isEnabled ? "Disable" : "Enable") {
                                        let (_, msg) = appState.performanceService.toggleBackgroundItem(item, enable: !item.isEnabled)
                                        appState.showBanner(msg)
                                        appState.startPerformanceScan()
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.14)))
                                    .buttonStyle(.plain)
                                } else {
                                    Text(item.isEnabled ? "Enabled" : "Disabled")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(item.isEnabled ? Color(hex: "2ED573") : .white.opacity(0.5))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.white.opacity(0.08)))
                                }

                                Button { FileSystemHelpers.revealInFinder(path: item.path) } label: {
                                    Image(systemName: "magnifyingglass.circle").foregroundStyle(.white.opacity(0.65))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                UbiquitousButton(title: "Remove", subtitle: "\(selectedCount) selected", palette: palette, isDisabled: selectedCount == 0) {
                    Task {
                        appState.performanceStage = .cleaning
                        let res = await appState.performanceService.removeStartupItems(items)
                        appState.performanceSummary = res
                        appState.performanceStage = .complete
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }
}
