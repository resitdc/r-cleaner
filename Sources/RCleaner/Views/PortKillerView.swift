import SwiftUI
import AppKit

public struct PortKillerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: PortServiceCategory? = nil
    @State private var searchText: String = ""
    @State private var quickKillPortInput: String = ""
    @State private var sortMode: SortMode = .categoryAndPort
    @State private var expandedItemID: String? = nil
    @State private var autoRefreshEnabled: Bool = true
    @State private var confirmForceKillItem: ActivePortItem? = nil
    private let palette = RCleanerTheme.palette(for: .portKiller)
    private let refreshTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    private enum SortMode: String, CaseIterable, Identifiable {
        case categoryAndPort = "Smart Order"
        case portAsc = "Port Number"
        case memoryDesc = "Highest RAM"
        case nameAsc = "Project / App Name"
        var id: String { rawValue }
    }

    public init() {}

    private var filteredItems: [ActivePortItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = appState.portKillerSnapshot.items.filter { item in
            if let cat = selectedCategory, item.category != cat { return false }
            if !query.isEmpty {
                let hay = ":\(item.port) \(item.port) \(item.displayTitle) \(item.processName) \(item.frameworkLabel) \(item.pid) \(item.workingDirectory ?? "") \(item.commandLine)".lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }

        switch sortMode {
        case .categoryAndPort:
            return base
        case .portAsc:
            return base.sorted { $0.port < $1.port }
        case .memoryDesc:
            return base.sorted { $0.memoryBytes > $1.memoryBytes }
        case .nameAsc:
            return base.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    public var body: some View {
        let snap = appState.portKillerSnapshot
        let visible = filteredItems
        let selectedItems = snap.items.filter { $0.isSelected && !$0.isSystemProtected }
        let activePortSet = Set(snap.items.map(\.port))

        VStack(spacing: 0) {
            // Top Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Active Port & Local Server Killer")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if appState.isScanningPorts {
                            ProgressView()
                                .controlSize(.small)
                                .tint(palette.accent)
                        }
                    }
                    Text("Inspect listening TCP ports, see which project folder owns each local server, and free stuck ports in one click.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer(minLength: 355) // Keeps header clear of top-right HUD pills
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // 4 Summary Metric Cards
            HStack(spacing: 12) {
                summaryTile(
                    title: "Listening Ports",
                    value: "\(snap.items.count)",
                    subtitle: "Updated \(snap.lastUpdated.formatted(date: .omitted, time: .standard))",
                    icon: "network",
                    tint: palette.primary
                ) {
                    selectedCategory = nil
                }

                summaryTile(
                    title: "Dev & Web Servers",
                    value: "\(snap.devServersCount)",
                    subtitle: snap.devServersCount == 0 ? "No active dev servers" : "Node, Vite, Next, Python, Go",
                    icon: "globe",
                    tint: Color(hex: "00F5D4")
                ) {
                    selectedCategory = (selectedCategory == .devWebServer) ? nil : .devWebServer
                }

                summaryTile(
                    title: "Databases & AI",
                    value: "\(snap.databasesAndAICount)",
                    subtitle: "PostgreSQL, MySQL, Redis, Ollama",
                    icon: "cylinder.split.1x2.fill",
                    tint: Color(hex: "FFB703")
                ) {
                    selectedCategory = (selectedCategory == .databaseCache) ? nil : .databaseCache
                }

                summaryTile(
                    title: "Server Memory",
                    value: ByteFormat.string(snap.totalMemoryBytes),
                    subtitle: "\(snap.lanExposedCount) exposed on LAN (0.0.0.0)",
                    icon: "memorychip.fill",
                    tint: Color(hex: "C77DFF")
                ) {
                    sortMode = .memoryDesc
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            // Quick Watched Ports Strip + Instant "Kill Port #" Box
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.accent)
                    Text("Watch:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PortKillerService.watchedDevPorts, id: \.self) { watchedPort in
                            let isActive = activePortSet.contains(watchedPort)
                            let isFiltered = searchText == "\(watchedPort)"
                            Button {
                                if isFiltered {
                                    searchText = ""
                                } else {
                                    selectedCategory = nil
                                    searchText = "\(watchedPort)"
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(isActive ? Color(hex: "00F5D4") : Color.white.opacity(0.22))
                                        .frame(width: 6, height: 6)
                                        .shadow(color: isActive ? Color(hex: "00F5D4").opacity(0.9) : .clear, radius: 3)
                                    Text(":\(String(watchedPort))")
                                        .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .monospaced))
                                        .foregroundStyle(isActive ? .white : .white.opacity(0.48))
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(
                                        isFiltered
                                            ? palette.primary.opacity(0.75)
                                            : (isActive ? Color(hex: "00F5D4").opacity(0.16) : Color.white.opacity(0.05))
                                    )
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        isActive ? Color(hex: "00F5D4").opacity(0.45) : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .help(isActive ? "Port :\(watchedPort) is ACTIVE — click to filter" : "Port :\(watchedPort) is free")
                        }
                    }
                }

                // Direct "Kill by Port #" input box
                HStack(spacing: 6) {
                    Text(":")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.accent)
                    TextField("Port #", text: $quickKillPortInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 58)
                        .onSubmit {
                            triggerQuickKillByPortNumber()
                        }
                    Button("Kill Port") {
                        triggerQuickKillByPortNumber()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.82)))
                    .buttonStyle(.plain)
                    .disabled(Int(quickKillPortInput.trimmingCharacters(in: .whitespaces)) == nil)
                }
                .padding(.leading, 10)
                .padding(.trailing, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Category Filter Pills + Search + Sort + Auto-Refresh Toolbar
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        categoryFilterPill(
                            title: "All Ports",
                            icon: "square.grid.2x2.fill",
                            count: snap.items.count,
                            isSelected: selectedCategory == nil,
                            tint: palette.primary
                        ) {
                            selectedCategory = nil
                        }

                        ForEach(PortServiceCategory.allCases) { cat in
                            let count = snap.count(for: cat)
                            categoryFilterPill(
                                title: cat.shortTitle,
                                icon: cat.iconName,
                                count: count,
                                isSelected: selectedCategory == cat,
                                tint: Color(hex: cat.accentHex)
                            ) {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                }

                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                    TextField("Search port, project, PID...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 155)
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

                // Sort Menu
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

                // Auto-refresh toggle pill
                Button {
                    autoRefreshEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(autoRefreshEnabled ? Color(hex: "2ED573") : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                        Text("Live")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(autoRefreshEnabled ? Color(hex: "2ED573").opacity(0.18) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Toggle automatic 4-second live port refresh")

                Button {
                    appState.refreshListeningPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Refresh listening ports now")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Main Port Cards List
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(palette.accent.opacity(0.8))
                    Text(snap.items.isEmpty ? "No listening TCP ports detected" : "No ports match your current filter")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(snap.items.isEmpty
                         ? "Click Refresh to scan active local servers."
                         : "Try clearing the search box or switching category tabs.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.62))
                    if !searchText.isEmpty || selectedCategory != nil {
                        Button("Reset Filters") {
                            searchText = ""
                            selectedCategory = nil
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(palette.primary.opacity(0.75)))
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visible) { item in
                            PortServerCardView(
                                item: item,
                                isExpanded: expandedItemID == item.id,
                                palette: palette,
                                onToggleSelect: {
                                    appState.togglePortItemSelection(id: item.id)
                                },
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedItemID = (expandedItemID == item.id) ? nil : item.id
                                    }
                                },
                                onGracefulStop: {
                                    appState.killListeningPort(item, force: false)
                                },
                                onForceKill: {
                                    confirmForceKillItem = item
                                },
                                onCopy: { text, label in
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                    appState.showBanner("Copied \(label) to clipboard")
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
            }

            // Bottom Batch Action Bar
            HStack(spacing: 12) {
                Button("Select Dev Servers") {
                    appState.selectPortItems(category: .devWebServer)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .buttonStyle(.plain)

                if !selectedItems.isEmpty {
                    Button("Clear Selection (\(selectedItems.count))") {
                        appState.clearPortSelection()
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .buttonStyle(.plain)
                }

                Spacer()

                if !selectedItems.isEmpty {
                    Button {
                        appState.killSelectedPorts(force: false)
                    } label: {
                        Label("Stop Selected (\(selectedItems.count))", systemImage: "stop.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(palette.primary.opacity(0.85)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.killSelectedPorts(force: true)
                    } label: {
                        Label("Force Kill (\(selectedItems.count))", systemImage: "bolt.slash.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.88)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Tip: Click any row to inspect full CLI command, working folder & bind address")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .onAppear {
            appState.refreshListeningPorts()
        }
        .onReceive(refreshTimer) { _ in
            guard autoRefreshEnabled, appState.selectedModule == .portKiller else { return }
            appState.refreshListeningPorts(silent: true)
        }
        .alert(
            "Force Kill :\(confirmForceKillItem?.port.description ?? "") (\(confirmForceKillItem?.displayTitle ?? ""))?",
            isPresented: Binding(
                get: { confirmForceKillItem != nil },
                set: { if !$0 { confirmForceKillItem = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { confirmForceKillItem = nil }
            Button("Force Kill (SIGKILL -9)", role: .destructive) {
                if let item = confirmForceKillItem {
                    appState.killListeningPort(item, force: true)
                }
                confirmForceKillItem = nil
            }
        } message: {
            if let item = confirmForceKillItem {
                Text("Sends SIGKILL (-9) to PID \(item.pid) (\(item.processName)) immediately freeing port :\(item.port).")
            }
        }
    }

    // MARK: - Subcomponents

    private func triggerQuickKillByPortNumber() {
        let trimmed = quickKillPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), port > 0 && port <= 65535 else { return }
        quickKillPortInput = ""
        appState.killPortByNumber(port, force: true)
    }

    private func summaryTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.20))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 19, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func categoryFilterPill(
        title: String,
        icon: String,
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
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.white.opacity(isSelected ? 0.22 : 0.10)))
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? tint.opacity(0.76) : Color.white.opacity(0.09)))
            .overlay(Capsule().strokeBorder(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Individual Active Port & Local Server Card

private struct PortServerCardView: View {
    let item: ActivePortItem
    let isExpanded: Bool
    let palette: ModulePalette
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void
    let onGracefulStop: () -> Void
    let onForceKill: () -> Void
    let onCopy: (String, String) -> Void
    @State private var isHovered = false

    private var tint: Color {
        Color(hex: item.category.accentHex)
    }

    private var abbreviatedCwd: String? {
        guard let cwd = item.workingDirectory else { return nil }
        let home = FileSystemHelpers.homeDirectory
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Multi-select checkbox
                Toggle("", isOn: Binding(get: { item.isSelected }, set: { _ in onToggleSelect() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(item.isSystemProtected)

                // Prominent Glowing Port Badge (e.g. :5173)
                VStack(spacing: 2) {
                    Text(":\(String(item.port))")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(item.isExposedToLAN ? "LAN *" : "Local")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.isExposedToLAN ? Color(hex: "FFB703") : Color(hex: "00F5D4"))
                }
                .frame(width: 72, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(tint.opacity(0.50), lineWidth: 1)
                )

                // Project / Process Title + Framework Tag + Path + Live Metrics
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(item.displayTitle)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(item.frameworkLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.16)))
                            .lineLimit(1)

                        if item.isSystemProtected {
                            Text("macOS Protected")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                    }

                    if let cwd = abbreviatedCwd {
                        Text(cwd)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(item.commandLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 10) {
                        Text("PID \(item.pid)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                        Text("• \(item.processName)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.60))
                        if item.memoryBytes > 0 {
                            Text("• RAM \(ByteFormat.string(item.memoryBytes))")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        if item.cpuPercent > 0.05 {
                            Text(String(format: "• CPU %.1f%%", item.cpuPercent))
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color(hex: "FF9F43"))
                        }
                        Text("• Up \(item.uptimeLabel)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                }

                Spacer(minLength: 8)

                // Quick Action Buttons
                HStack(spacing: 6) {
                    if let webURL = item.localWebURL {
                        Button {
                            NSWorkspace.shared.open(webURL)
                        } label: {
                            HStack(spacing: 3) {
                                Text("Open")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "00F5D4"))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: "00F5D4").opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color(hex: "00F5D4").opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Open \(webURL.absoluteString) in browser")
                    }

                    if let cwd = item.workingDirectory {
                        Button {
                            FileSystemHelpers.revealInFinder(path: cwd)
                        } label: {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.82))
                                .padding(6)
                                .background(Circle().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .help("Reveal project folder in Finder (\(cwd))")
                    }

                    if !item.isSystemProtected {
                        Button(action: onGracefulStop) {
                            Text("Stop")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(palette.primary.opacity(0.75)))
                        }
                        .buttonStyle(.plain)
                        .help("Gracefully stop process (SIGTERM) on port :\(item.port)")

                        Button(action: onForceKill) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.slash.fill")
                                    .font(.system(size: 9.5))
                                Text("Kill")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.85)))
                        }
                        .buttonStyle(.plain)
                        .help("Force kill process immediately (SIGKILL -9) on port :\(item.port)")
                    }

                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpand()
            }

            // Expandable Deep Process Inspector Drawer
            if isExpanded {
                Divider().overlay(Color.white.opacity(0.10))
                VStack(alignment: .leading, spacing: 8) {
                    inspectorRow(
                        label: "Bind Endpoint",
                        value: "\(item.bindAddress) → TCP :\(item.port) (\(item.isExposedToLAN ? "Accessible from LAN / Wi-Fi" : "Localhost loopback only"))",
                        copyValue: "http://localhost:\(item.port)",
                        copyLabel: "URL"
                    )
                    if let cwd = item.workingDirectory {
                        inspectorRow(
                            label: "Project Directory",
                            value: cwd,
                            copyValue: cwd,
                            copyLabel: "Project Path",
                            revealPath: cwd
                        )
                    }
                    inspectorRow(
                        label: "Full Command",
                        value: item.commandLine,
                        copyValue: item.commandLine,
                        copyLabel: "Command"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.18))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(item.isSelected ? palette.primary.opacity(0.18) : (isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.06)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(item.isSelected ? palette.primary.opacity(0.45) : Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { isHovered = $0 }
        .contextMenu {
            if let webURL = item.localWebURL {
                Button("Open http://localhost:\(item.port) in Browser") {
                    NSWorkspace.shared.open(webURL)
                }
                Button("Copy http://localhost:\(item.port)") {
                    onCopy("http://localhost:\(item.port)", "URL")
                }
            }
            if let cwd = item.workingDirectory {
                Button("Reveal Project Folder in Finder") {
                    FileSystemHelpers.revealInFinder(path: cwd)
                }
                Button("Copy Project Path") {
                    onCopy(cwd, "Project Path")
                }
            }
            Button("Copy PID (\(item.pid))") {
                onCopy("\(item.pid)", "PID")
            }
            Button("Copy Full Command Line") {
                onCopy(item.commandLine, "Command")
            }
            if !item.isSystemProtected {
                Divider()
                Button("Graceful Stop (SIGTERM)", action: onGracefulStop)
                Button("Force Kill (SIGKILL -9)", role: .destructive, action: onForceKill)
            }
        }
    }

    private func inspectorRow(
        label: String,
        value: String,
        copyValue: String,
        copyLabel: String,
        revealPath: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 115, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let revealPath {
                Button("Reveal") {
                    FileSystemHelpers.revealInFinder(path: revealPath)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(hex: "00F5D4"))
                .buttonStyle(.plain)
            }
            Button("Copy") {
                onCopy(copyValue, copyLabel)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.accent)
            .buttonStyle(.plain)
        }
    }
}
