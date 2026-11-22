import SwiftUI
import AppKit

public struct CryoFreezerView: View {
    @EnvironmentObject var appState: AppState
    @State private var viewMode: ViewMode = .thermalMatrix
    @State private var selectedFilter: FilterTab = .all
    @State private var searchText: String = ""
    @State private var selectedPID: Int32? = nil
    @State private var autoRefreshEnabled: Bool = true
    @State private var confirmForceQuitItem: CryoProcessItem? = nil
    private let palette = RCleanerTheme.palette(for: .cryoFreezer)
    private let refreshTimer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    private enum ViewMode: String, CaseIterable, Identifiable {
        case thermalMatrix = "Cells"
        case compactList = "List"
        var id: String { rawValue }
    }

    private enum FilterTab: String, CaseIterable, Identifiable {
        case all = "All Processes"
        case frozen = "Cryo-Frozen"
        case hotAndWarm = "Hot & Heavy"
        case memoryGrowth = "RAM Growth"
        case guiApps = "Apps Only"
        var id: String { rawValue }
    }

    public init() {}

    private var filteredItems: [CryoProcessItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.cryoSnapshot.items.filter { item in
            switch selectedFilter {
            case .all:
                break
            case .frozen:
                if !item.isFrozen { return false }
            case .hotAndWarm:
                if item.thermalState != .overheating && item.thermalState != .warm { return false }
            case .memoryGrowth:
                if !item.isMemoryGrowing { return false }
            case .guiApps:
                if !item.isGUIApp { return false }
            }

            if !query.isEmpty {
                let hay = "\(item.displayTitle) \(item.name) \(item.pid) \(item.executablePath)".lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }
    }

    private var activeInspectedItem: CryoProcessItem? {
        let visible = filteredItems
        if let pid = selectedPID, let found = visible.first(where: { $0.pid == pid }) {
            return found
        }
        return visible.first
    }

    public var body: some View {
        let snap = appState.cryoSnapshot
        let visible = filteredItems

        VStack(spacing: 0) {
            headerSection(snap: snap)
            toolbarSection(snap: snap)

            if visible.isEmpty {
                emptyStateView(snap: snap)
            } else if viewMode == .thermalMatrix {
                thermalMatrixWorkspace(visible: visible)
            } else {
                compactListView(visible: visible)
            }

            footerSection(snap: snap)
        }
        .onAppear {
            appState.refreshCryoProcesses()
        }
        .onReceive(refreshTimer) { _ in
            guard autoRefreshEnabled, appState.selectedModule == .cryoFreezer else { return }
            appState.refreshCryoProcesses(silent: true)
        }
        .alert(
            "Force Quit \(confirmForceQuitItem?.displayTitle ?? "") (PID \(confirmForceQuitItem.map { String($0.pid) } ?? ""))?",
            isPresented: Binding(
                get: { confirmForceQuitItem != nil },
                set: { if !$0 { confirmForceQuitItem = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { confirmForceQuitItem = nil }
            Button("Force Quit (SIGKILL -9)", role: .destructive) {
                if let item = confirmForceQuitItem {
                    appState.terminateCryoProcess(item, force: true)
                }
                confirmForceQuitItem = nil
            }
        } message: {
            if let item = confirmForceQuitItem {
                Text("Immediately terminates \(item.displayTitle) (PID \(String(item.pid))). Unsaved data in that app may be lost.")
            }
        }
    }

    // MARK: - 1. Clean Header + Single-Line Summary Badges

    private func headerSection(snap: CryoFreezerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Cryo-Freezer & Pulse")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if appState.isScanningCryo {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)
                }

                Spacer(minLength: 360)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    summaryBadge(
                        icon: "snowflake",
                        iconSize: 11,
                        label: "\(snap.frozenCount) Frozen (0% CPU)",
                        tint: Color(hex: "38BDF8"),
                        isActive: selectedFilter == .frozen
                    ) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            selectedFilter = (selectedFilter == .frozen) ? .all : .frozen
                        }
                    }

                    summaryBadge(
                        icon: "flame.fill",
                        iconSize: 11,
                        label: "\(snap.hotCount) Hot / Heavy",
                        tint: Color(hex: "FF5E57"),
                        isActive: selectedFilter == .hotAndWarm
                    ) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            selectedFilter = (selectedFilter == .hotAndWarm) ? .all : .hotAndWarm
                        }
                    }

