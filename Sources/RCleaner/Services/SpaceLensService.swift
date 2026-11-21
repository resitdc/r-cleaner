import Foundation
import Darwin

/// Deadlock-free async concurrency gate that limits simultaneous filesystem I/O workers
/// across nested `withTaskGroup` fan-outs without ever blocking a Swift cooperative thread.
private actor AsyncConcurrencyLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            available += 1
        }
    }
}

/// Thread-safe progress throttle (reports UI updates at most every 180ms to keep Main Thread idle).
private final class ThrottledProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReport = CFAbsoluteTimeGetCurrent()
    private var completedTopUnits = 0
    private var measuredDirs = 0
    private let totalTopUnits: Int
    private let callback: @Sendable (String, Double) -> Void

    init(totalTopUnits: Int, callback: @escaping @Sendable (String, Double) -> Void) {
        self.totalTopUnits = max(1, totalTopUnits)
        self.callback = callback
    }

    func noteDirectory(_ label: String) {
        lock.lock()
        measuredDirs += 1
        let now = CFAbsoluteTimeGetCurrent()
        let shouldSend = (now - lastReport >= 0.18)
        let basePct = Double(completedTopUnits) / Double(totalTopUnits)
        // Smooth asymptotic creep while a large single folder (e.g. projects) is being fanned out
        let subPct = (1.0 - basePct) * (1.0 - exp(-Double(measuredDirs) / 400.0)) * 0.75
        let pct = min(0.96, 0.08 + (basePct + subPct) * 0.88)
        if shouldSend { lastReport = now }
        lock.unlock()
        if shouldSend {
            callback("Measuring \(label)...", pct)
        }
    }

    func finishTopUnit(_ label: String) {
        lock.lock()
        completedTopUnits += 1
        let now = CFAbsoluteTimeGetCurrent()
        let shouldSend = (now - lastReport >= 0.12)
        let pct = min(0.96, 0.08 + (Double(completedTopUnits) / Double(totalTopUnits)) * 0.88)
        if shouldSend { lastReport = now }
        lock.unlock()
        if shouldSend {
            callback("Measuring \(label)...", pct)
        }
    }
}

/// High-speed, APFS-accurate storage tree scanner powered by native macOS `getattrlistbulk`
/// and multi-level parallel fan-out across all CPU cores.
/// - Counts every file without artificial file-count caps (`maxFiles: 0`)
/// - Preserves packages and bundles (`.app`, `.xcodeproj`, `.framework`, `.xcarchive`, etc.)
/// - Uses physical allocated bytes (`ATTR_FILE_ALLOCSIZE`) matching macOS Finder & Space Lens
/// - Skips symlinks and cross-volume mount points, and excludes dataless cloud placeholders (`SF_DATALESS`)
/// - Saturates all cores even when 99% of files live under a single nested subfolder
public final class SpaceLensService: @unchecked Sendable {
    public init() {}

