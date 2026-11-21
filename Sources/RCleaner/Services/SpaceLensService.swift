import Foundation

public final class SpaceLensService {
    public init() {}

    public func buildTree(
        at rootURL: URL,
        maxDepth: Int = 3,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> SpaceLensNode {
        progress("Mapping \(rootURL.path)...", 0.15)
        let node = scanDirectory(url: rootURL, depth: 0, maxDepth: maxDepth, progress: progress)
        progress("Space map ready", 1.0)
        return node
    }

    private func scanDirectory(
        url: URL,
        depth: Int,
        maxDepth: Int,
        progress: @escaping @Sendable (String, Double) -> Void
    ) -> SpaceLensNode {
        let fm = FileManager.default
        let isHidden = url.lastPathComponent.hasPrefix(".")
        let isCloud = url.path.contains("/Mobile Documents/") || url.path.contains("/Library/CloudStorage/")

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                .totalFileAllocatedSizeKey, .fileSizeKey, .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ],
            options: []
        ) else {
            return SpaceLensNode(name: url.lastPathComponent, path: url.path, isDirectory: true, isHidden: isHidden, isCloudItem: isCloud)
        }

        var children: [SpaceLensNode] = []
        var totalSize: Int64 = 0

        for (idx, childURL) in contents.enumerated() {
            if Task.isCancelled { break }
            if depth == 0 {
                progress("Measuring \(childURL.lastPathComponent)...", 0.15 + (Double(idx) / Double(max(1, contents.count))) * 0.80)
            }
            guard let vals = try? childURL.resourceValues(forKeys: [
                .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                .totalFileAllocatedSizeKey, .fileSizeKey, .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]) else { continue }

            if vals.isSymbolicLink == true { continue }

            let name = childURL.lastPathComponent
            let childHidden = name.hasPrefix(".")
            let childIsCloud = isCloud || (vals.isUbiquitousItem == true)
            let isEvicted = vals.ubiquitousItemDownloadingStatus == .notDownloaded

            if vals.isDirectory == true && vals.isPackage != true {
                if depth < maxDepth {
                    let subNode = scanDirectory(url: childURL, depth: depth + 1, maxDepth: maxDepth, progress: progress)
                    totalSize += subNode.sizeBytes
                    if subNode.sizeBytes > 0 {
                        children.append(subNode)
                    }
                } else {
                    let dirBytes = FileSystemHelpers.directorySize(at: childURL, maxFiles: 4000)
                    totalSize += dirBytes
                    if dirBytes > 0 {
                        children.append(SpaceLensNode(
                            name: name,
                            path: childURL.path,
                            isDirectory: true,
                            isHidden: childHidden,
                            isCloudItem: childIsCloud,
                            isCloudOnlyEvicted: isEvicted,
                            sizeBytes: dirBytes
                        ))
                    }
                }
            } else {
                let sz: Int64
                if vals.isPackage == true {
                    sz = FileSystemHelpers.directorySize(at: childURL, maxFiles: 3000)
                } else {
                    sz = Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
                }
                totalSize += sz
                if sz > 0 {
                    children.append(SpaceLensNode(
                        name: name,
                        path: childURL.path,
                        isDirectory: false,
                        isHidden: childHidden,
                        isCloudItem: childIsCloud,
                        isCloudOnlyEvicted: isEvicted,
                        sizeBytes: sz
                    ))
                }
            }
        }

        children.sort { $0.sizeBytes > $1.sizeBytes }
        return SpaceLensNode(
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            path: url.path,
            isDirectory: true,
            isHidden: isHidden,
            isCloudItem: isCloud,
            sizeBytes: totalSize,
            children: children
        )
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
