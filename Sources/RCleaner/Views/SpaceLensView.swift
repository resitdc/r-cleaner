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

                // Right Interactive Glass Bubble Map
                GeometryReader { geo in
                    BubbleMapCanvas(
                        nodes: currentNode.children,
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
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
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

            NativeFileIconView(path: node.path, isDirectory: node.isDirectory, size: 22)

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

// MARK: - Native macOS File/Folder Icon View (Cached)

private final class SpaceLensIconCache {
    static let shared = SpaceLensIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        let key = (isDirectory ? "d:" : "f:") + path
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 128, height: 128)
        cache.setObject(img, forKey: key as NSString)
        return img
    }
}

private struct NativeFileIconView: View {
    let path: String
    let isDirectory: Bool
    let size: CGFloat

    var body: some View {
        Image(nsImage: SpaceLensIconCache.shared.icon(forPath: path, isDirectory: isDirectory))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Non-Overlapping Tangential Circle Packer

public struct PackedBubbleLayout: Equatable {
    public let index: Int
    public let center: CGPoint
    public let radius: CGFloat
}

public enum SpaceLensBubblePacker {
    /// Packs proportional bubbles tangentially into an organic, non-overlapping cluster
    /// and scales + centers the entire cluster cleanly inside `canvasSize`.
    public static func pack(sizes: [Int64], in canvasSize: CGSize, padding: CGFloat = 22) -> [PackedBubbleLayout] {
        guard !sizes.isEmpty, canvasSize.width > 40, canvasSize.height > 40 else { return [] }
        let largest = max(1.0, Double(sizes.max() ?? 1))

        // Compute proportional virtual radii (area scales with byte size, with readable floor)
        let virtualRadii: [CGFloat] = sizes.map { sz in
            let ratio = sqrt(max(0, Double(sz)) / largest)
            return CGFloat(max(24.0, ratio * 100.0))
        }

        let gap: CGFloat = 10.0
        var placed: [(idx: Int, x: CGFloat, y: CGFloat, r: CGFloat)] = []
        placed.reserveCapacity(sizes.count)

        for (i, r) in virtualRadii.enumerated() {
            if i == 0 {
                placed.append((0, 0, 0, r))
                continue
            }
            if i == 1 {
                // Place second-largest bubble organically beside the largest
                placed.append((1, placed[0].r + r + gap, 6, r))
                continue
            }

            // Compute weighted cluster centroid so subsequent bubbles tuck neatly into valleys
            var sumW: CGFloat = 0
            var cx: CGFloat = 0
            var cy: CGFloat = 0
            for p in placed {
                let w = p.r * p.r
                cx += p.x * w
                cy += p.y * w
                sumW += w
            }
            if sumW > 0 {
                cx /= sumW
                cy /= sumW
            }

            var bestPoint: (x: CGFloat, y: CGFloat)? = nil
            var bestScore: CGFloat = .greatestFiniteMagnitude

            func evaluateCandidate(x: CGFloat, y: CGFloat) {
                // Reject any overlap with existing bubbles
                for ex in placed {
                    let minDist = ex.r + r + gap - 0.5
                    let dx = x - ex.x
                    let dy = y - ex.y
                    if dx * dx + dy * dy < minDist * minDist {
                        return
                    }
                }
                let distToCenter = hypot(x - cx, y - cy)
                if distToCenter < bestScore {
                    bestScore = distToCenter
                    bestPoint = (x, y)
                }
            }

            // Exact pair-tangent placement touching two existing bubbles
            for aIdx in 0..<placed.count {
                let a = placed[aIdx]
                for bIdx in (aIdx + 1)..<placed.count {
                    let b = placed[bIdx]
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let d = hypot(dx, dy)
                    let da = a.r + r + gap
                    let db = b.r + r + gap
                    guard d > 0.001, d <= da + db, d >= abs(da - db) else { continue }

                    let aDist = (da * da - db * db + d * d) / (2 * d)
                    let hSq = max(0, da * da - aDist * aDist)
                    let h = sqrt(hSq)
                    let px = a.x + aDist * dx / d
                    let py = a.y + aDist * dy / d
                    let rx = -dy * (h / d)
                    let ry = dx * (h / d)

                    evaluateCandidate(x: px + rx, y: py + ry)
                    evaluateCandidate(x: px - rx, y: py - ry)
                }
            }

            // Fallback radial sweep around existing bubbles if no pair-tangent fit
            if bestPoint == nil {
                for anchor in placed {
                    let dist = anchor.r + r + gap
                    for step in 0..<24 {
                        let angle = CGFloat(step) * (.pi * 2.0 / 24.0)
                        evaluateCandidate(x: anchor.x + cos(angle) * dist, y: anchor.y + sin(angle) * dist)
                    }
                }
            }

            let chosen = bestPoint ?? (placed[0].x + placed[0].r + r + gap, 0)
            placed.append((i, chosen.x, chosen.y, r))
        }

        // Compute tight bounding box of entire packed cluster
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in placed {
            minX = min(minX, p.x - p.r)
            maxX = max(maxX, p.x + p.r)
            minY = min(minY, p.y - p.r)
            maxY = max(maxY, p.y + p.r)
        }

        let clusterW = max(1, maxX - minX)
        let clusterH = max(1, maxY - minY)
        let availW = max(20, canvasSize.width - padding * 2)
        let availH = max(20, canvasSize.height - padding * 2)

        // Cap max scale when only 1 bubble exists so a single item stays tasteful
        let maxSingleScale: CGFloat = placed.count == 1 ? (min(availW, availH) * 0.34 / max(1, placed[0].r)) : .greatestFiniteMagnitude
        let scale = min(availW / clusterW, availH / clusterH, maxSingleScale)

        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        let canvasCX = canvasSize.width / 2
        let canvasCY = canvasSize.height / 2

        return placed.map { p in
            PackedBubbleLayout(
                index: p.idx,
                center: CGPoint(
                    x: canvasCX + (p.x - midX) * scale,
                    y: canvasCY + (p.y - midY) * scale
                ),
                radius: max(10, p.r * scale)
            )
        }
    }
}

// MARK: - Translucent Glass Bubble Map Canvas

private enum BubbleEntry: Identifiable {
    case node(SpaceLensNode)
    case otherItems(count: Int, totalBytes: Int64)

    var id: String {
        switch self {
        case .node(let n): return n.id.uuidString
        case .otherItems: return "other-items-cluster"
        }
    }

    var sizeBytes: Int64 {
        switch self {
        case .node(let n): return n.sizeBytes
        case .otherItems(_, let b): return b
        }
    }
}

private struct BubbleMapCanvas: View {
    let nodes: [SpaceLensNode]
    let totalSize: Int64
    let palette: ModulePalette
    let size: CGSize
    let onTap: (SpaceLensNode) -> Void

    private var displayEntries: [BubbleEntry] {
        let maxIndividual = 8
        if nodes.count > maxIndividual + 1 {
            let head = nodes.prefix(maxIndividual).map { BubbleEntry.node($0) }
            let tail = nodes.dropFirst(maxIndividual)
            let tailBytes = tail.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return head + [.otherItems(count: tail.count, totalBytes: tailBytes)]
        }
        return nodes.map { BubbleEntry.node($0) }
    }

    var body: some View {
        let entries = displayEntries
        let packed = SpaceLensBubblePacker.pack(sizes: entries.map(\.sizeBytes), in: size)

        ZStack {
            if entries.isEmpty {
                Text("Empty folder").foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(packed, id: \.index) { layout in
                    let entry = entries[layout.index]
                    GlassStorageBubbleView(
                        entry: entry,
                        radius: layout.radius,
                        palette: palette
                    ) {
                        if case .node(let n) = entry {
                            onTap(n)
                        }
                    }
                    .position(layout.center)
                }
            }
        }
        .clipped()
    }
}

private struct GlassStorageBubbleView: View {
    let entry: BubbleEntry
    let radius: CGFloat
    let palette: ModulePalette
    let action: () -> Void
    @State private var isHovered = false

    private var isSelected: Bool {
        if case .node(let n) = entry { return n.isSelected }
        return false
    }

    private var helpText: String {
        switch entry {
        case .node(let n):
            return "\(n.name) — \(ByteFormat.string(n.sizeBytes))"
        case .otherItems(let count, let bytes):
            return "\(count) other items — \(ByteFormat.string(bytes))"
        }
    }

    var body: some View {
        let diameter = radius * 2
        let rimColor = isSelected ? Color.white : palette.accent

        Button(action: action) {
            ZStack {
                // Translucent soap-bubble / luminous glass sphere fill (dark hollow core → glowing edge)
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: palette.backgroundMid.opacity(isHovered ? 0.34 : 0.24), location: 0.0),
                                .init(color: palette.secondary.opacity(isHovered ? 0.36 : 0.26), location: 0.56),
                                .init(color: palette.primary.opacity(isHovered ? 0.62 : 0.48), location: 0.88),
                                .init(color: rimColor.opacity(isHovered ? 0.78 : 0.62), location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    // Subtle inner upper specular sheen
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.22 : 0.14),
                                        Color.clear,
                                        palette.accent.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    // Crisp luminous glass rim border
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSelected ? 0.95 : (isHovered ? 0.72 : 0.48)),
                                        palette.accent.opacity(isHovered ? 0.62 : 0.36),
                                        Color.white.opacity(isSelected ? 0.85 : 0.42)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSelected ? 2.8 : (isHovered ? 1.8 : 1.2)
                            )
                    )
                    .shadow(color: palette.primary.opacity(isHovered ? 0.45 : 0.24), radius: isHovered ? 16 : 10)

                // Content inside bubble
                bubbleContent
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch entry {
        case .node(let node):
            let iconSize: CGFloat = {
                if radius >= 70 { return min(82, radius * 0.62) }
                if radius >= 40 { return min(48, radius * 0.68) }
                return max(20, radius * 0.86)
            }()

            VStack(spacing: radius >= 56 ? 5 : 2) {
                NativeFileIconView(path: node.path, isDirectory: node.isDirectory, size: iconSize)
                    .shadow(color: Color.black.opacity(0.28), radius: 6, y: 3)

                if radius >= 36 {
                    Text(node.name)
                        .font(.system(size: min(14.5, max(10, radius * 0.145)), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: radius * 1.62)
                }

                if radius >= 54 {
                    Text(ByteFormat.string(node.sizeBytes))
                        .font(.system(size: min(13.5, max(10.5, radius * 0.135)), weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.92))
                }
            }

        case .otherItems(let count, let bytes):
            VStack(spacing: 4) {
                // Iconic grouped-bubbles glyph for "Other items"
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: max(12, radius * 0.42), height: max(12, radius * 0.42))
                        .offset(x: radius * 0.08, y: radius * 0.06)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: max(5, radius * 0.16), height: max(5, radius * 0.16))
                        .offset(x: -radius * 0.20, y: -radius * 0.18)
                }
                if radius >= 44 {
                    Text("Other items")
                        .font(.system(size: min(12, max(9.5, radius * 0.15)), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
                if radius >= 58 {
                    Text("\(count) • \(ByteFormat.string(bytes))")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}