    public func buildTree(
        at rootURL: URL,
        maxDepth: Int = 4,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> SpaceLensNode {
        let rootPath = rootURL.path
        progress("Mapping \(rootPath)...", 0.06)

        var rootSt = stat()
        guard lstat(rootPath, &rootSt) == 0 else {
            progress("Space map ready", 1.0)
            return SpaceLensNode(
                name: rootURL.lastPathComponent.isEmpty ? rootPath : rootURL.lastPathComponent,
                path: rootPath,
                isDirectory: true,
                sizeBytes: 0,
                itemCount: 0
            )
        }

        let rootDev = rootSt.st_dev
        let isRootCloud = rootPath.contains("/Mobile Documents/") || rootPath.contains("/Library/CloudStorage/")
        let maxWorkers = min(10, max(4, ProcessInfo.processInfo.activeProcessorCount))
        let limiter = AsyncConcurrencyLimiter(limit: maxWorkers)

        await limiter.acquire()
        let topEntries = FileSystemHelpers.readDirectoryBulk(atPath: rootPath)
        await limiter.release()

        let tracker = ThrottledProgress(totalTopUnits: topEntries.count, callback: progress)
        let basePrefix = rootPath == "/" ? "/" : (rootPath + "/")

        var children: [SpaceLensNode] = []
        children.reserveCapacity(topEntries.count)
        var totalBytes: Int64 = 0
        var totalItems: Int = 0

        await withTaskGroup(of: (node: SpaceLensNode?, bytes: Int64, items: Int).self) { group in
            for entry in topEntries {
                if Task.isCancelled { break }
                if entry.isSymlink { continue }
                if entry.devID != rootDev { continue }

                let childPath = basePrefix + entry.name
                if childPath == "/System/Volumes/Data" || childPath == "/dev" { continue }

                if entry.isDirectory {
                    group.addTask(priority: .userInitiated) {
                        if Task.isCancelled { return (nil, 0, 0) }
                        let node = await self.scanDirectoryAsync(
                            name: entry.name,
                            path: childPath,
                            depth: 1,
                            maxDepth: maxDepth,
                            rootDev: rootDev,
                            isHidden: entry.name.hasPrefix("."),
                            isCloud: isRootCloud || childPath.contains("/Mobile Documents/") || childPath.contains("/Library/CloudStorage/"),
                            isDataless: entry.isDataless,
                            limiter: limiter,
                            tracker: tracker
                        )
                        tracker.finishTopUnit(entry.name)
                        guard let node else { return (nil, 0, 0) }
                        let visible: SpaceLensNode? = (node.sizeBytes > 0 || node.isCloudOnlyEvicted) ? node : nil
                        return (visible, node.sizeBytes, node.itemCount)
                    }
                } else if entry.isRegularFile {
                    let (node, bytes, items) = Self.makeFileResult(
                        entry: entry,
                        path: childPath,
                        parentIsCloud: isRootCloud
                    )
                    totalBytes += bytes
                    totalItems += items
                    if let node { children.append(node) }
                    tracker.finishTopUnit(entry.name)
                }
            }

            for await res in group {
                totalBytes += res.bytes
                totalItems += res.items
                if let node = res.node {
                    children.append(node)
                }
            }
        }

        children.sort { $0.sizeBytes > $1.sizeBytes }
        progress("Space map ready", 1.0)
        return SpaceLensNode(
            name: rootURL.lastPathComponent.isEmpty ? rootPath : rootURL.lastPathComponent,
            path: rootPath,
            isDirectory: true,
            isHidden: rootURL.lastPathComponent.hasPrefix("."),
            isCloudItem: isRootCloud,
            sizeBytes: totalBytes,
            itemCount: totalItems,
            children: children
        )
    }

    /// Lazily expands a directory node deeper than the initial `maxDepth` when the user drills down.
    public func expandNode(_ node: SpaceLensNode, additionalDepth: Int = 3) async -> [SpaceLensNode] {
        guard node.isDirectory else { return [] }
        let built = await buildTree(at: URL(fileURLWithPath: node.path), maxDepth: additionalDepth) { _, _ in }
        return built.children
    }

    private func scanDirectoryAsync(
        name: String,
        path: String,
        depth: Int,
        maxDepth: Int,
        rootDev: dev_t,
        isHidden: Bool,
        isCloud: Bool,
        isDataless: Bool,
        limiter: AsyncConcurrencyLimiter,
        tracker: ThrottledProgress
    ) async -> SpaceLensNode? {
        if Task.isCancelled { return nil }

        // Leaf depth: measure the ENTIRE remaining subtree iteratively with unlimited file count
        if depth >= maxDepth {
            await limiter.acquire()
            let (bytes, items) = FileSystemHelpers.bulkMeasureSubtree(
                atPath: path,
                rootDev: rootDev,
                maxFiles: 0
            )
            await limiter.release()
            tracker.noteDirectory(name)

            return SpaceLensNode(
                name: name,
                path: path,
                isDirectory: true,
                isHidden: isHidden,
                isCloudItem: isCloud,
                isCloudOnlyEvicted: isDataless,
                sizeBytes: bytes,
                itemCount: items,
                children: []
            )
        }

        // Read direct children under limiter, then release BEFORE fanning out so we can never deadlock
        await limiter.acquire()
        let entries = FileSystemHelpers.readDirectoryBulk(atPath: path)
        await limiter.release()
        tracker.noteDirectory(name)

        let basePrefix = path == "/" ? "/" : (path + "/")
        var dirEntries: [(entry: FileSystemHelpers.BulkDirEntry, path: String)] = []
        var children: [SpaceLensNode] = []
        children.reserveCapacity(entries.count)
        var totalBytes: Int64 = 0
        var totalItems: Int = 0

        for entry in entries {
            if Task.isCancelled { break }
            if entry.isSymlink { continue }
            if entry.devID != rootDev { continue }
            let childPath = basePrefix + entry.name
            if childPath == "/System/Volumes/Data" || childPath == "/dev" { continue }

            if entry.isDirectory {
                dirEntries.append((entry, childPath))
            } else if entry.isRegularFile {
                let (node, bytes, items) = Self.makeFileResult(
                    entry: entry,
                    path: childPath,
                    parentIsCloud: isCloud
                )
                totalBytes += bytes
                totalItems += items
                if let node { children.append(node) }
            }
        }

        // Fan out directory children across cores; batch if a directory has hundreds of subdirectories
        // to avoid spawning excessive Task objects while keeping all cores saturated.
        if dirEntries.count == 1 {
            let item = dirEntries[0]
            if let child = await scanDirectoryAsync(
                name: item.entry.name,
                path: item.path,
                depth: depth + 1,
                maxDepth: maxDepth,
                rootDev: rootDev,
                isHidden: item.entry.name.hasPrefix("."),
                isCloud: isCloud || item.path.contains("/Mobile Documents/") || item.path.contains("/Library/CloudStorage/"),
                isDataless: item.entry.isDataless,
                limiter: limiter,
                tracker: tracker
            ) {
                totalBytes += child.sizeBytes
                totalItems += child.itemCount
                if child.sizeBytes > 0 || child.isCloudOnlyEvicted {
                    children.append(child)
                }
            }
        } else if dirEntries.count > 1 && dirEntries.count <= 256 {
            await withTaskGroup(of: SpaceLensNode?.self) { group in
                for item in dirEntries {
                    if Task.isCancelled { break }
                    let childCloud = isCloud || item.path.contains("/Mobile Documents/") || item.path.contains("/Library/CloudStorage/")
                    group.addTask(priority: .userInitiated) {
                        await self.scanDirectoryAsync(
                            name: item.entry.name,
                            path: item.path,
                            depth: depth + 1,
                            maxDepth: maxDepth,
                            rootDev: rootDev,
                            isHidden: item.entry.name.hasPrefix("."),
                            isCloud: childCloud,
                            isDataless: item.entry.isDataless,
                            limiter: limiter,
                            tracker: tracker
                        )
                    }
                }
                for await child in group {
                    if let child {
                        totalBytes += child.sizeBytes
                        totalItems += child.itemCount
                        if child.sizeBytes > 0 || child.isCloudOnlyEvicted {
                            children.append(child)
                        }
                    }
                }
            }
        } else if dirEntries.count > 256 {
            let bucketCount = min(10, max(4, ProcessInfo.processInfo.activeProcessorCount))
            let chunkSize = (dirEntries.count + bucketCount - 1) / bucketCount
            await withTaskGroup(of: ([SpaceLensNode], Int64, Int).self) { group in
                for start in stride(from: 0, to: dirEntries.count, by: chunkSize) {
                    let slice = Array(dirEntries[start..<min(start + chunkSize, dirEntries.count)])
                    group.addTask(priority: .userInitiated) {
                        var localNodes: [SpaceLensNode] = []
                        var localBytes: Int64 = 0
                        var localItems: Int = 0
                        for item in slice {
                            if Task.isCancelled { break }
                            let childCloud = isCloud || item.path.contains("/Mobile Documents/") || item.path.contains("/Library/CloudStorage/")
                            if let child = await self.scanDirectoryAsync(
                                name: item.entry.name,
                                path: item.path,
                                depth: depth + 1,
                                maxDepth: maxDepth,
                                rootDev: rootDev,
                                isHidden: item.entry.name.hasPrefix("."),
                                isCloud: childCloud,
                                isDataless: item.entry.isDataless,
                                limiter: limiter,
                                tracker: tracker
                            ) {
                                localBytes += child.sizeBytes
                                localItems += child.itemCount
                                if child.sizeBytes > 0 || child.isCloudOnlyEvicted {
                                    localNodes.append(child)
                                }
                            }
                        }
                        return (localNodes, localBytes, localItems)
                    }
                }
                for await (nodes, bytes, items) in group {
                    totalBytes += bytes
                    totalItems += items
                    children.append(contentsOf: nodes)
                }
            }
        }

        children.sort { $0.sizeBytes > $1.sizeBytes }
        return SpaceLensNode(
            name: name,
            path: path,
            isDirectory: true,
            isHidden: isHidden,
            isCloudItem: isCloud,
            isCloudOnlyEvicted: isDataless,
            sizeBytes: totalBytes,
            itemCount: totalItems,
            children: children
        )
    }

    private static func makeFileResult(
        entry: FileSystemHelpers.BulkDirEntry,
        path: String,
        parentIsCloud: Bool
    ) -> (node: SpaceLensNode?, bytes: Int64, items: Int) {
        let isHidden = entry.name.hasPrefix(".")
        if entry.isDataless {
            let node = SpaceLensNode(
                name: entry.name,
                path: path,
                isDirectory: false,
                isHidden: isHidden,
                isCloudItem: true,
                isCloudOnlyEvicted: true,
                sizeBytes: 0,
                itemCount: 1,
                children: []
            )
            return (node, 0, 1)
        }
        let sz = entry.allocatedSize
        guard sz > 0 else {
            // Still count 0-byte regular files in itemCount without cluttering the visual bubble map
            return (nil, 0, 1)
        }
        let isCloud = parentIsCloud || path.contains("/Mobile Documents/") || path.contains("/Library/CloudStorage/")
        let node = SpaceLensNode(
            name: entry.name,
            path: path,
            isDirectory: false,
            isHidden: isHidden,
            isCloudItem: isCloud,
            isCloudOnlyEvicted: false,
            sizeBytes: sz,
            itemCount: 1,
            children: []
        )
        return (node, sz, 1)
    }

    public func collectSelectedNodes(from root: SpaceLensNode) -> [SpaceLensNode] {
        var list: [SpaceLensNode] = []
        if root.isSelected {
            list.append(root)
            return list
        }
        for child in root.children {
            list.append(contentsOf: collectSelectedNodes(from: child))
        }
        return list
    }

    public func removeSelectedNodes(_ nodes: [SpaceLensNode]) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0
        for node in nodes {
            let res = FileSystemHelpers.safeRemoveItem(at: node.path, moveToTrash: true)
            if res.success {
                freed += node.sizeBytes
                ok += 1
                logs.append(CleanupLogEntry(moduleName: "Space Lens", itemName: node.name, path: node.path, sizeBytes: node.sizeBytes, status: .cleaned))
            } else {
                fail += 1
                logs.append(CleanupLogEntry(moduleName: "Space Lens", itemName: node.name, path: node.path, sizeBytes: node.sizeBytes, status: .failed, errorMessage: res.error))
            }
        }
        return CleanupSummary(bytesFreed: freed, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Removal complete!", subtitle: "successfully removed")
    }
}
