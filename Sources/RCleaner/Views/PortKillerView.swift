import SwiftUI
import AppKit

public struct PortKillerView: View {
    @EnvironmentObject var appState: AppState
    @State private var viewMode: ViewMode = .plasmaBubbles
    @State private var selectedCategory: PortServiceCategory? = nil
    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .categoryAndPort
    @State private var selectedPortID: String? = nil
    @State private var expandedItemID: String? = nil
    @State private var poppingPortIDs: Set<String> = []
    @State private var autoRefreshEnabled: Bool = true
    @State private var confirmForceKillItem: ActivePortItem? = nil
    @State private var confirmStopAllDevServers: Bool = false
    private let palette = RCleanerTheme.palette(for: .portKiller)
    private let refreshTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    private enum ViewMode: String, CaseIterable, Identifiable {
        case plasmaBubbles = "Bubbles"
        case compactList = "List"
        var id: String { rawValue }
    }

    private enum SortMode: String, CaseIterable, Identifiable {
        case categoryAndPort = "Smart Order"
        case memoryDesc = "Largest RAM"
        case portAsc = "Port Number"
        case nameAsc = "Project Name"
        var id: String { rawValue }
    }

    public init() {}

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
        case .memoryDesc:
            return base.sorted { $0.memoryBytes > $1.memoryBytes }
        case .portAsc:
            return base.sorted { $0.port < $1.port }
        case .nameAsc:
            return base.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    private var activeInspectedItem: ActivePortItem? {
        let visible = filteredItems
        if let id = selectedPortID, let found = visible.first(where: { $0.id == id }) {
            return found
        }
        return visible.first
    }

