import SwiftUI
import AppKit

public struct DevAISweeperView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: DevAISweeperCategory? = nil
    @State private var minAgeFilter: Int = 0 // 0 = All, 14, 30, 60, 90
    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .largest
    @State private var moveToTrash: Bool = true
    @State private var showReviewSheet: Bool = false
    @State private var showConfirmDeleteAlert: Bool = false
    private let palette = RCleanerTheme.palette(for: .devAISweeper)

    private enum SortMode: String, CaseIterable, Identifiable {
        case largest = "Largest First"
        case oldest = "Oldest First"
        case name = "Name"
        var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        switch appState.devAISweeperStage {
        case .intro:
            let detectedRoots = appState.devAISweeperService.discoverWorkspaceRoots(
                customPaths: appState.settings.devCustomWorkspacePaths
            )
            let rootSummary = detectedRoots.isEmpty
                ? "Add Workspace Folder"
                : "Workspaces (\(detectedRoots.map { URL(fileURLWithPath: $0).lastPathComponent }.prefix(2).joined(separator: ", "))\(detectedRoots.count > 2 ? " +\(detectedRoots.count - 2)" : ""))"

            ModuleIntroHero(
                title: "Dev & AI Sweeper",
                subtitle: "Reclaim tens of gigabytes from stale build artifacts, Xcode & Android caches, package stores, Docker, and local AI models without touching your source code.",
                iconName: "terminal.fill",
                palette: palette,
                features: [
                    ("folder.badge.gearshape", "Stale Build Artifacts", "Finds old node_modules, Rust target/, Swift .build/, Gradle build/, Pods, and Python .venv while auto-protecting active projects."),
                    ("hammer.fill", "Xcode, Android & Packages", "Clears DerivedData, iOS DeviceSupport, Gradle, npm, Cargo, Go, Homebrew, and Docker build caches."),
                    ("brain.head.profile", "Local AI & Agent Storage", "Safely sweeps Cursor/Claude/VS Code caches and lets you review Ollama, LM Studio, and HuggingFace weights.")
                ],
                primaryActionTitle: "Scan",
                secondaryActionTitle: rootSummary,
                onPrimaryAction: {
                    appState.startDevAISweeperScan()
                },
                onSecondaryAction: {
                    pickWorkspaceFolder(autoScan: true)
                }
            )

        case .scanning:
            ScanningProgressView(
                title: "Sweeping developer & AI storage...",
                subtitle: "Scanning project workspaces, Xcode/Android SDKs, package caches, Docker, and AI weights.",
                currentPath: appState.devAISweeperStatusText,
                progress: appState.devAISweeperProgress,
                iconName: "terminal.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            resultsWorkspace

        case .cleaning:
            ScanningProgressView(
                title: "Sweeping selected artifacts...",
                subtitle: moveToTrash ? "Moving selected build caches & artifacts safely to Trash." : "Reclaiming disk space immediately from selected items.",
                currentPath: appState.devAISweeperStatusText,
                progress: appState.devAISweeperProgress,
                iconName: "sparkles",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.devAISweeperSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: {
                    appState.devAISweeperStage = .intro
                })
            }
        }
    }

    // MARK: - Results Workspace

    private var filteredItems: [DevAIArtifactItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = appState.devAISweeperResult.items.filter { item in
            if let cat = selectedCategory, item.category != cat { return false }
            if minAgeFilter > 0 {
                guard let age = item.ageDays, age >= minAgeFilter else { return false }
            }
            if !query.isEmpty {
                let hay = "\(item.name) \(item.projectName) \(item.ecosystem) \(item.path) \(item.rebuildHint)".lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }

        switch sortMode {
        case .largest:
            return list.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest:
            return list.sorted { ($0.ageDays ?? -1) > ($1.ageDays ?? -1) }
        case .name:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var resultsWorkspace: some View {
        let result = appState.devAISweeperResult
        let visible = filteredItems
        let selectedBytes = result.selectedBytes
        let selectedCount = result.selectedCount

        return VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "Dev & AI Sweeper",
                backTitle: "Start Over",
                trailingText: "\(ByteFormat.string(result.totalBytes)) found • \(result.items.count) items"
            ) {
                appState.devAISweeperStage = .intro
            }

            // Category Filter Strip (horizontal scroll, never wraps vertically)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryPill(
                        title: "All",
                        icon: "square.grid.2x2.fill",
                        bytes: result.totalBytes,
                        count: result.items.count,
                        isSelected: selectedCategory == nil,
                        tint: palette.primary
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(DevAISweeperCategory.allCases) { cat in
                        let catCount = result.count(for: cat)
                        let catBytes = result.bytes(for: cat)
                        if catCount > 0 || cat == .dockerContainers {
                            categoryPill(
                                title: cat.rawValue,
                                icon: cat.iconName,
                                bytes: catBytes,
                                count: catCount,
                                isSelected: selectedCategory == cat,
                                tint: Color(hex: cat.accentHex)
                            ) {
                                selectedCategory = cat
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)

            // Secondary Toolbar: Stale Age Filter, Search, Sort, Workspace Adder & Quick Presets
            HStack(spacing: 10) {
                // Age / Stale pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([(0, "All Ages"), (14, "14d+"), (30, "30d+"), (60, "60d+"), (90, "90d+")], id: \.0) { days, label in
                            Button(label) {
                                minAgeFilter = days
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(minAgeFilter == days ? palette.primary.opacity(0.82) : Color.white.opacity(0.09)))
                            .buttonStyle(.plain)
                        }

                        Divider().frame(height: 16).overlay(Color.white.opacity(0.18))

                        Button("Select Stale (30d+)") {
                            applySelectionPreset(.stale30)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(palette.primary.opacity(0.16)))
                        .buttonStyle(.plain)

                        Button("Safe Caches") {
                            applySelectionPreset(.safeAll)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                        .buttonStyle(.plain)

                        Button("Deselect All") {
                            applySelectionPreset(.none)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .buttonStyle(.plain)
                    }
                }

                // Search input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                    TextField("Filter project or tool...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 150)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.10)))

                // Sort Picker
                Menu {
                    ForEach(SortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if sortMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortMode.rawValue)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    pickWorkspaceFolder(autoScan: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("Add Folder")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Add a developer workspace folder and rescan")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Optional Docker daemon notice when Docker tab is selected
            if selectedCategory == .dockerContainers, let note = result.dockerStatusNote {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(palette.accent)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            // Artifact List
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(palette.accent.opacity(0.85))
                    Text(result.items.isEmpty ? "Your developer storage is spotless!" : "No items match your current filter.")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(result.items.isEmpty
                         ? "Scanned \(result.scannedWorkspaces.count) workspace(s) in \(String(format: "%.1fs", result.scanDurationSeconds))."
                         : "Try clearing the search query or age filter to inspect all discovered items.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(visible) { item in
                            DevAIArtifactRow(
                                item: item,
                                palette: palette,
                                onToggle: { toggleItem(item.id) },
                                onReveal: {
                                    if case .filesystemPath = item.actionKind {
                                        FileSystemHelpers.revealInFinder(path: item.path)
                                    } else if case .ollamaModel = item.actionKind {
                                        FileSystemHelpers.revealInFinder(path: item.path)
                                    }
                                },
                                onCopyPath: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.path, forType: .string)
                                    appState.showBanner("Copied path to clipboard")
                                },
                                onIgnore: {
                                    appState.addToIgnoreList(
                                        path: item.path,
                                        displayName: item.name,
                                        category: .devAISweeper,
                                        description: "\(item.ecosystem) artifact excluded from Dev & AI Sweeper"
                                    )
                                    appState.devAISweeperResult.items.removeAll { $0.id == item.id }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
            }

            // Bottom Action Bar
            HStack(spacing: 14) {
                // Trash vs Immediate Delete safety mode
                HStack(spacing: 6) {
                    Button {
                        moveToTrash = true
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(moveToTrash ? palette.primary.opacity(0.75) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        moveToTrash = false
                    } label: {
                        Label("Free Immediately", systemImage: "bolt.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(!moveToTrash ? Color(hex: "FF6B4A").opacity(0.80) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .help("Move to Trash lets you undo from macOS Trash; Free Immediately deletes regenerable build folders directly to reclaim disk space right away.")

                if result.scanDurationSeconds > 0 {
                    Text("Scanned in \(String(format: "%.1fs", result.scanDurationSeconds))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                if selectedCount > 0 {
                    Button("Review (\(selectedCount))") {
                        showReviewSheet = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .buttonStyle(.plain)
                }

                UbiquitousButton(
                    title: "Sweep",
                    subtitle: selectedCount == 0 ? nil : ByteFormat.string(selectedBytes),
                    palette: palette,
                    isDisabled: selectedCount == 0
                ) {
                    if !moveToTrash {
                        showConfirmDeleteAlert = true
                    } else {
                        appState.cleanSelectedDevAIItems(moveToTrash: true)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showReviewSheet) {
            reviewSheet
        }
        .alert("Free \(ByteFormat.string(selectedBytes)) immediately?", isPresented: $showConfirmDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Immediately", role: .destructive) {
                appState.cleanSelectedDevAIItems(moveToTrash: false)
            }
        } message: {
            Text("This permanently deletes \(selectedCount) selected artifact(s) without sending them to Trash. Source code is untouched; dependencies can be rebuilt with your package manager.")
        }
    }

    // MARK: - Review Sheet

    private var reviewSheet: some View {
        let selected = appState.devAISweeperResult.items.filter(\.isSelected)
        let bytes = selected.reduce(Int64(0)) { $0 + $1.sizeBytes }

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Dev & AI Sweep")
                        .font(.headline)
                    Text("\(selected.count) selected item(s) totaling \(ByteFormat.string(bytes)) • Mode: \(moveToTrash ? "Move to Trash" : "Delete Immediately")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showReviewSheet = false }
            }
            .padding()
            Divider()
            List(selected) { item in
                HStack {
                    Image(systemName: item.category.iconName)
                        .foregroundStyle(Color(hex: item.category.accentHex))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.name).fontWeight(.semibold)
                            Text(item.ecosystem)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        }
                        Text(item.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(ByteFormat.string(item.sizeBytes))
                        .font(.callout.monospacedDigit())
                    Button("Deselect") {
                        toggleItem(item.id)
                        if appState.devAISweeperResult.items.filter(\.isSelected).isEmpty {
                            showReviewSheet = false
                        }
                    }
                    .controlSize(.small)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Sweep Selected (\(ByteFormat.string(bytes)))", role: .destructive) {
                    showReviewSheet = false
                    appState.cleanSelectedDevAIItems(moveToTrash: moveToTrash)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding()
        }
        .frame(width: 660, height: 460)
    }

    // MARK: - Helpers

    private func categoryPill(
        title: String,
        icon: String,
        bytes: Int64,
        count: Int,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if count > 0 {
                    Text(ByteFormat.string(bytes))
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.72))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.22 : 0.10)))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.75) : Color.white.opacity(0.09))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private enum SelectionPreset {
        case stale30
        case safeAll
        case none
    }

    private func applySelectionPreset(_ preset: SelectionPreset) {
        for idx in appState.devAISweeperResult.items.indices {
            let item = appState.devAISweeperResult.items[idx]
            switch preset {
            case .stale30:
                if item.category == .projectArtifacts {
                    appState.devAISweeperResult.items[idx].isSelected = (item.ageDays ?? 0) >= 30 && item.isSafeAutoSelect
                } else {
                    appState.devAISweeperResult.items[idx].isSelected = item.isSafeAutoSelect
                }
            case .safeAll:
                appState.devAISweeperResult.items[idx].isSelected = item.isSafeAutoSelect
            case .none:
                appState.devAISweeperResult.items[idx].isSelected = false
            }
        }
    }

    private func toggleItem(_ id: UUID) {
        if let idx = appState.devAISweeperResult.items.firstIndex(where: { $0.id == id }) {
            appState.devAISweeperResult.items[idx].isSelected.toggle()
        }
    }

    private func pickWorkspaceFolder(autoScan: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Workspace"
        panel.message = "Choose a folder containing your coding projects (e.g. working-directory, Projects, Code)."
        if panel.runModal() == .OK, let url = panel.url {
            appState.addDevWorkspaceFolder(url.path)
            if autoScan {
                appState.startDevAISweeperScan()
            }
        }
    }
}

// MARK: - Artifact Row

private struct DevAIArtifactRow: View {
    let item: DevAIArtifactItem
    let palette: ModulePalette
    let onToggle: () -> Void
    let onReveal: () -> Void
    let onCopyPath: () -> Void
    let onIgnore: () -> Void
    @State private var isHovered = false

    private var abbreviatedPath: String {
        let home = FileSystemHelpers.homeDirectory
        if item.path.hasPrefix(home) {
            return "~" + item.path.dropFirst(home.count)
        }
        return item.path
    }

    private var tint: Color {
        Color(hex: item.category.accentHex)
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { item.isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.20))
                    .frame(width: 34, height: 34)
                Image(systemName: item.category.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(item.ecosystem)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.16)))

                    if let badge = item.badge {
                        let isStale = badge.hasPrefix("Stale")
                        let isCaution = badge == "Caution" || badge == "Exceeds RAM"
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    isCaution ? Color(hex: "FF5E57").opacity(0.65)
                                    : (isStale ? Color(hex: "FFB703").opacity(0.45) : Color.white.opacity(0.12))
                                )
                            )
                    }
                }

                Text(abbreviatedPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(item.rebuildHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    if item.itemCount > 0 {
                        Text("• \(ByteFormat.itemCount(item.itemCount))")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }

            Spacer(minLength: 10)

            Text(ByteFormat.string(item.sizeBytes))
                .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)

            if case .filesystemPath = item.actionKind {
                Button(action: onReveal) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(isHovered ? 0.85 : 0.35))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(item.isSelected ? palette.primary.opacity(0.18) : (isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.06)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(item.isSelected ? palette.primary.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            if case .filesystemPath = item.actionKind {
                Button("Reveal in Finder", action: onReveal)
            }
            Button("Copy Path / Command", action: onCopyPath)
            Divider()
            Button("Add to Ignore List", action: onIgnore)
        }
    }
}
