import SwiftUI
import AppKit

public struct PortKillerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: PortServiceCategory? = nil
    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .categoryAndPort
    @State private var expandedItemID: String? = nil
    @State private var autoRefreshEnabled: Bool = true
    @State private var confirmForceKillItem: ActivePortItem? = nil
    @State private var confirmStopAllDevServers: Bool = false
    private let palette = RCleanerTheme.palette(for: .portKiller)
    private let refreshTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    private enum SortMode: String, CaseIterable, Identifiable {
        case categoryAndPort = "Smart Order"
        case portAsc = "Port Number"
        case memoryDesc = "Highest RAM"
        case nameAsc = "Project Name"
        var id: String { rawValue }
    }

    public init() {}

    /// If the user typed a valid port number (e.g. "3000" or ":5173") into the search bar, returns that port.
    private var typedPortNumber: Int? {
        let raw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
        guard let port = Int(raw), port > 0 && port <= 65535 else { return nil }
        return port
    }

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

        VStack(spacing: 0) {
            // MARK: - 1. Clean Header + Inline Summary Badges
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Port Killer")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if appState.isScanningPorts {
                            ProgressView()
                                .controlSize(.small)
                                .tint(palette.accent)
                        }
                    }

                    // Sleek Inline Summary Strip (replaces the 4 bulky boxes & watched-port clutter)
                    HStack(spacing: 8) {
                        summaryBadge(
                            icon: "circle.fill",
                            iconSize: 7,
                            label: "\(snap.items.count) Active Ports",
                            tint: Color(hex: "2ED573"),
                            isActive: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                        }

                        summaryBadge(
                            icon: "globe",
                            iconSize: 11,
                            label: "\(snap.devServersCount) Dev \(snap.devServersCount == 1 ? "Server" : "Servers")",
                            tint: Color(hex: "00F5D4"),
                            isActive: selectedCategory == .devWebServer
                        ) {
                            selectedCategory = (selectedCategory == .devWebServer) ? nil : .devWebServer
                        }

                        if snap.count(for: .databaseCache) > 0 {
                            let dbCount = snap.count(for: .databaseCache)
                            summaryBadge(
                                icon: "cylinder.split.1x2.fill",
                                iconSize: 10.5,
                                label: "\(dbCount) \(dbCount == 1 ? "Database" : "Databases")",
                                tint: Color(hex: "FFB703"),
                                isActive: selectedCategory == .databaseCache
                            ) {
                                selectedCategory = (selectedCategory == .databaseCache) ? nil : .databaseCache
                            }
                        }

                        summaryBadge(
                            icon: "memorychip",
                            iconSize: 11,
                            label: ByteFormat.string(snap.totalMemoryBytes),
                            tint: Color(hex: "C77DFF"),
                            isActive: sortMode == .memoryDesc
                        ) {
                            sortMode = (sortMode == .memoryDesc) ? .categoryAndPort : .memoryDesc
                        }

                        if snap.lanExposedCount > 0 {
                            HStack(spacing: 5) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Color(hex: "FFB703"))
                                Text("\(snap.lanExposedCount) on LAN")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                        }
                    }
                }

                Spacer(minLength: 360) // Keeps header clear of top-right floating HUD pills
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // MARK: - 2. Single Unified Filter & Search Toolbar
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryTab(
                            title: "All",
                            count: snap.items.count,
                            isSelected: selectedCategory == nil,
                            tint: palette.primary
                        ) {
                            selectedCategory = nil
                        }

                        ForEach(PortServiceCategory.allCases) { cat in
                            let count = snap.count(for: cat)
                            if count > 0 || selectedCategory == cat {
                                categoryTab(
                                    title: cat.shortTitle,
                                    count: count,
                                    isSelected: selectedCategory == cat,
                                    tint: Color(hex: cat.accentHex)
                                ) {
                                    selectedCategory = (selectedCategory == cat) ? nil : cat
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 6)

                // Smart Search + Instant Port Kill Input
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    TextField("Search port (e.g. 5173) or project...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 195)
                        .onSubmit {
                            if let port = typedPortNumber {
                                appState.killPortByNumber(port, force: false)
                                searchText = ""
                            }
                        }

                    if let port = typedPortNumber,
                       snap.items.contains(where: { $0.port == port && !$0.isSystemProtected }) {
                        Button {
                            appState.killPortByNumber(port, force: false)
                            searchText = ""
                        } label: {
                            Text("Kill :\(String(port))")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(hex: "FF5E57")))
                        }
                        .buttonStyle(.plain)
                    }

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.11), lineWidth: 1))

                // Compact Sort Menu
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
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Refresh Button
                Button {
                    appState.refreshListeningPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Refresh listening ports now")
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 12)

            // MARK: - 3. Clean, Breathable Port List
            if visible.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(palette.accent.opacity(0.75))
                    Text(snap.items.isEmpty ? "No Listening Ports Detected" : "No Matching Ports")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(snap.items.isEmpty
                         ? "Your Mac currently has no active TCP servers listening."
                         : "Try clearing your search or switching category tabs.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                    if !searchText.isEmpty || selectedCategory != nil {
                        Button("Reset Filters") {
                            searchText = ""
                            selectedCategory = nil
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
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
                                onToggleExpand: {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
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
                    .padding(.horizontal, 26)
                    .padding(.vertical, 4)
                }
            }

            // MARK: - 4. Minimal Footer Bar
            HStack(spacing: 12) {
                Button {
                    autoRefreshEnabled.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(autoRefreshEnabled ? Color(hex: "2ED573") : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(autoRefreshEnabled ? "Live updates active (every 4s)" : "Live updates paused")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .buttonStyle(.plain)

                Text("•")
                    .foregroundStyle(.white.opacity(0.25))

                Text("Click any row to view full command & options")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                if snap.devServersCount > 0 {
                    Button {
                        confirmStopAllDevServers = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "power")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Stop All Dev Servers (\(snap.devServersCount))")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: "FF7B72"))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Color(hex: "FF5E57").opacity(0.32), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
        }
        .onAppear {
            appState.refreshListeningPorts()
        }
        .onReceive(refreshTimer) { _ in
            guard autoRefreshEnabled, appState.selectedModule == .portKiller else { return }
            appState.refreshListeningPorts(silent: true)
        }
        .alert(
            "Force Kill :\(confirmForceKillItem.map { String($0.port) } ?? "") (\(confirmForceKillItem?.displayTitle ?? ""))?",
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
                Text("Immediately terminates PID \(String(item.pid)) (\(item.processName)) with SIGKILL (-9) and frees port :\(String(item.port)).")
            }
        }
        .alert(
            "Stop All \(snap.devServersCount) Active Dev Servers?",
            isPresented: $confirmStopAllDevServers
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Stop Dev Servers", role: .destructive) {
                appState.selectPortItems(category: .devWebServer)
                appState.killSelectedPorts(force: false)
            }
        } message: {
            Text("Gracefully stops all active local development web servers (Node, Vite, Next.js, Python, Go) while leaving databases and apps untouched.")
        }
    }

    // MARK: - Subcomponents

    private func summaryBadge(
        icon: String,
        iconSize: CGFloat,
        label: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(isActive ? 0.96 : 0.80))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isActive ? tint.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(isActive ? tint.opacity(0.45) : Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryTab(
        title: String,
        count: Int,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                    .lineLimit(1)

                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                    )
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.68) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Clean 2-Line Port & Server Card

private struct PortServerCardView: View {
    let item: ActivePortItem
    let isExpanded: Bool
    let palette: ModulePalette
    let onToggleExpand: () -> Void
    let onGracefulStop: () -> Void
    let onForceKill: () -> Void
    let onCopy: (String, String) -> Void
    @State private var isHovered = false

    private var tint: Color {
        Color(hex: item.category.accentHex)
    }

    private var abbreviatedCwd: String? {
        guard let cwd = item.workingDirectory, !cwd.isEmpty, cwd != "/" else { return nil }
        let home = FileSystemHelpers.homeDirectory
        if cwd.hasPrefix(home) {
            let suffix = cwd.dropFirst(home.count)
            return suffix.isEmpty ? "~" : "~" + suffix
        }
        return cwd
    }

    /// Clean single-line subtitle combining path/process + PID (no comma!) + RAM
    private var cleanSubtitle: String {
        var parts: [String] = []
        if let cwd = abbreviatedCwd {
            parts.append(cwd)
        } else {
            parts.append(item.processName)
        }
        parts.append("PID \(String(item.pid))")
        if item.memoryBytes > 0 {
            parts.append(ByteFormat.string(item.memoryBytes))
        }
        return parts.joined(separator: "  •  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRowView
            if isExpanded {
                expandedDrawerView
            }
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .contextMenu { contextMenuItems }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isHovered || isExpanded ? Color.white.opacity(0.085) : Color.white.opacity(0.05))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isExpanded ? tint.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
    }

    private var mainRowView: some View {
        HStack(spacing: 14) {
            portBadgeView
            titleSectionView
            Spacer(minLength: 10)
            actionButtonsView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpand()
        }
    }

    private var portBadgeView: some View {
        let dotColor = item.isExposedToLAN ? Color(hex: "FFB703") : tint
        return HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6.5, height: 6.5)
                .shadow(color: dotColor.opacity(0.8), radius: 3)

            Text(":\(String(item.port))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: 78, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var titleSectionView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(item.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.frameworkLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tint.opacity(0.14)))
                    .lineLimit(1)

                if item.isExposedToLAN {
                    Text("LAN")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color(hex: "FFB703"))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(hex: "FFB703").opacity(0.15)))
                        .help("Listening on \(item.bindAddress) — reachable from other devices on your network")
                }

                if item.cpuPercent >= 5.0 {
                    Text(String(format: "%.0f%% CPU", item.cpuPercent))
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color(hex: "FF9F43"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(hex: "FF9F43").opacity(0.15)))
                }

                if item.isSystemProtected {
                    Text("macOS")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }

            Text(cleanSubtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var actionButtonsView: some View {
        HStack(spacing: 7) {
            if let webURL = item.localWebURL {
                Button {
                    NSWorkspace.shared.open(webURL)
                } label: {
                    HStack(spacing: 3) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "00F5D4"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: "00F5D4").opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color(hex: "00F5D4").opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Open \(webURL.absoluteString) in browser")
            }

            if let cwd = item.workingDirectory, !cwd.isEmpty, cwd != "/" {
                Button {
                    FileSystemHelpers.revealInFinder(path: cwd)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Reveal project folder in Finder")
            }

            if !item.isSystemProtected {
                Button(action: onGracefulStop) {
                    Text("Stop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "FF7B72"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color(hex: "FF5E57").opacity(isHovered ? 0.24 : 0.14))
                        )
                        .overlay(
                            Capsule().strokeBorder(Color(hex: "FF5E57").opacity(0.38), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Stop server on port :\(String(item.port)) (right-click or expand for Force Kill -9)")
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 18)
        }
    }

    private var expandedDrawerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    detailPill(label: "PID", value: String(item.pid))
                    detailPill(label: "Process", value: item.processName)
                    detailPill(label: "Bind", value: "\(item.bindAddress):\(String(item.port))")
                    detailPill(label: "Uptime", value: item.uptimeLabel)
                    if item.cpuPercent > 0 {
                        detailPill(label: "CPU", value: String(format: "%.1f%%", item.cpuPercent))
                    }
                    Spacer()
                }

                if let cwd = item.workingDirectory, !cwd.isEmpty {
                    inspectorRow(
                        label: "Folder",
                        value: cwd,
                        copyValue: cwd,
                        copyLabel: "Project Path",
                        revealPath: cwd
                    )
                }

                inspectorRow(
                    label: "Command",
                    value: item.commandLine,
                    copyValue: item.commandLine,
                    copyLabel: "Command"
                )

                if !item.isSystemProtected {
                    HStack(spacing: 8) {
                        Spacer()
                        Button(action: onGracefulStop) {
                            Label("Graceful Stop (SIGTERM)", systemImage: "stop.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)

                        Button(action: onForceKill) {
                            Label("Force Kill (SIGKILL -9)", systemImage: "bolt.slash.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.82)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.black.opacity(0.16))
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let webURL = item.localWebURL {
            Button("Open http://localhost:\(String(item.port)) in Browser") {
                NSWorkspace.shared.open(webURL)
            }
            Button("Copy http://localhost:\(String(item.port))") {
                onCopy("http://localhost:\(String(item.port))", "URL")
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
        Button("Copy PID (\(String(item.pid)))") {
            onCopy(String(item.pid), "PID")
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

    private func detailPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
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
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
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