                    summaryBadge(
                        icon: "chart.line.uptrend.xyaxis",
                        iconSize: 11,
                        label: "\(snap.memoryGrowingCount) RAM Growth",
                        tint: Color(hex: "FFB703"),
                        isActive: selectedFilter == .memoryGrowth
                    ) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            selectedFilter = (selectedFilter == .memoryGrowth) ? .all : .memoryGrowth
                        }
                    }

                    summaryBadge(
                        icon: "memorychip",
                        iconSize: 11,
                        label: "\(ByteFormat.string(snap.totalMemoryBytes)) Tracked",
                        tint: Color(hex: "00F5D4"),
                        isActive: selectedFilter == .all
                    ) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            selectedFilter = .all
                        }
                    }

                    if snap.frozenCount > 0 {
                        Button {
                            appState.unfreezeAllCryoProcesses()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Unfreeze All (\(snap.frozenCount))")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: "38BDF8")))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - 2. Filter, Search & View Mode Switcher Toolbar

    private func toolbarSection(snap: CryoFreezerSnapshot) -> some View {
        HStack(spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FilterTab.allCases) { tab in
                        let count = tabCount(for: tab, snap: snap)
                        let isSelected = selectedFilter == tab
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                selectedFilter = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(tab.rawValue)
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
                                Capsule().fill(isSelected ? palette.primary.opacity(0.68) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                Capsule().strokeBorder(isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            // Search Field
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                TextField("Search app or PID...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 155)

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

            // Cells vs List Switcher
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    let isSelected = viewMode == mode
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode == .thermalMatrix ? "square.grid.3x2.fill" : "list.bullet")
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
                appState.refreshCryoProcesses()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Refresh live process pulse")
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 10)
    }

    private func tabCount(for tab: FilterTab, snap: CryoFreezerSnapshot) -> Int {
        switch tab {
        case .all: return snap.items.count
        case .frozen: return snap.frozenCount
        case .hotAndWarm: return snap.hotCount
        case .memoryGrowth: return snap.memoryGrowingCount
        case .guiApps: return snap.items.filter(\.isGUIApp).count
        }
    }

    // MARK: - 3A. Thermal & Cryo Cell Matrix + Right HUD Inspector Dock

    private func thermalMatrixWorkspace(visible: [CryoProcessItem]) -> some View {
        let inspected = activeInspectedItem

        return HStack(spacing: 14) {
            thermalCellsGridArena(visible: visible, inspected: inspected)
            cryoInspectorDock(inspected: inspected)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 4)
    }

    private func thermalCellsGridArena(visible: [CryoProcessItem], inspected: CryoProcessItem?) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 12)
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visible) { item in
                    CryoThermalCellCard(
                        item: item,
                        isSelected: inspected?.pid == item.pid,
                        onSelect: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                selectedPID = item.pid
                            }
                        },
                        onToggleFreeze: {
                            appState.toggleCryoFreeze(item)
                        }
                    )
                }
            }
            .padding(16)
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

    private func cryoInspectorDock(inspected: CryoProcessItem?) -> some View {
        VStack(spacing: 10) {
            if let item = inspected {
                CryoProcessInspectorCard(
                    item: item,
                    palette: palette,
                    onToggleFreeze: {
                        appState.toggleCryoFreeze(item)
                    },
                    onGracefulQuit: {
                        appState.terminateCryoProcess(item, force: false)
                    },
                    onForceQuit: {
                        confirmForceQuitItem = item
                    }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(width: 315)
    }

    // MARK: - 3B. Compact List View

    private func compactListView(visible: [CryoProcessItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(visible) { item in
                    CryoCompactRowCard(
                        item: item,
                        isSelected: activeInspectedItem?.pid == item.pid,
                        onSelect: {
                            selectedPID = item.pid
                        },
                        onToggleFreeze: {
                            appState.toggleCryoFreeze(item)
                        },
                        onQuit: {
                            appState.terminateCryoProcess(item, force: false)
                        }
                    )
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State & Footer

    private func emptyStateView(snap: CryoFreezerSnapshot) -> some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .frozen ? "snowflake" : "waveform.path.ecg")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(palette.accent.opacity(0.8))
            Text(selectedFilter == .frozen ? "No Apps Currently Cryo-Frozen" : "No Matching Processes")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(selectedFilter == .frozen
                 ? "Click Freeze on any heavy app cell to pause its CPU usage to 0% without closing it."
                 : "Try switching filter tabs or clearing your search query.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.55))
            if selectedFilter != .all || !searchText.isEmpty {
                Button("Show All Processes") {
                    selectedFilter = .all
                    searchText = ""
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

    private func footerSection(snap: CryoFreezerSnapshot) -> some View {
        HStack(spacing: 12) {
            Button {
                autoRefreshEnabled.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(autoRefreshEnabled ? Color(hex: "2ED573") : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(autoRefreshEnabled ? "Live thermal & RAM pulse active (3.5s)" : "Live pulse paused")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .buttonStyle(.plain)

            Text("•")
                .foregroundStyle(.white.opacity(0.25))

            Text("Cryo-Freeze (SIGSTOP) pauses an app at 0% CPU without closing windows • Auto-unfreezes on exit")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)

            Spacer()

            if snap.frozenCount > 0 {
                Button {
                    appState.unfreezeAllCryoProcesses()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Unfreeze All (\(snap.frozenCount))")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "38BDF8"))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: "38BDF8").opacity(0.15)))
                    .overlay(Capsule().strokeBorder(Color(hex: "38BDF8").opacity(0.38), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
    }

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
}

// MARK: - Interactive Thermal / Ice Crystal Cell Card

private struct CryoThermalCellCard: View {
    let item: CryoProcessItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFreeze: () -> Void
    @State private var isHovered = false

    private var tint: Color {
        Color(hex: item.thermalState.accentHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            titleAndMetricsRow
            sparklineAndActionRow
        }
        .padding(13)
        .background(cellBackground)
        .overlay(cellBorder)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: tint.opacity(isSelected ? 0.35 : (isHovered ? 0.24 : 0.08)), radius: isSelected ? 12 : 7)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                NativeFileIconView(path: item.iconFilePath, isDirectory: false, size: 32)
                    .opacity(item.isFrozen ? 0.78 : 1.0)

                if item.isFrozen {
                    Image(systemName: "snowflake.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "38BDF8"))
                        .background(Circle().fill(Color.black))
                        .offset(x: 3, y: 3)
                }
            }

            Spacer(minLength: 4)

            // Thermal / Cryo Badge
            HStack(spacing: 3.5) {
                Image(systemName: item.thermalState.iconName)
                    .font(.system(size: 9, weight: .bold))
                Text(item.isFrozen ? "FROZEN" : String(format: "%.1f%%", item.cpuPercent))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(item.isFrozen ? Color(hex: "A5F3FC") : tint)
            .padding(.horizontal, 7.5)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(item.isFrozen ? 0.24 : 0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.42), lineWidth: 1))
        }
    }

    private var titleAndMetricsRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.displayTitle)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(ByteFormat.string(item.memoryBytes))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))

                if item.isMemoryGrowing {
                    Text("+\(ByteFormat.string(item.memoryDeltaBytes))")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "FFB703"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: "FFB703").opacity(0.16)))
                } else {
                    Text("PID \(String(item.pid))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .lineLimit(1)
        }
    }

    private var sparklineAndActionRow: some View {
        HStack(spacing: 8) {
            // Mini Memory Pulse Sparkline
            CryoMiniSparklineView(samples: item.memoryHistory, tint: tint)
                .frame(height: 18)

            if item.isSystemProtected {
                Text("macOS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            } else {
                Button(action: onToggleFreeze) {
                    HStack(spacing: 3.5) {
                        Image(systemName: item.isFrozen ? "sun.max.fill" : "snowflake")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(item.isFrozen ? "Thaw" : "Freeze")
                            .font(.system(size: 10.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(item.isFrozen ? .black : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            item.isFrozen
                                ? Color(hex: "38BDF8")
                                : Color(hex: "38BDF8").opacity(isHovered ? 0.35 : 0.20)
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(Color(hex: "38BDF8").opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(item.isFrozen ? "Unfreeze & resume \(item.displayTitle)" : "Cryo-freeze \(item.displayTitle) to 0% CPU")
            }
        }
    }

    private var cellBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(item.isFrozen ? 0.24 : (isSelected ? 0.20 : 0.10)),
                            Color.black.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if item.isFrozen {
                // Crystalline Frost Sheen
                Image(systemName: "snowflake")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(Color(hex: "A5F3FC").opacity(0.10))
                    .offset(x: 48, y: -12)
            }
        }
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        item.isFrozen
                            ? Color(hex: "A5F3FC").opacity(0.85)
                            : (isSelected ? tint.opacity(0.85) : Color.white.opacity(isHovered ? 0.28 : 0.12)),
                        tint.opacity(isSelected || item.isFrozen ? 0.45 : 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected || item.isFrozen ? 1.8 : 1.0
            )
    }
}

// MARK: - Live Memory Pulse Sparkline Canvas

private struct CryoMiniSparklineView: View {
    let samples: [Int64]
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else {
                var mid = Path()
                mid.move(to: CGPoint(x: 0, y: size.height * 0.6))
                mid.addLine(to: CGPoint(x: size.width, y: size.height * 0.6))
                ctx.stroke(mid, with: .color(tint.opacity(0.35)), lineWidth: 1.5)
                return
            }

            let minVal = Double(samples.min() ?? 0) * 0.96
            let maxVal = max(minVal + 1024, Double(samples.max() ?? 1) * 1.02)
            let span = max(1.0, maxVal - minVal)
            let stepX = size.width / CGFloat(samples.count - 1)

            var path = Path()
            for (i, sample) in samples.enumerated() {
                let norm = (Double(sample) - minVal) / span
                let x = CGFloat(i) * stepX
                let y = size.height - CGFloat(max(0.1, min(0.92, norm))) * size.height
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            ctx.stroke(path, with: .color(tint.opacity(0.82)), lineWidth: 1.6)
        }
    }
}

// MARK: - Right-Side Live Cryo HUD Inspector Card

private struct CryoProcessInspectorCard: View {
    let item: CryoProcessItem
    let palette: ModulePalette
    let onToggleFreeze: () -> Void
    let onGracefulQuit: () -> Void
    let onForceQuit: () -> Void

    private var tint: Color {
        Color(hex: item.thermalState.accentHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // App Icon & Header
            HStack(spacing: 11) {
                NativeFileIconView(path: item.iconFilePath, isDirectory: false, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: item.thermalState.iconName)
                            .font(.system(size: 9.5, weight: .bold))
                        Text(item.thermalState.badgeLabel)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(tint)
                }

                Spacer(minLength: 0)
            }

            // 4 Telemetry Tiles
            HStack(spacing: 6) {
                metricBox(
                    title: "CPU",
                    value: item.isFrozen ? "0.0%" : String(format: "%.1f%%", item.cpuPercent),
                    highlight: item.isFrozen ? Color(hex: "38BDF8") : (item.cpuPercent >= 20 ? Color(hex: "FF5E57") : nil)
                )
                metricBox(title: "RAM", value: ByteFormat.string(item.memoryBytes))
                metricBox(
                    title: "TREND",
                    value: item.memoryDeltaBytes > 0 ? "+\(ByteFormat.string(item.memoryDeltaBytes))" : "Stable",
                    highlight: item.isMemoryGrowing ? Color(hex: "FFB703") : Color(hex: "2ED573")
                )
                metricBox(title: "PID", value: String(item.pid))
            }

            // Memory Growth Sparkline Box
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LIVE MEMORY FOOTPRINT TREND")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(item.isMemoryGrowing ? "Growing (Watch for Leak)" : "Stable Footprint")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.isMemoryGrowing ? Color(hex: "FFB703") : Color(hex: "00F5D4"))
                }
                CryoMiniSparklineView(samples: item.memoryHistory, tint: tint)
                    .frame(height: 36)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.24)))

            // Executable Path Box
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("EXECUTABLE PATH")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button("Reveal in Finder") {
                        FileSystemHelpers.revealInFinder(path: item.iconFilePath)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "00F5D4"))
                    .buttonStyle(.plain)
                }
                Text(item.executablePath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.24)))

            // Primary Cryo-Freeze / Unfreeze Action
            if item.isSystemProtected {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Protected macOS System Service")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                Button(action: onToggleFreeze) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isFrozen ? "sun.max.fill" : "snowflake")
                            .font(.system(size: 12, weight: .bold))
                        Text(item.isFrozen ? "Unfreeze & Resume App" : "Cryo-Freeze App (0% CPU)")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    .foregroundStyle(item.isFrozen ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(
                            item.isFrozen
                                ? Color(hex: "38BDF8")
                                : Color(hex: "38BDF8").opacity(0.82)
                        )
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Button(action: onGracefulQuit) {
                        Text("Quit App")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)

                    Button(action: onForceQuit) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.slash.fill")
                                .font(.system(size: 10))
                            Text("Force Quit")
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "FF7B72"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Color(hex: "FF5E57").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.38), lineWidth: 1)
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.22)))
    }
}

