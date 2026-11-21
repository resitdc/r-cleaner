import SwiftUI

public struct CleanupView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategoryID: String?
    @State private var selectedGroupID: String?
    @State private var searchText: String = ""
    @State private var sortBySize: Bool = true
    @State private var showRiskyCleanAlert: Bool = false
    @State private var riskyCleanAlertTitle: String = ""
    @State private var riskyCleanAlertMessage: String = ""
    private let palette = RCleanerTheme.palette(for: .cleanup)

    public init() {}

    public var body: some View {
        switch appState.cleanupStage {
        case .intro:
            ModuleIntroHero(
                title: "Cleanup",
                subtitle: "Clean your system to achieve maximum performance and reclaim free space.",
                iconName: "trash.circle.fill",
                palette: palette,
                features: [
                    ("sparkles.rectangle.stack.fill", "System Junk", "User & system caches, logs, Xcode DerivedData, broken preferences, iOS backups."),
                    ("envelope.open.fill", "Mail Attachments", "Removes locally cached email attachment downloads while keeping online copies."),
                    ("trash.fill", "Trash Bins", "Empties Macintosh HD and connected drive Trash bins at once."),
                    ("wand.and.rays", "AI Clutter (New)", "Finds caches, logs & local models from Claude, Codex, Gemini, Cursor, Ollama, and LM Studio.")
                ],
                primaryActionTitle: "Scan",
                onPrimaryAction: { appState.startCleanupScan() }
            )

        case .scanning:
            ScanningProgressView(
                title: "Looking for junk...",
                subtitle: "Checking caches, logs, mail attachments, trash bins, and AI clutter.",
                currentPath: appState.cleanupStatusText,
                progress: appState.cleanupProgress,
                iconName: "trash.circle.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview:
            cleanupOverviewView

        case .dataManager(let initialCat):
            cleanupDataManagerView
                .onAppear {
                    if selectedCategoryID == nil {
                        selectedCategoryID = initialCat ?? appState.cleanupCategories.first?.id
                    }
                    syncSelectedGroup()
                }

        case .cleaning:
            ScanningProgressView(
                title: "Cleaning junk...",
                subtitle: "Safely removing selected unnecessary files.",
                currentPath: appState.cleanupStatusText,
                progress: appState.cleanupProgress,
                iconName: "sparkles",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.cleanupSummary {
                CleanupCompleteView(
                    summary: summary,
                    palette: palette,
                    onDone: { appState.cleanupStage = .intro },
                    onReviewRemaining: { appState.startCleanupScan() }
                )
            }
        }
    }

    // MARK: - Results Overview Tiles

    private var cleanupOverviewView: some View {
        let totalSelected = appState.cleanupCategories.reduce(0) { $0 + $1.selectedBytes }
        let totalFound = appState.cleanupCategories.reduce(0) { $0 + $1.totalBytes }

        return VStack(spacing: 0) {
            ModuleHeaderBar(title: "Cleanup", backTitle: "Start Over") {
                appState.cleanupStage = .intro
            }

            if appState.cleanupCategories.isEmpty {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(hex: "2ED573"))
                Text("Your Mac is pure!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                Text("There's nothing to be cleaned from your system right now.")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                UbiquitousButton(title: "Scan", palette: palette) { appState.startCleanupScan() }
                    .padding(.bottom, 22)
            } else {
                VStack(spacing: 6) {
                    Text("There are \(ByteFormat.string(totalFound)) of junk files on your Mac.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(ByteFormat.string(totalSelected)) smartly selected for safe removal.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 12)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 16)], spacing: 16) {
                        ForEach(appState.cleanupCategories) { cat in
                            GlassCard(padding: 18, cornerRadius: 18) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: cat.iconName)
                                            .font(.system(size: 24))
                                            .foregroundStyle(palette.accent)
                                        Spacer()
                                        if let badge = cat.badge {
                                            Text(badge)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Capsule().fill(palette.primary))
                                        }
                                    }

                                    Text(cat.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)

                                    Text(ByteFormat.string(cat.totalBytes))
                                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                                        .foregroundStyle(palette.accent)

                                    Text(cat.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(2)

                                    HStack {
                                        Text("\(cat.totalCount) items • \(ByteFormat.string(cat.selectedBytes)) selected")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.55))
                                        Spacer()
                                        Button("Review") {
                                            selectedCategoryID = cat.id
                                            selectedGroupID = cat.groups.first?.id
                                            appState.cleanupStage = .dataManager(categoryID: cat.id)
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color.white.opacity(0.15)))
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                }

                HStack(spacing: 16) {
                    Button {
                        selectedCategoryID = appState.cleanupCategories.first?.id
                        selectedGroupID = appState.cleanupCategories.first?.groups.first?.id
                        appState.cleanupStage = .dataManager(categoryID: selectedCategoryID)
                    } label: {
                        Text("Review All Junk")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)

                    UbiquitousButton(
                        title: "Clean",
                        subtitle: ByteFormat.string(totalSelected),
                        palette: palette,
                        isDisabled: totalSelected == 0
                    ) {
                        appState.runCleanupClean()
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Full 3-Pane Data Manager

    private var cleanupDataManagerView: some View {
        let totalSelected = appState.cleanupCategories.reduce(0) { $0 + $1.selectedBytes }

        return VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "Cleanup Manager",
                backTitle: "Back",
                trailingText: "Selected: \(ByteFormat.string(totalSelected))"
            ) {
                appState.cleanupStage = .resultsOverview
            }

            // Category Pills + Search + Sort Bar
            HStack(spacing: 10) {
                ForEach(appState.cleanupCategories) { cat in
                    Button {
                        selectedCategoryID = cat.id
                        selectedGroupID = cat.groups.first?.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.iconName)
                            Text(cat.title)
                            Text(ByteFormat.string(cat.totalBytes))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selectedCategoryID == cat.id ? palette.primary.opacity(0.75) : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 140)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.10)))

                Button {
                    sortBySize.toggle()
                } label: {
                    Label(sortBySize ? "Size" : "Name", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Select All in Group") { applyGroupSelection(true) }
                    Button("Deselect All in Group") { applyGroupSelection(false) }
                } label: {
                    Label("Select", systemImage: "checklist")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)

            // Split View: Groups (Left) | Items (Right)
            HStack(spacing: 14) {
                // Groups List
                ScrollView {
                    VStack(spacing: 8) {
                        if let catIdx = currentCategoryIndex {
                            ForEach(appState.cleanupCategories[catIdx].groups.indices, id: \.self) { gIdx in
                                let group = appState.cleanupCategories[catIdx].groups[gIdx]
                                let isSelGroup = selectedGroupID == group.id
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(
                                        get: { group.isAllSelected },
                                        set: { newVal in
                                            for i in appState.cleanupCategories[catIdx].groups[gIdx].items.indices {
                                                if !appState.cleanupCategories[catIdx].groups[gIdx].items[i].isProtected {
                                                    appState.cleanupCategories[catIdx].groups[gIdx].items[i].isSelected = newVal
                                                }
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()

                                    Image(systemName: group.iconName)
                                        .foregroundStyle(palette.accent)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text("\(group.items.count) items")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                    Spacer()
                                    Text(ByteFormat.string(group.selectedBytes))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelGroup ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                                )
                                .onTapGesture { selectedGroupID = group.id }
                            }
                        }
                    }
                }
                .frame(width: 280)

                // Items List
                VStack(alignment: .leading, spacing: 10) {
                    if let catIdx = currentCategoryIndex, let gIdx = currentGroupIndex(in: catIdx) {
                        let group = appState.cleanupCategories[catIdx].groups[gIdx]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            Text(group.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                        .padding(.horizontal, 6)

                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredItemIndices(catIdx: catIdx, gIdx: gIdx), id: \.self) { iIdx in
                                    let item = appState.cleanupCategories[catIdx].groups[gIdx].items[iIdx]
                                    HStack(spacing: 10) {
                                        Toggle("", isOn: $appState.cleanupCategories[catIdx].groups[gIdx].items[iIdx].isSelected)
                                            .toggleStyle(.checkbox)
                                            .labelsHidden()
                                            .disabled(item.isProtected)

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(item.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                if let badge = item.badge {
                                                    Text(badge)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundStyle(palette.accent)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Capsule().fill(palette.primary.opacity(0.25)))
                                                }
                                            }
                                            Text(item.path)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.5))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }

                                        Spacer()

                                        Text(ByteFormat.string(item.sizeBytes))
                                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.9))

                                        Button {
                                            FileSystemHelpers.revealInFinder(path: item.path)
                                        } label: {
                                            Image(systemName: "magnifyingglass.circle")
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Reveal in Finder")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                                    .contextMenu {
                                        Button("Reveal in Finder") { FileSystemHelpers.revealInFinder(path: item.path) }
                                        Button("Add \"\(item.name)\" to Ignore List") {
                                            let ignoreCat: IgnoreListCategory = item.categoryID == "aiClutter" ? .aiClutter : (item.categoryID == "mailAttachments" ? .mailAttachments : .systemJunk)
                                            appState.addToIgnoreList(path: item.path, displayName: item.name, category: ignoreCat, description: item.groupTitle)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Spacer()
                        Text("Select a category to inspect items.")
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 22)

            // Bottom Clean Footer
            HStack {
                Spacer()
                UbiquitousButton(
                    title: "Clean",
                    subtitle: ByteFormat.string(totalSelected),
                    palette: palette,
                    isDisabled: totalSelected == 0
                ) {
                    triggerCleanWithSafetyCheck()
                }
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .alert(riskyCleanAlertTitle, isPresented: $showRiskyCleanAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) { appState.runCleanupClean() }
        } message: {
            Text(riskyCleanAlertMessage)
        }
    }

    private func applyGroupSelection(_ selected: Bool) {
        guard let catIdx = currentCategoryIndex, let gIdx = currentGroupIndex(in: catIdx) else { return }
        for i in appState.cleanupCategories[catIdx].groups[gIdx].items.indices {
            if !appState.cleanupCategories[catIdx].groups[gIdx].items[i].isProtected {
                appState.cleanupCategories[catIdx].groups[gIdx].items[i].isSelected = selected
            }
        }
    }

    private func triggerCleanWithSafetyCheck() {
        let selected = appState.cleanupCategories.flatMap(\.groups).flatMap(\.items).filter(\.isSelected)
        if selected.contains(where: { $0.groupTitle == "Local Models" }) {
            riskyCleanAlertTitle = "Removing local models may affect your projects"
            riskyCleanAlertMessage = "Selected Ollama/LM Studio models may still be used by your local projects. Removing them requires downloading them again."
            showRiskyCleanAlert = true
            return
        }
        if selected.contains(where: { $0.groupTitle == "iOS Device Backups" && $0.badge == "Latest" }) {
            riskyCleanAlertTitle = "Removing Your Latest Backups"
            riskyCleanAlertMessage = "Your selection includes the most recent backup for one or more iOS devices. If removed, you won't be able to restore from it."
            showRiskyCleanAlert = true
            return
        }
        appState.runCleanupClean()
    }

    private var currentCategoryIndex: Int? {
        if let id = selectedCategoryID, let idx = appState.cleanupCategories.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return appState.cleanupCategories.isEmpty ? nil : 0
    }

    private func currentGroupIndex(in catIdx: Int) -> Int? {
        let groups = appState.cleanupCategories[catIdx].groups
        if let id = selectedGroupID, let idx = groups.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return groups.isEmpty ? nil : 0
    }

    private func syncSelectedGroup() {
        if let catIdx = currentCategoryIndex {
            selectedGroupID = appState.cleanupCategories[catIdx].groups.first?.id
        }
    }

    private func filteredItemIndices(catIdx: Int, gIdx: Int) -> [Int] {
        let items = appState.cleanupCategories[catIdx].groups[gIdx].items
        let indices = items.indices.filter { idx in
            searchText.isEmpty || items[idx].name.localizedCaseInsensitiveContains(searchText) || items[idx].path.localizedCaseInsensitiveContains(searchText)
        }
        return indices.sorted { a, b in
            if sortBySize {
                return items[a].sizeBytes > items[b].sizeBytes
            }
            return items[a].name.localizedCaseInsensitiveCompare(items[b].name) == .orderedAscending
        }
    }
}
