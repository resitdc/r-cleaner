import SwiftUI
import AppKit

public struct ApplicationsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppsTab = .uninstaller
    @State private var filterText: String = ""
    @State private var filterKind: UninstallerFilter = .all
    @State private var vendorFilter: AppVendorGroup? = nil
    @State private var expandedAppID: String? = nil
    private let palette = RCleanerTheme.palette(for: .applications)

    enum AppsTab: String, CaseIterable {
        case uninstaller = "Uninstaller"
        case updater = "App Updater"
        case leftovers = "Leftovers"
        case installers = "Installers"
    }

    enum UninstallerFilter: String, CaseIterable {
        case all = "All Apps"
        case unused = "Unused (6mo+)"
        case appStore = "App Store"
        case audioPlugins = "Audio Plugins"
        case selected = "Selected"
    }

    public init() {}

    public var body: some View {
        switch appState.applicationsStage {
        case .intro:
            ModuleIntroHero(
                title: "Applications",
                subtitle: "Take control of your applications. Uninstall completely, reset misbehaving apps, update software, or clear leftovers.",
                iconName: "square.grid.2x2.fill",
                palette: palette,
                features: [
                    ("trash.square.fill", "App Uninstaller", "Removes entire applications together with Preferences, Caches, Containers, and Logs — or Reset an app."),
                    ("arrow.down.app.fill", "App Updater", "Checks installed Sparkle feeds and macOS Software Updates."),
                    ("puzzlepiece.extension.fill", "Leftovers & Installers", "Finds orphaned files of removed apps and unused DMG/PKG installers.")
                ],
                primaryActionTitle: "Scan",
                onPrimaryAction: { appState.startApplicationsScan(checkUpdatesOnline: false) }
            )

        case .scanning:
            ScanningProgressView(
                title: "Scanning application files...",
                subtitle: "Looking for applications, related support files, leftovers, and installers.",
                currentPath: appState.applicationsStatusText,
                progress: appState.applicationsProgress,
                iconName: "square.grid.2x2.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            applicationsManagerView

        case .cleaning:
            ScanningProgressView(
                title: "Processing applications...",
                subtitle: "Safely uninstalling or removing selected items.",
                currentPath: appState.applicationsStatusText,
                progress: 0.65,
                iconName: "square.grid.2x2.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.applicationsSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: { appState.applicationsStage = .intro })
            }
        }
    }

    private var applicationsManagerView: some View {
        VStack(spacing: 0) {
            ModuleHeaderBar(title: "Applications", backTitle: "Start Over") {
                appState.applicationsStage = .intro
            }

            HStack(spacing: 8) {
                ForEach(AppsTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selectedTab == tab ? palette.primary.opacity(0.85) : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if selectedTab == .uninstaller {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                        TextField("Search apps...", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 150)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            switch selectedTab {
            case .uninstaller: uninstallerView
            case .updater: updaterView
            case .leftovers: itemListView(items: $appState.applicationsResult.leftovers, emptyTitle: "No app leftovers found", actionTitle: "Remove")
            case .installers: itemListView(items: $appState.applicationsResult.installers, emptyTitle: "No unused DMG/PKG installers found", actionTitle: "Remove")
            }
        }
    }

    private var uninstallerView: some View {
        let filteredIndices = appState.applicationsResult.installedApps.indices.filter { idx in
            let app = appState.applicationsResult.installedApps[idx]
            let matchesSearch = filterText.isEmpty || app.name.localizedCaseInsensitiveContains(filterText) || app.bundleID.localizedCaseInsensitiveContains(filterText)
            let matchesVendor = vendorFilter == nil || app.vendor == vendorFilter
            let matchesFilter: Bool
            switch filterKind {
            case .all: matchesFilter = !app.isAudioPlugin
            case .unused: matchesFilter = app.isUnusedOverSixMonths
            case .appStore: matchesFilter = app.store == .appStore
            case .audioPlugins: matchesFilter = app.isAudioPlugin
            case .selected: matchesFilter = app.isSelected
            }
            return matchesSearch && matchesVendor && matchesFilter
        }
        let selectedApps = appState.applicationsResult.installedApps.filter(\.isSelected)
        let selectedBytes = selectedApps.reduce(0) { $0 + $1.totalSizeBytes }

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(UninstallerFilter.allCases, id: \.self) { f in
                    Button { filterKind = f } label: {
                        Text(f.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(filterKind == f ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(filterKind == f ? Color.white.opacity(0.22) : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("All Vendors") { vendorFilter = nil }
                    Divider()
                    ForEach(AppVendorGroup.allCases) { v in
                        Button(v.rawValue) { vendorFilter = v }
                    }
                } label: {
                    Label(vendorFilter?.rawValue ?? "Vendor: All", systemImage: "building.2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(vendorFilter != nil ? palette.primary.opacity(0.55) : Color.white.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
                Text("\(filteredIndices.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredIndices, id: \.self) { idx in
                        let app = appState.applicationsResult.installedApps[idx]
                        let isExpanded = expandedAppID == app.id
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Toggle("", isOn: $appState.applicationsResult.installedApps[idx].isSelected)
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()

                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(app.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text("v\(app.version)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.55))
                                        Text(app.store.rawValue)
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.white.opacity(0.10)))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    Text("\(app.relatedFiles.count) related files • \(app.vendor.rawValue)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                Spacer()

                                Text(ByteFormat.string(app.totalSizeBytes))
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedAppID = isExpanded ? nil : app.id
                                    }
                                } label: {
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }

                            if isExpanded {
                                Divider().overlay(Color.white.opacity(0.10))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Application Bundle").font(.caption.bold()).foregroundStyle(.white.opacity(0.85))
                                        Spacer()
                                        Text(ByteFormat.string(app.appSizeBytes)).font(.caption).foregroundStyle(.white.opacity(0.7))
                                    }
                                    ForEach(appState.applicationsResult.installedApps[idx].relatedFiles.indices, id: \.self) { rfIdx in
                                        let rf = appState.applicationsResult.installedApps[idx].relatedFiles[rfIdx]
                                        HStack(spacing: 6) {
                                            Toggle("", isOn: $appState.applicationsResult.installedApps[idx].relatedFiles[rfIdx].isSelected)
                                                .toggleStyle(.checkbox)
                                                .labelsHidden()
                                            Text("[\(rf.group)] \(rf.name)")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.76))
                                                .lineLimit(1)
                                            Spacer()
                                            Text(ByteFormat.string(rf.sizeBytes))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                    HStack {
                                        Button("Reveal in Finder") { FileSystemHelpers.revealInFinder(path: app.path) }
                                            .font(.caption)
                                        Spacer()
                                        if !app.relatedFiles.isEmpty {
                                            Button("Reset App Data Only") {
                                                var copy = app
                                                copy.isSelected = true
                                                Task {
                                                    let res = await appState.applicationsService.uninstallApps([copy], resetOnly: true)
                                                    appState.applicationsSummary = res
                                                    appState.applicationsStage = .complete
                                                }
                                            }
                                            .font(.caption.bold())
                                            .foregroundStyle(palette.accent)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                                .padding(.leading, 36)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(.horizontal, 24)
            }

            UbiquitousButton(
                title: "Uninstall",
                subtitle: selectedApps.isEmpty ? nil : ByteFormat.string(selectedBytes),
                palette: palette,
                isDisabled: selectedApps.isEmpty
            ) {
                Task {
                    appState.applicationsStage = .cleaning
                    let res = await appState.applicationsService.uninstallApps(selectedApps, resetOnly: false)
                    appState.stats.totalApplicationsCleanedBytes += res.bytesFreed
                    appState.stats.totalAppsUninstalled += selectedApps.count
                    appState.stats.monthlyCleanedBytes += res.bytesFreed
                    appState.applicationsSummary = res
                    appState.applicationsStage = .complete
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var updaterView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Apps supporting Sparkle appcast feeds and macOS Software Updates.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Check Online Now") {
                    appState.startApplicationsScan(checkUpdatesOnline: true)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(palette.primary.opacity(0.8)))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            if appState.applicationsResult.updates.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Color(hex: "2ED573"))
                Text("Everything is up to date").font(.title2.bold()).foregroundStyle(.white)
                Text("Click 'Check Online Now' to query live Sparkle appcasts and macOS Software Update.")
                    .font(.callout).foregroundStyle(.white.opacity(0.65))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.applicationsResult.updates) { upd in
                            GlassCard(padding: 14, cornerRadius: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(upd.appName).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                        Text("Installed: \(upd.currentVersion) → Latest: \(upd.latestVersion) (\(upd.source))")
                                            .font(.system(size: 12)).foregroundStyle(palette.accent)
                                        Text(upd.releaseNotes).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                                    }
                                    Spacer()
                                    if upd.isMacOSUpdate {
                                        Button("Software Update") {
                                            if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Capsule().fill(Color.white.opacity(0.15)))
                                        .buttonStyle(.plain)
                                    } else if let feed = upd.downloadURL, let url = URL(string: feed) {
                                        Button("Open Feed") { NSWorkspace.shared.open(url) }
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Capsule().fill(Color.white.opacity(0.15)))
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private func itemListView(items: Binding<[ScanItem]>, emptyTitle: String, actionTitle: String) -> some View {
        let selected = items.wrappedValue.filter(\.isSelected)
        let selectedBytes = selected.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 10) {
            if items.wrappedValue.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Color(hex: "2ED573"))
                Text(emptyTitle).font(.title3.bold()).foregroundStyle(.white)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(items.indices, id: \.self) { idx in
                            let item = items.wrappedValue[idx]
                            HStack(spacing: 10) {
                                Toggle("", isOn: items[idx].isSelected).toggleStyle(.checkbox).labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    Text(item.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(ByteFormat.string(item.sizeBytes)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                                Button { FileSystemHelpers.revealInFinder(path: item.path) } label: {
                                    Image(systemName: "magnifyingglass.circle").foregroundStyle(.white.opacity(0.65))
                                }.buttonStyle(.plain)
                            }
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                UbiquitousButton(title: actionTitle, subtitle: ByteFormat.string(selectedBytes), palette: palette, isDisabled: selected.isEmpty) {
                    Task {
                        appState.applicationsStage = .cleaning
                        let res = await appState.clutterService.removeFiles(paths: selected.map { ($0.name, $0.path, $0.sizeBytes) })
                        appState.stats.totalApplicationsCleanedBytes += res.bytesFreed
                        appState.stats.monthlyCleanedBytes += res.bytesFreed
                        appState.applicationsSummary = res
                        appState.applicationsStage = .complete
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}
