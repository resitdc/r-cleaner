import SwiftUI
import AppKit

public struct CryoFreezerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFilter: FilterTab = .all
    @State private var searchText: String = ""
    @State private var selectedPID: Int32? = nil
    @State private var autoRefreshEnabled: Bool = true
    @State private var confirmForceQuitItem: CryoProcessItem? = nil
    private let palette = RCleanerTheme.palette(for: .cryoFreezer)
    private let refreshTimer = Timer.publish(every: 6.0, tolerance: 1.5, on: .main, in: .common).autoconnect()

    private enum FilterTab: String, CaseIterable, Identifiable {
        case all = "All"
        case hotAndWarm = "Hot & Heavy"
        case frozen = "Frozen"
        case memoryGrowth = "RAM Growth"
        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .hotAndWarm: return "flame.fill"
            case .frozen: return "snowflake"
            case .memoryGrowth: return "chart.line.uptrend.xyaxis"
            }
        }

        var tintHex: String {
            switch self {
            case .all: return "00F5D4"
            case .hotAndWarm: return "FF5E57"
            case .frozen: return "38BDF8"
            case .memoryGrowth: return "FFB703"
            }
        }
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
            }

            if !query.isEmpty {
                let hay = "\(item.displayTitle) \(item.name) \(item.pid)".lowercased()
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
            headerAndToolbarSection(snap: snap)

            if visible.isEmpty {
                emptyStateView(snap: snap)
            } else {
                thermalMatrixWorkspace(visible: visible)
            }

            footerSection(snap: snap)
        }
        .onAppear {
            appState.refreshCryoProcesses()
        }
        .onReceive(refreshTimer) { _ in
            guard autoRefreshEnabled,
                  appState.selectedModule == .cryoFreezer,
                  NSApp.isActive else { return }
            appState.refreshCryoProcesses(silent: true)
        }
        .alert(
            "Force Quit \(confirmForceQuitItem?.displayTitle ?? "")?",
            isPresented: Binding(
                get: { confirmForceQuitItem != nil },
                set: { if !$0 { confirmForceQuitItem = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { confirmForceQuitItem = nil }
            Button("Force Quit", role: .destructive) {
                if let item = confirmForceQuitItem {
                    appState.terminateCryoProcess(item, force: true)
                }
                confirmForceQuitItem = nil
            }
        } message: {
            if let item = confirmForceQuitItem {
                Text("Immediately terminates \(item.displayTitle) (PID \(String(item.pid))).")
            }
        }
    }

    // MARK: - 1. Clean Unified Header & Single Toolbar Row (No Duplicate Filter Rows!)

    private func headerAndToolbarSection(snap: CryoFreezerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Cryo-Freezer")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(ByteFormat.string(snap.totalMemoryBytes))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(palette.primary.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(palette.primary.opacity(0.35), lineWidth: 1))

                if appState.isScanningCryo {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)
                }

                Spacer(minLength: 360)
            }

            // Single Unified Filter & Search Row
            HStack(spacing: 8) {
                ForEach(FilterTab.allCases) { tab in
                    let count = tabCount(for: tab, snap: snap)
                    let isSelected = selectedFilter == tab
                    let tint = Color(hex: tab.tintHex)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedFilter = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : tint)

                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.78))
                                .lineLimit(1)

                            Text("\(count)")
                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                                )
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? tint.opacity(0.55) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule().strokeBorder(isSelected ? tint.opacity(0.85) : Color.white.opacity(0.09), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if snap.frozenCount > 0 {
                    Button {
                        appState.unfreezeAllCryoProcesses()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Thaw All (\(snap.frozenCount))")
                                .font(.system(size: 11.5, weight: .bold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: "38BDF8")))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 6)

                // Clean Search Box
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    TextField("Search app...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 145)

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
                .help("Refresh process pulse")
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func tabCount(for tab: FilterTab, snap: CryoFreezerSnapshot) -> Int {
        switch tab {
        case .all: return snap.items.count
        case .frozen: return snap.frozenCount
        case .hotAndWarm: return snap.hotCount
        case .memoryGrowth: return snap.memoryGrowingCount
        }
    }

    // MARK: - 2. Symmetrical Full-Width Matrix + Full-Height Inspector Dock

    private func thermalMatrixWorkspace(visible: [CryoProcessItem]) -> some View {
        let inspected = activeInspectedItem

        return HStack(alignment: .top, spacing: 14) {
            thermalCellsGridArena(visible: visible, inspected: inspected)
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
                .frame(width: 285)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.vertical, 4)
    }

    private func thermalCellsGridArena(visible: [CryoProcessItem], inspected: CryoProcessItem?) -> some View {
        // Exact 3-column symmetrical flexible grid filling 100% of the arena width
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
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
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    // MARK: - Empty State & Minimal Footer

    private func emptyStateView(snap: CryoFreezerSnapshot) -> some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .frozen ? "snowflake" : "waveform.path.ecg")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(palette.accent.opacity(0.8))
            Text(selectedFilter == .frozen ? "No Frozen Apps" : "No Matching Apps")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(selectedFilter == .frozen
                 ? "Click Freeze on any card to pause its CPU to 0%."
                 : "Try switching filter tabs or clearing your search.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.55))
            if selectedFilter != .all || !searchText.isEmpty {
                Button("Show All") {
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
        HStack(spacing: 10) {
            Button {
                autoRefreshEnabled.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(autoRefreshEnabled ? Color(hex: "2ED573") : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(autoRefreshEnabled ? "Live pulse active" : "Live pulse paused")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(snap.items.count) active processes")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 9)
    }
}

// MARK: - Clean, Symmetrical Thermal / Ice Crystal Cell Card

private struct CryoThermalCellCard: View {
    let item: CryoProcessItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFreeze: () -> Void
    @State private var isHovered = false

    private var tint: Color {
        Color(hex: item.thermalState.accentHex)
    }

    private var cleanTitle: String {
        let raw = item.displayTitle
        if raw == "qemu-system-aarch64" || raw == "qemu-system-x86_64" {
            return "Android Emulator"
        }
        return raw.replacingOccurrences(of: " Helper (Renderer)", with: " Helper")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            topIconAndBadgeRow
            titleAndMemoryRow
            bottomSparklineAndActionRow
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cellBackground)
        .overlay(cellBorder)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: tint.opacity(isSelected ? 0.30 : (isHovered ? 0.20 : 0.06)), radius: isSelected ? 10 : 6)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }

    private var topIconAndBadgeRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                NativeFileIconView(path: item.iconFilePath, isDirectory: false, size: 32)
                    .opacity(item.isFrozen ? 0.78 : 1.0)

                if item.isFrozen {
                    Image(systemName: "snowflake.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "38BDF8"))
                        .background(Circle().fill(Color.black))
                        .offset(x: 2, y: 2)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 3.5) {
                Image(systemName: item.thermalState.iconName)
                    .font(.system(size: 8.5, weight: .bold))
                Text(item.isFrozen ? "0% CPU" : String(format: "%.0f%%", item.cpuPercent))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(item.isFrozen ? Color(hex: "A5F3FC") : tint)
            .padding(.horizontal, 7.5)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(item.isFrozen ? 0.24 : 0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 1))
        }
    }

    private var titleAndMemoryRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cleanTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(ByteFormat.string(item.memoryBytes))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))

                if item.isMemoryGrowing {
                    Text("+\(ByteFormat.string(item.memoryDeltaBytes))")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "FFB703"))
                }
            }
            .lineLimit(1)
        }
    }

    private var bottomSparklineAndActionRow: some View {
        HStack(spacing: 8) {
            CryoMiniSparklineView(samples: item.memoryHistory, tint: tint)
                .frame(height: 16)

            if item.isSystemProtected {
                Text("System")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
            } else {
                Button(action: onToggleFreeze) {
                    HStack(spacing: 3.5) {
                        Image(systemName: item.isFrozen ? "sun.max.fill" : "snowflake")
                            .font(.system(size: 9, weight: .bold))
                        Text(item.isFrozen ? "Thaw" : "Freeze")
                            .font(.system(size: 10.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(item.isFrozen ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            item.isFrozen
                                ? Color(hex: "38BDF8")
                                : Color(hex: "38BDF8").opacity(isHovered ? 0.36 : 0.18)
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(Color(hex: "38BDF8").opacity(0.50), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(item.isFrozen ? 0.22 : (isSelected ? 0.18 : 0.08)),
                        Color.black.opacity(0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isSelected || item.isFrozen
                    ? tint.opacity(0.80)
                    : Color.white.opacity(isHovered ? 0.24 : 0.10),
                lineWidth: isSelected || item.isFrozen ? 1.6 : 1.0
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
                mid.move(to: CGPoint(x: 0, y: size.height * 0.55))
                mid.addLine(to: CGPoint(x: size.width, y: size.height * 0.55))
                ctx.stroke(mid, with: .color(tint.opacity(0.32)), lineWidth: 1.5)
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
                let y = size.height - CGFloat(max(0.12, min(0.88, norm))) * size.height
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            ctx.stroke(path, with: .color(tint.opacity(0.85)), lineWidth: 1.6)
        }
    }
}

// MARK: - Full-Height Symmetrical Right Inspector Dock

private struct CryoProcessInspectorCard: View {
    let item: CryoProcessItem
    let palette: ModulePalette
    let onToggleFreeze: () -> Void
    let onGracefulQuit: () -> Void
    let onForceQuit: () -> Void

    private var tint: Color {
        Color(hex: item.thermalState.accentHex)
    }

    private var cleanTitle: String {
        let raw = item.displayTitle
        if raw == "qemu-system-aarch64" || raw == "qemu-system-x86_64" {
            return "Android Emulator"
        }
        return raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Clean App Header
            HStack(spacing: 12) {
                NativeFileIconView(path: item.iconFilePath, isDirectory: false, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cleanTitle)
                        .font(.system(size: 15.5, weight: .bold))
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

            // 2. Symmetrical 2x2 Metric Grid (Never Truncates!)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                metricBox(
                    title: "CPU LOAD",
                    value: item.isFrozen ? "0.0%" : String(format: "%.1f%%", item.cpuPercent),
                    highlight: item.isFrozen ? Color(hex: "38BDF8") : (item.cpuPercent >= 20 ? Color(hex: "FF5E57") : nil)
                )
                metricBox(
                    title: "MEMORY",
                    value: ByteFormat.string(item.memoryBytes)
                )
                metricBox(
                    title: "RAM TREND",
                    value: item.memoryDeltaBytes > 0 ? "+\(ByteFormat.string(item.memoryDeltaBytes))" : "Stable",
                    highlight: item.isMemoryGrowing ? Color(hex: "FFB703") : Color(hex: "2ED573")
                )
                metricBox(
                    title: "PROCESS ID",
                    value: String(item.pid)
                )
            }

            // 3. Memory Pulse Graph (Expands smoothly to fill vertical height symmetrically)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("MEMORY PULSE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(item.isMemoryGrowing ? "Growing" : "Stable")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(item.isMemoryGrowing ? Color(hex: "FFB703") : Color(hex: "00F5D4"))
                }

                Spacer(minLength: 4)
                CryoMiniSparklineView(samples: item.memoryHistory, tint: tint)
                    .frame(maxHeight: 68)
                Spacer(minLength: 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.22)))

            // 4. Clean Action Stack at Bottom
            if item.isSystemProtected {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Protected macOS Service")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            } else {
                VStack(spacing: 8) {
                    Button(action: onToggleFreeze) {
                        HStack(spacing: 6) {
                            Image(systemName: item.isFrozen ? "sun.max.fill" : "snowflake")
                                .font(.system(size: 12, weight: .bold))
                            Text(item.isFrozen ? "Unfreeze App" : "Cryo-Freeze (0% CPU)")
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        .foregroundStyle(item.isFrozen ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
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
                        Button {
                            FileSystemHelpers.revealInFinder(path: item.iconFilePath)
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 34, height: 30)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")

                        Button(action: onGracefulQuit) {
                            Text("Quit")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        Button(action: onForceQuit) {
                            Text("Force Quit")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color(hex: "FF7B72"))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(Capsule().fill(Color(hex: "FF5E57").opacity(0.16)))
                                .overlay(Capsule().strokeBorder(Color(hex: "FF5E57").opacity(0.32), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
    }

    private func metricBox(title: String, value: String, highlight: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .foregroundStyle(highlight ?? .white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.22)))
    }
}