// MARK: - Compact List Row Card (For List Mode)

private struct CryoCompactRowCard: View {
    let item: CryoProcessItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFreeze: () -> Void
    let onQuit: () -> Void

    private var tint: Color {
        Color(hex: item.thermalState.accentHex)
    }

    var body: some View {
        HStack(spacing: 12) {
            NativeFileIconView(path: item.iconFilePath, isDirectory: false, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(item.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(item.thermalState.badgeLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(tint.opacity(0.15)))
                }

                Text("PID \(String(item.pid))  •  RAM \(ByteFormat.string(item.memoryBytes))  •  Up \(item.uptimeLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            CryoMiniSparklineView(samples: item.memoryHistory, tint: tint)
                .frame(width: 72, height: 18)

            Text(item.isFrozen ? "0.0% CPU" : String(format: "%.1f%% CPU", item.cpuPercent))
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: 82, alignment: .trailing)

            if !item.isSystemProtected {
                Button(action: onToggleFreeze) {
                    HStack(spacing: 4) {
                        Image(systemName: item.isFrozen ? "sun.max.fill" : "snowflake")
                            .font(.system(size: 10, weight: .bold))
                        Text(item.isFrozen ? "Unfreeze" : "Freeze")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(item.isFrozen ? .black : .white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: "38BDF8").opacity(item.isFrozen ? 1.0 : 0.25)))
                    .overlay(Capsule().strokeBorder(Color(hex: "38BDF8").opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "FF7B72"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tint.opacity(0.16) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