    public var body: some View {
        let snap = appState.portKillerSnapshot
        let visible = filteredItems

        VStack(spacing: 0) {
            headerSection(snap: snap)
            toolbarSection(snap: snap)

            if visible.isEmpty {
                emptyStateView(snap: snap)
            } else if viewMode == .plasmaBubbles {
                plasmaBubbleWorkspace(visible: visible)
            } else {
                compactListView(visible: visible)
            }

            footerSection(snap: snap)
        }
        .onAppear {
            appState.refreshListeningPorts()
        }
        .onReceive(refreshTimer) { _ in
            guard autoRefreshEnabled, appState.selectedModule == .portKiller, poppingPortIDs.isEmpty else { return }
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
                    triggerBubblePopAndKill(item, force: true)
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
                let devItems = snap.items.filter { $0.category == .devWebServer && !$0.isSystemProtected }
                for item in devItems {
                    poppingPortIDs.insert(item.id)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    appState.selectPortItems(category: .devWebServer)
                    appState.killSelectedPorts(force: false)
                    poppingPortIDs.removeAll()
                }
            }
        } message: {
            Text("Gracefully stops all active local development web servers (Node, Vite, Next.js, Python, Go) while leaving databases and apps untouched.")
        }
    }

    // MARK: - Bubble Pop Animation + Kill Trigger

    private func triggerBubblePopAndKill(_ item: ActivePortItem, force: Bool) {
        guard !item.isSystemProtected else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
            _ = poppingPortIDs.insert(item.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            appState.killListeningPort(item, force: force)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                poppingPortIDs.remove(item.id)
            }
        }
    }

    private func copyToClipboard(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.showBanner("Copied \(label) to clipboard")
    }

    // MARK: - 1. Clean Header + Summary Badges

    private func headerSection(snap: PortKillerSnapshot) -> some View {
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

                Spacer(minLength: 360)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    summaryBadge(
                        icon: "circle.fill",
                        iconSize: 7,
                        label: "\(snap.items.count) Active Ports",
                        tint: Color(hex: "2ED573"),
                        isActive: selectedCategory == nil
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedCategory = nil
                        }
                    }

                    summaryBadge(
                        icon: "globe",
                        iconSize: 11,
                        label: "\(snap.devServersCount) Dev \(snap.devServersCount == 1 ? "Server" : "Servers")",
                        tint: Color(hex: "00F5D4"),
                        isActive: selectedCategory == .devWebServer
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedCategory = (selectedCategory == .devWebServer) ? nil : .devWebServer
                        }
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
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                selectedCategory = (selectedCategory == .databaseCache) ? nil : .databaseCache
                            }
                        }
                    }

                    summaryBadge(
                        icon: "memorychip",
                        iconSize: 11,
                        label: ByteFormat.string(snap.totalMemoryBytes),
                        tint: Color(hex: "C77DFF"),
                        isActive: sortMode == .memoryDesc
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            sortMode = (sortMode == .memoryDesc) ? .categoryAndPort : .memoryDesc
                        }
                    }

                    if snap.lanExposedCount > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color(hex: "FFB703"))
                            Text("\(snap.lanExposedCount) on LAN")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - 2. Unified Filter, Search & View Mode Switcher Toolbar

    private func toolbarSection(snap: PortKillerSnapshot) -> some View {
        HStack(spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryTab(
                        title: "All",
                        count: snap.items.count,
                        isSelected: selectedCategory == nil,
                        tint: palette.primary
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedCategory = nil
                        }
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
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    selectedCategory = (selectedCategory == cat) ? nil : cat
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Search + Quick Port Kill Input
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                TextField("Search port (e.g. 5173) or project...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 175)
                    .onSubmit {
                        if let port = typedPortNumber {
                            appState.killPortByNumber(port, force: false)
                            searchText = ""
                        }
                    }

                if let port = typedPortNumber,
                   let match = snap.items.first(where: { $0.port == port && !$0.isSystemProtected }) {
                    Button {
                        triggerBubblePopAndKill(match, force: false)
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
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.11), lineWidth: 1))

            // Bubbles vs List Mode Switcher
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    let isSelected = viewMode == mode
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode == .plasmaBubbles ? "circle.hexagongrid.fill" : "list.bullet")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isSelected ? palette.primary.opacity(0.75) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

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
        .padding(.bottom, 10)
    }

    // MARK: - 3A. Gravity Plasma Bubbles Workspace (Arena + Live HUD Inspector Dock)

    private func plasmaBubbleWorkspace(visible: [ActivePortItem]) -> some View {
        let inspected = activeInspectedItem

        return HStack(spacing: 14) {
            plasmaBubbleArena(visible: visible, inspected: inspected)
            plasmaInspectorDock(visible: visible, inspected: inspected)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 4)
    }

    private func plasmaBubbleArena(visible: [ActivePortItem], inspected: ActivePortItem?) -> some View {
        GeometryReader { geo in
            ZStack {
                PlasmaRadarBackdropCanvas(accentColor: palette.accent)

                PortPlasmaBubbleMapCanvas(
                    items: visible,
                    selectedPortID: inspected?.id,
                    poppingPortIDs: poppingPortIDs,
                    palette: palette,
                    canvasSize: geo.size,
                    onSelect: { item in
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            selectedPortID = item.id
                        }
                    },
                    onQuickKill: { item in
                        triggerBubblePopAndKill(item, force: false)
                    },
                    onTapOverflow: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewMode = .compactList
                        }
                    }
                )

                bubbleLegendOverlay
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var bubbleLegendOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                legendDot(color: Color(hex: "00F5D4"), label: "Dev Server")
                legendDot(color: Color(hex: "FFB703"), label: "Database")
                legendDot(color: Color(hex: "C77DFF"), label: "AI & SDK")
                legendDot(color: Color(hex: "38BDF8"), label: "App / IDE")
                HStack(spacing: 4) {
                    Circle()
                        .strokeBorder(Color(hex: "FFB703"), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: 8, height: 8)
                    Text("LAN 0.0.0.0")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Text("Bubble size = Server priority & RAM/CPU load")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.32)))
            .padding(12)
        }
    }

    private func plasmaInspectorDock(visible: [ActivePortItem], inspected: ActivePortItem?) -> some View {
        VStack(spacing: 10) {
            if let item = inspected {
                PortBubbleInspectorCard(
                    item: item,
                    palette: palette,
                    onGracefulStop: {
                        triggerBubblePopAndKill(item, force: false)
                    },
                    onForceKill: {
                        confirmForceKillItem = item
                    },
                    onCopy: { text, label in
                        copyToClipboard(text, label: label)
                    }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ACTIVE PORTS (\(visible.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.48))
                    Spacer()
                    Text("Click to inspect")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visible) { item in
                            quickJumpPortRow(item: item, isCurrent: inspected?.id == item.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .frame(width: 315)
    }

    private func quickJumpPortRow(item: ActivePortItem, isCurrent: Bool) -> some View {
        let itemTint = Color(hex: item.category.accentHex)
        let dotColor = item.isExposedToLAN ? Color(hex: "FFB703") : itemTint

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(":\(String(item.port))")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 54, alignment: .leading)

            Text(item.displayTitle)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)

            Spacer(minLength: 4)

            if item.memoryBytes > 0 {
                Text(ByteFormat.string(item.memoryBytes))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.48))
            }

            if !item.isSystemProtected {
                Button {
                    triggerBubblePopAndKill(item, force: false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "FF7B72").opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Stop :\(String(item.port))")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? itemTint.opacity(0.22) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isCurrent ? itemTint.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                selectedPortID = item.id
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: 2)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - 3B. Compact List View

    private func compactListView(visible: [ActivePortItem]) -> some View {
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
                            triggerBubblePopAndKill(item, force: false)
                        },
                        onForceKill: {
                            confirmForceKillItem = item
                        },
                        onCopy: { text, label in
                            copyToClipboard(text, label: label)
                        }
                    )
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State & Footer

    private func emptyStateView(snap: PortKillerSnapshot) -> some View {
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
    }

    private func footerSection(snap: PortKillerSnapshot) -> some View {
        HStack(spacing: 12) {
            Button {
                autoRefreshEnabled.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(autoRefreshEnabled ? Color(hex: "2ED573") : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(autoRefreshEnabled ? "Live plasma radar active (every 4s)" : "Live updates paused")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .buttonStyle(.plain)

            Text("•")
                .foregroundStyle(.white.opacity(0.25))

            Text(viewMode == .plasmaBubbles
                 ? "Click any bubble to inspect • Hover bubble to quick-pop port"
                 : "Click any row to view full command & options")
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
        .padding(.vertical, 10)
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
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
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

// MARK: - Subtle Sonar Radar Backdrop Canvas

private struct PlasmaRadarBackdropCanvas: View {
    let accentColor: Color

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = hypot(size.width, size.height) * 0.46

            // Ambient center glow
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - maxR * 0.7, y: center.y - maxR * 0.7, width: maxR * 1.4, height: maxR * 1.4)),
                with: .radialGradient(
                    Gradient(colors: [accentColor.opacity(0.09), .clear]),
                    center: center,
                    startRadius: 5,
                    endRadius: maxR * 0.7
                )
            )

            // Concentric radar rings
            for factor in [0.24, 0.48, 0.72, 0.96] {
                let r = maxR * factor
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                ctx.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(0.045)),
                    style: StrokeStyle(lineWidth: 1, dash: factor == 0.72 ? [5, 5] : [])
                )
            }

            // Subtle crosshairs
            var hLine = Path()
            hLine.move(to: CGPoint(x: 24, y: center.y))
            hLine.addLine(to: CGPoint(x: size.width - 24, y: center.y))
            ctx.stroke(hLine, with: .color(Color.white.opacity(0.03)), lineWidth: 1)

            var vLine = Path()
            vLine.move(to: CGPoint(x: center.x, y: 24))
            vLine.addLine(to: CGPoint(x: center.x, y: size.height - 24))
            ctx.stroke(vLine, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Gravity Plasma Bubble Map Canvas

private enum PortBubbleEntry: Identifiable {
    case port(ActivePortItem)
    case overflow(count: Int, totalMemory: Int64)

    var id: String {
        switch self {
        case .port(let item): return item.id
        case .overflow: return "port-overflow-bubble"
        }
    }

    /// Smart visual weight so Dev Servers, Databases, and high-RAM/CPU processes get proportional, legible bubbles
    var visualWeight: Int64 {
        switch self {
        case .port(let item):
            let baseCategoryWeight: Double
            switch item.category {
            case .devWebServer: baseCategoryWeight = 160.0
            case .databaseCache: baseCategoryWeight = 135.0
            case .aiAndMobile: baseCategoryWeight = 115.0
            case .ideAndTools: baseCategoryWeight = 90.0
            case .macOSSystem: baseCategoryWeight = 65.0
            }
            let mb = max(1.0, Double(item.memoryBytes) / 1_048_576.0)
            let ramBoost = sqrt(min(2000.0, mb)) * 8.5
            let cpuBoost = min(100.0, item.cpuPercent) * 2.2
            let lanBoost = item.isExposedToLAN ? 28.0 : 0.0
            let totalScore = baseCategoryWeight + ramBoost + cpuBoost + lanBoost
            return Int64(totalScore * totalScore)
        case .overflow(let count, _):
            let score = 95.0 + Double(min(20, count)) * 3.0
            return Int64(score * score)
        }
    }
}

private struct PortPlasmaBubbleMapCanvas: View {
    let items: [ActivePortItem]
    let selectedPortID: String?
    let poppingPortIDs: Set<String>
    let palette: ModulePalette
    let canvasSize: CGSize
    let onSelect: (ActivePortItem) -> Void
    let onQuickKill: (ActivePortItem) -> Void
    let onTapOverflow: () -> Void

    private var entries: [PortBubbleEntry] {
        let maxBubbles = 14
        if items.count > maxBubbles + 1 {
            let head = items.prefix(maxBubbles).map { PortBubbleEntry.port($0) }
            let tail = items.dropFirst(maxBubbles)
            let tailMem = tail.reduce(Int64(0)) { $0 + $1.memoryBytes }
            return head + [.overflow(count: tail.count, totalMemory: tailMem)]
        }
        return items.map { PortBubbleEntry.port($0) }
    }

    var body: some View {
        let currentEntries = entries
        let usableSize = CGSize(width: max(80, canvasSize.width), height: max(80, canvasSize.height - 28))
        let packed = SpaceLensBubblePacker.pack(
            sizes: currentEntries.map(\.visualWeight),
            in: usableSize,
            padding: 24
        )

        ZStack {
            ForEach(packed, id: \.index) { layout in
                let entry = currentEntries[layout.index]
                PortPlasmaOrbView(
                    entry: entry,
                    radius: layout.radius,
                    isSelected: entry.id == selectedPortID,
                    isPopping: poppingPortIDs.contains(entry.id),
                    palette: palette,
                    onTap: {
                        switch entry {
                        case .port(let item):
                            onSelect(item)
                        case .overflow:
                            onTapOverflow()
                        }
                    },
                    onQuickKill: {
                        if case .port(let item) = entry {
                            onQuickKill(item)
                        }
                    }
                )
                .position(x: layout.center.x, y: layout.center.y - 8)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: layout.center)
            }
        }
        .clipped()
    }
}

// MARK: - Individual Translucent Plasma Port Bubble

private struct PortPlasmaOrbView: View {
    let entry: PortBubbleEntry
    let radius: CGFloat
    let isSelected: Bool
    let isPopping: Bool
    let palette: ModulePalette
    let onTap: () -> Void
    let onQuickKill: () -> Void
    @State private var isHovered = false

    private var tint: Color {
        switch entry {
        case .port(let item):
            return Color(hex: item.category.accentHex)
        case .overflow:
            return palette.accent
        }
    }

    private var isLANExposed: Bool {
        if case .port(let item) = entry { return item.isExposedToLAN }
        return false
    }

    private var isHighCPU: Bool {
        if case .port(let item) = entry { return item.cpuPercent >= 5.0 }
        return false
    }

    var body: some View {
        let diameter = radius * 2

        ZStack {
            // Outer LAN or High-CPU Warning Halo Ring
            if isLANExposed || isHighCPU {
                Circle()
                    .strokeBorder(
                        isHighCPU ? Color(hex: "FF9F43").opacity(0.75) : Color(hex: "FFB703").opacity(0.65),
                        style: StrokeStyle(lineWidth: isSelected || isHovered ? 2.2 : 1.5, dash: isLANExposed ? [5, 3] : [])
                    )
                    .frame(width: diameter + 10, height: diameter + 10)
            }

            // Pop Shockwave Ring when killing port
            if isPopping {
                Circle()
                    .stroke(Color(hex: "FF5E57"), lineWidth: 3)
                    .frame(width: diameter * 1.35, height: diameter * 1.35)
                    .opacity(0.0)
            }

            // Main Translucent Glass Plasma Sphere
            orbSphereBackground(diameter: diameter)

            // Inner Typography & Port Info
            orbContent

            // Floating Quick-Action Pill on Hover (Open / Pop-Kill)
            if isHovered, case .port(let item) = entry, radius >= 38 {
                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        if let webURL = item.localWebURL {
                            Button {
                                NSWorkspace.shared.open(webURL)
                            } label: {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Color(hex: "00F5D4"))
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.black.opacity(0.72)))
                                    .overlay(Circle().strokeBorder(Color(hex: "00F5D4").opacity(0.6), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Open http://localhost:\(String(item.port))")
                        }

                        if !item.isSystemProtected {
                            Button(action: onQuickKill) {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.slash.fill")
                                        .font(.system(size: 8.5, weight: .bold))
                                    if radius >= 54 {
                                        Text("Kill")
                                            .font(.system(size: 9.5, weight: .bold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, radius >= 54 ? 8 : 6)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(hex: "FF5E57")))
                                .shadow(color: Color(hex: "FF5E57").opacity(0.6), radius: 5)
                            }
                            .buttonStyle(.plain)
                            .help("Pop & stop port :\(String(item.port))")
                        }
                    }
                    .offset(y: 6)
                }
                .frame(width: diameter, height: diameter)
            }
        }
        .frame(width: diameter + 12, height: diameter + 12)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .scaleEffect(isPopping ? 0.02 : (isHovered ? 1.07 : (isSelected ? 1.03 : 1.0)))
        .opacity(isPopping ? 0.0 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHovered)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
        .animation(.easeIn(duration: 0.24), value: isPopping)
        .onHover { isHovered = $0 }
    }

    private func orbSphereBackground(diameter: CGFloat) -> some View {
        let rimColor = isSelected ? Color.white : tint
        return Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: Color.black.opacity(isHovered ? 0.22 : 0.34), location: 0.0),
                        .init(color: tint.opacity(isHovered ? 0.28 : 0.18), location: 0.55),
                        .init(color: tint.opacity(isHovered ? 0.56 : 0.40), location: 0.88),
                        .init(color: rimColor.opacity(isHovered ? 0.82 : 0.64), location: 1.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .overlay(
                // Top-left glass specular highlight
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.28 : 0.18),
                                Color.clear,
                                tint.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.98 : (isHovered ? 0.80 : 0.48)),
                                tint.opacity(isHovered ? 0.75 : 0.42),
                                Color.white.opacity(isSelected ? 0.90 : 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 2.6 : (isHovered ? 1.9 : 1.2)
                    )
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: tint.opacity(isSelected ? 0.52 : (isHovered ? 0.42 : 0.20)), radius: isSelected ? 18 : (isHovered ? 14 : 8))
    }

    @ViewBuilder
    private var orbContent: some View {
        switch entry {
        case .port(let item):
            VStack(spacing: radius >= 58 ? 3 : 1) {
                if radius >= 48 {
                    HStack(spacing: 4) {
                        Image(systemName: item.category.iconName)
                            .font(.system(size: min(12, max(8.5, radius * 0.16)), weight: .bold))
                            .foregroundStyle(tint)
                        if item.isExposedToLAN && radius >= 56 {
                            Text("LAN")
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundStyle(Color(hex: "FFB703"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color(hex: "FFB703").opacity(0.22)))
                        }
                    }
                }

                // Giant Monospace Port Label (:5173)
                Text(":\(String(item.port))")
                    .font(.system(size: min(22, max(10.5, radius * 0.32)), weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.45), radius: 3, y: 1)
                    .lineLimit(1)

                // Project / Process Name
                if radius >= 34 {
                    Text(item.displayTitle)
                        .font(.system(size: min(13, max(9.0, radius * 0.17)), weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: radius * 1.62)
                }

                // Framework & RAM / CPU Pill on larger bubbles
                if radius >= 56 {
                    Text(item.cpuPercent >= 5.0
                         ? String(format: "%@ • %.0f%% CPU", item.frameworkLabel, item.cpuPercent)
                         : (item.memoryBytes > 0 ? "\(item.frameworkLabel) • \(ByteFormat.string(item.memoryBytes))" : item.frameworkLabel))
                        .font(.system(size: min(10.5, max(8.5, radius * 0.135)), weight: .semibold).monospacedDigit())
                        .foregroundStyle(item.cpuPercent >= 5.0 ? Color(hex: "FF9F43") : .white.opacity(0.76))
                        .lineLimit(1)
                        .frame(maxWidth: radius * 1.55)
                }
            }
            .padding(.horizontal, 6)

        case .overflow(let count, let totalMemory):
            VStack(spacing: 3) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: min(18, max(12, radius * 0.28))))
                    .foregroundStyle(palette.accent)
                Text("+\(count) Ports")
                    .font(.system(size: min(14, max(10, radius * 0.22)), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if radius >= 46 && totalMemory > 0 {
                    Text(ByteFormat.string(totalMemory))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
    }
}

// MARK: - Right-Side Live Port HUD Inspector Card

private struct PortBubbleInspectorCard: View {
    let item: ActivePortItem
    let palette: ModulePalette
    let onGracefulStop: () -> Void
    let onForceKill: () -> Void
    let onCopy: (String, String) -> Void

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

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Top Port Header
            HStack(spacing: 10) {
                Text(":\(String(item.port))")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.20))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(tint.opacity(0.50), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(item.frameworkLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tint)
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(item.isExposedToLAN ? "LAN (\(item.bindAddress))" : "Localhost")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(item.isExposedToLAN ? Color(hex: "FFB703") : Color(hex: "00F5D4"))
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            // 4 Mini Telemetry Pills (PID, RAM, CPU, Uptime)
            HStack(spacing: 6) {
                metricBox(title: "PID", value: String(item.pid))
                metricBox(title: "RAM", value: item.memoryBytes > 0 ? ByteFormat.string(item.memoryBytes) : "—")
                metricBox(
                    title: "CPU",
                    value: String(format: "%.1f%%", item.cpuPercent),
                    highlight: item.cpuPercent >= 5.0 ? Color(hex: "FF9F43") : nil
                )
                metricBox(title: "UPTIME", value: item.uptimeLabel)
            }

            // Project Directory or Command
            if let cwd = abbreviatedCwd, let rawCwd = item.workingDirectory {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("PROJECT FOLDER")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Button("Reveal") {
                            FileSystemHelpers.revealInFinder(path: rawCwd)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: "00F5D4"))
                        .buttonStyle(.plain)

                        Button("Copy") {
                            onCopy(rawCwd, "Project Path")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .buttonStyle(.plain)
                    }
                    Text(cwd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.22)))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("CLI COMMAND")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button("Copy") {
                        onCopy(item.commandLine, "Command")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .buttonStyle(.plain)
                }
                Text(item.commandLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.22)))

            // Action Buttons
            HStack(spacing: 7) {
                if let webURL = item.localWebURL {
                    Button {
                        NSWorkspace.shared.open(webURL)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "00F5D4"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(hex: "00F5D4").opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Color(hex: "00F5D4").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if !item.isSystemProtected {
                    Button(action: onGracefulStop) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9.5))
                            Text("Stop Port")
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.85)))
                    }
                    .buttonStyle(.plain)

                    Button(action: onForceKill) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "FF7B72"))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(hex: "FF5E57").opacity(0.16)))
                            .overlay(Circle().strokeBorder(Color(hex: "FF5E57").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Force Kill (SIGKILL -9)")
                } else {
                    Text("macOS System Protected Service")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
    }

    private func metricBox(title: String, value: String, highlight: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(highlight ?? .white.opacity(0.90))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.20)))
    }
}

// MARK: - Clean 2-Line Port & Server Card (For List Mode)

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
