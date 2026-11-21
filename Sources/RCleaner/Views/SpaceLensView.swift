import SwiftUI
import AppKit

public struct SpaceLensView: View {
    @EnvironmentObject var appState: AppState
    @State private var navigationStack: [SpaceLensNode] = []
    @State private var showReviewSheet = false
    @State private var showCloudDeleteAlert = false
    @State private var showPurgeablePopover = false
    private let palette = RCleanerTheme.palette(for: .spaceLens)

    public init() {}

    public var body: some View {
        switch appState.spaceLensStage {
        case .intro:
            ModuleIntroHero(
                title: "Space Lens",
                subtitle: "Visualize what's taking up the most disk space and clean up your storage quickly.",
                iconName: "circle.hexagongrid.fill",
                palette: palette,
                features: [
                    ("circle.grid.cross.fill", "Visual Storage Map", "Proportional interactive bubbles reveal your biggest folders and files instantly."),
                    ("folder.fill.badge.gearshape", "Large Folders Overview", "Drill down into nested directories with breadcrumb navigation."),
                    ("eye.fill", "Hidden Files Uncovered", "Shows hidden folders, cloud status indicators, and macOS purgeable space.")
                ],
                primaryActionTitle: "Scan",
                secondaryActionTitle: "Choose Folder (\(appState.spaceLensTargetURL.lastPathComponent))",
                onPrimaryAction: {
                    navigationStack = []
                    appState.startSpaceLensScan(url: appState.spaceLensTargetURL)
                },
                onSecondaryAction: { chooseTargetFolder() }
            )

        case .scanning:
            ScanningProgressView(
                title: "Visualizing your storage space...",
                subtitle: "Building proportional disk map for \(appState.spaceLensTargetURL.path)",
                currentPath: appState.spaceLensStatusText,
                progress: appState.spaceLensProgress,
                iconName: "circle.hexagongrid.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            if let root = appState.spaceLensRoot {
                spaceLensExplorer(root: root)
            }

        case .cleaning:
            ScanningProgressView(
                title: "Removing files...",
                subtitle: "Moving selected items to Trash.",
                currentPath: "",
                progress: 0.7,
                iconName: "trash.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.spaceLensSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: {
                    navigationStack = []
                    appState.spaceLensStage = .intro
                })
            }
        }
    }

    private func chooseTargetFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select Target"
        if panel.runModal() == .OK, let url = panel.url {
            appState.spaceLensTargetURL = url
            navigationStack = []
            appState.startSpaceLensScan(url: url)
        }
    }

    private func spaceLensExplorer(root: SpaceLensNode) -> some View {
        let currentNode = navigationStack.last ?? root
        let selectedNodes = appState.spaceLensService.collectSelectedNodes(from: root)
        let selectedBytes = selectedNodes.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "Space Lens",
                backTitle: "Start Over",
                trailingText: "\(ByteFormat.string(currentNode.sizeBytes)) • \(ByteFormat.itemCount(currentNode.itemCount))"
            ) {
                navigationStack = []
                appState.spaceLensStage = .intro
            }

            // Breadcrumb bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button(root.name) {
                        navigationStack = []
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .buttonStyle(.plain)

                    ForEach(Array(navigationStack.enumerated()), id: \.element.id) { idx, node in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                        Button(node.name) {
                            navigationStack = Array(navigationStack.prefix(idx + 1))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(idx == navigationStack.count - 1 ? palette.primary.opacity(0.75) : Color.white.opacity(0.10)))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 6)

            // Split: Left Directory List | Right Proportional Bubble Map
            HStack(spacing: 16) {
                // Left List
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(currentNode.children.prefix(80)) { child in
                            SpaceLensRow(
                                node: child,
                                palette: palette,
                                onSelectionChanged: { appState.objectWillChange.send() }
                            ) {
                                drillInto(child)
                            }
                        }
                    }
                }
                .frame(width: 340)

                // Right Interactive Bubble Map
                GeometryReader { geo in
                    BubbleMapCanvas(
                        nodes: Array(currentNode.children.prefix(14)),
                        totalSize: max(1, currentNode.sizeBytes),
                        palette: palette,
                        size: geo.size
                    ) { tapped in
                        if tapped.isDirectory {
                            drillInto(tapped)
                        } else {
                            tapped.isSelected.toggle()
                            appState.objectWillChange.send()
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            // Bottom Action Bar
            HStack(spacing: 14) {
                if !navigationStack.isEmpty {
                    Button {
                        navigationStack.removeLast()
                    } label: {
                        Label("Up One Level", systemImage: "arrow.up.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showPurgeablePopover.toggle()
                } label: {
                    Label("Purgeable: \(ByteFormat.string(appState.telemetry.storage.purgeableBytes))", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPurgeablePopover) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Purgeable Space").font(.headline)
                        Text("Purgeable space includes files macOS marks as safe to remove when storage runs low — like caches, temporary data, and redownloadable content.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Clean Purgeable Space") {
                            showPurgeablePopover = false
                            let perfService = appState.performanceService
                            Task.detached(priority: .userInitiated) {
                                let (_, msg) = perfService.executeSingleTask(.freeUpPurgeable)
                                await MainActor.run {
                                    appState.showBanner(msg)
                                    appState.refreshTelemetry(includeHeavy: true)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .frame(width: 280)
                }

                Spacer()

                if !selectedNodes.isEmpty {
                    Button("Review (\(selectedNodes.count))") {
                        showReviewSheet = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                    .buttonStyle(.plain)
                }

                UbiquitousButton(
                    title: "Remove",
                    subtitle: selectedNodes.isEmpty ? nil : ByteFormat.string(selectedBytes),
                    palette: palette,
                    isDisabled: selectedNodes.isEmpty
                ) {
                    if selectedNodes.contains(where: \.isCloudItem) {
                        showCloudDeleteAlert = true
                    } else {
                        performSpaceLensRemoval(selectedNodes)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showReviewSheet) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Review files before removal").font(.headline)
                        Text("Includes \(selectedNodes.count) item(s) across all selected folders (\(ByteFormat.string(selectedBytes))).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { showReviewSheet = false }
                }
                .padding()
                Divider()
                List(selectedNodes) { node in
                    HStack {
                        Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(.cyan)
                        VStack(alignment: .leading) {
                            Text(node.name).fontWeight(.medium)
                            Text(node.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(ByteFormat.string(node.sizeBytes)).font(.callout.monospacedDigit())
                        Button("Deselect") {
                            node.isSelected = false
                            appState.objectWillChange.send()
                        }
                        .controlSize(.small)
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Remove Selected (\(ByteFormat.string(selectedBytes)))", role: .destructive) {
                        showReviewSheet = false
                        if selectedNodes.contains(where: \.isCloudItem) {
                            showCloudDeleteAlert = true
                        } else {
                            performSpaceLensRemoval(selectedNodes)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(width: 600, height: 420)
        }
        .alert("Selected files will also be removed from the cloud", isPresented: $showCloudDeleteAlert) {
            Button("Change Selection", role: .cancel) {}
            Button("Continue", role: .destructive) { performSpaceLensRemoval(selectedNodes) }
        } message: {
            Text("Some selected files are stored in cloud storage. Removing them will permanently delete them from the cloud and connected devices.")
        }
    }

    private func drillInto(_ node: SpaceLensNode) {
        guard node.isDirectory else { return }
        if !node.children.isEmpty {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                navigationStack.append(node)
            }
            return
        }
        // Lazily expand folders deeper than the initial materialized tree depth
        let service = appState.spaceLensService
        Task {
            let loadedChildren = await service.expandNode(node, additionalDepth: 3)
            node.children = loadedChildren
            if !loadedChildren.isEmpty {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    navigationStack.append(node)
                }
                appState.objectWillChange.send()
            }
        }
    }

    private func performSpaceLensRemoval(_ nodes: [SpaceLensNode]) {
        Task {
            appState.spaceLensStage = .cleaning
            let res = await appState.spaceLensService.removeSelectedNodes(nodes)
            appState.stats.totalPersonalFilesCleanedBytes += res.bytesFreed
            appState.stats.monthlyCleanedBytes += res.bytesFreed
            appState.spaceLensSummary = res
            appState.spaceLensStage = .complete
            appState.refreshTelemetry(includeHeavy: true)
        }
    }
}

private struct SpaceLensRow: View {
    @ObservedObject var node: SpaceLensNode
    let palette: ModulePalette
    let onSelectionChanged: () -> Void
    let onDrillDown: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Toggle("", isOn: Binding(
                get: { node.isSelected },
                set: { newVal in
                    node.isSelected = newVal
                    onSelectionChanged()
                }
            ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(node.isCloudOnlyEvicted)

            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.isDirectory ? palette.accent : .white.opacity(0.7))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(node.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(node.isHidden ? .white.opacity(0.6) : .white)
                        .lineLimit(1)
                    if node.isCloudItem {
                        Image(systemName: "icloud").font(.system(size: 10)).foregroundStyle(palette.accent)
                    }
                }
                if node.isCloudOnlyEvicted {
                    Text("Cloud-only item").font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

            Text(ByteFormat.string(node.sizeBytes))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))

            if node.isDirectory && (!node.children.isEmpty || node.itemCount > 0) {
                Button(action: onDrillDown) {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(node.isSelected ? palette.primary.opacity(0.25) : Color.white.opacity(0.06)))
        .onTapGesture(count: 2) { onDrillDown() }
        .contextMenu {
            Button("Reveal in Finder") { FileSystemHelpers.revealInFinder(path: node.path) }
            if node.isDirectory && (!node.children.isEmpty || node.itemCount > 0) {
                Button("Open Folder in Space Lens") { onDrillDown() }
            }
        }
    }
}

private struct BubbleMapCanvas: View {
    let nodes: [SpaceLensNode]
    let totalSize: Int64
    let palette: ModulePalette
    let size: CGSize
    let onTap: (SpaceLensNode) -> Void

    var body: some View {
        let positions = layoutBubbles()
        ZStack {
            if nodes.isEmpty {
                Text("Empty folder").foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(Array(positions.enumerated()), id: \.element.node.id) { idx, item in
                    let gradColors: [Color] = idx % 3 == 0
                        ? [palette.primary.opacity(0.85), palette.secondary.opacity(0.65)]
                        : (idx % 3 == 1
                           ? [palette.secondary.opacity(0.80), palette.accent.opacity(0.55)]
                           : [palette.accent.opacity(0.75), palette.primary.opacity(0.55)])

                    Button {
                        onTap(item.node)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: gradColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(
                                    Circle().strokeBorder(
                                        item.node.isSelected ? Color.white : Color.white.opacity(0.30),
                                        lineWidth: item.node.isSelected ? 3 : 1.2
                                    )
                                )
                                .shadow(color: palette.primary.opacity(0.35), radius: 10)

                            VStack(spacing: 2) {
                                Image(systemName: item.node.isDirectory ? "folder.fill" : "doc.fill")
                                    .font(.system(size: max(11, item.radius * 0.24)))
                                    .foregroundStyle(.white.opacity(0.9))
                                if item.radius >= 34 {
                                    Text(item.node.name)
                                        .font(.system(size: min(13, max(9, item.radius * 0.17)), weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .frame(maxWidth: item.radius * 1.55)
                                    Text(ByteFormat.string(item.node.sizeBytes))
                                        .font(.system(size: min(11, max(8, item.radius * 0.14)), weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                        .frame(width: item.radius * 2, height: item.radius * 2)
                    }
                    .buttonStyle(.plain)
                    .position(item.center)
                    .help("\(item.node.name) — \(ByteFormat.string(item.node.sizeBytes))")
                }
            }
        }
    }

    private func layoutBubbles() -> [(node: SpaceLensNode, center: CGPoint, radius: CGFloat)] {
        guard !nodes.isEmpty, size.width > 40, size.height > 40 else { return [] }
        let cx = size.width / 2
        let cy = size.height / 2
        let maxR = min(size.width, size.height) * 0.24
        let minR: CGFloat = 24
        let largest = max(1, Double(nodes[0].sizeBytes))

        var placed: [(node: SpaceLensNode, center: CGPoint, radius: CGFloat)] = []
        for (i, node) in nodes.enumerated() {
            let ratio = sqrt(Double(node.sizeBytes) / largest)
            let r = max(minR, CGFloat(ratio) * maxR)

            if i == 0 {
                placed.append((node, CGPoint(x: cx, y: cy), r))
                continue
            }

            // Spiral placement until non-overlapping
            var foundPoint = CGPoint(x: cx, y: cy)
            var angle: CGFloat = CGFloat(i) * 1.1
            var dist: CGFloat = placed[0].radius + r + 8
            for _ in 0..<240 {
                let candidate = CGPoint(x: cx + cos(angle) * dist, y: cy + sin(angle) * dist)
                let inBounds = candidate.x - r > 10 && candidate.x + r < size.width - 10 && candidate.y - r > 10 && candidate.y + r < size.height - 10
                let overlaps = placed.contains { existing in
                    hypot(existing.center.x - candidate.x, existing.center.y - candidate.y) < (existing.radius + r + 6)
                }
                if inBounds && !overlaps {
                    foundPoint = candidate
                    break
                }
                angle += 0.42
                dist += 2.2
            }
            placed.append((node, foundPoint, r))
        }
        return placed
    }
}
