import Foundation
import CryptoKit
import AppKit
import CoreGraphics

public struct ClutterScanResult {
    public var duplicateGroups: [DuplicateGroup] = []
    public var similarImageGroups: [SimilarImageGroup] = []
    public var largeAndOldFiles: [ScanItem] = []
    public var downloads: [ScanItem] = []

    public var totalDuplicatesBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.totalWastedBytes }
    }
    public var totalSimilarImagesBytes: Int64 {
        similarImageGroups.reduce(0) { $0 + $1.selectedBytes }
    }
    public var totalLargeFilesBytes: Int64 {
        largeAndOldFiles.reduce(0) { $0 + $1.sizeBytes }
    }
    public var totalDownloadsBytes: Int64 {
        downloads.reduce(0) { $0 + $1.sizeBytes }
    }
}

public final class ClutterScannerService {
    public init() {}

    public func scanAll(
        rootURL: URL? = nil,
        settings: RCleanerSettings,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> ClutterScanResult {
        var result = ClutterScanResult()

        let roots: [URL]
        if let rootURL {
            roots = [rootURL]
        } else {
            roots = [
                URL(fileURLWithPath: FileSystemHelpers.expand("~/Downloads")),
                URL(fileURLWithPath: FileSystemHelpers.expand("~/Desktop")),
                URL(fileURLWithPath: FileSystemHelpers.expand("~/Documents")),
                URL(fileURLWithPath: FileSystemHelpers.expand("~/Pictures")),
                URL(fileURLWithPath: FileSystemHelpers.expand("~/Movies"))
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
        }

        progress("Collecting files across user folders...", 0.12)
        let files = collectRegularFiles(in: roots, maxFiles: 12_000)

        progress("Finding exact Duplicate Files (SHA-256)...", 0.35)
        result.duplicateGroups = findDuplicates(files: files, settings: settings)

        progress("Analyzing Similar Images & Visual Flaws...", 0.62)
        result.similarImageGroups = findSimilarImages(files: files, settings: settings)

        progress("Identifying Large & Old Files...", 0.80)
        result.largeAndOldFiles = findLargeAndOldFiles(files: files, settings: settings)

        progress("Reviewing Downloads folder...", 0.92)
        result.downloads = scanDownloads(settings: settings)

        progress("Clutter scan complete", 1.0)
        return result
    }

    private struct FileMeta {
        let url: URL
        let size: Int64
        let created: Date?
        let modified: Date?
        let accessed: Date?
    }

    private func collectRegularFiles(in roots: [URL], maxFiles: Int) -> [FileMeta] {
        let fm = FileManager.default
        var results: [FileMeta] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentAccessDateKey]

        for root in roots {
            guard let en = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in en {
                if results.count >= maxFiles { return results }
                guard let vals = try? url.resourceValues(forKeys: Set(keys)),
                      vals.isRegularFile == true,
                      let size = vals.fileSize, size > 1024 else { continue }
                results.append(FileMeta(
                    url: url,
                    size: Int64(size),
                    created: vals.creationDate,
                    modified: vals.contentModificationDate,
                    accessed: vals.contentAccessDate ?? vals.contentModificationDate
                ))
            }
        }
        return results
    }

    // MARK: - 1. Exact Duplicate Finder (Size -> Prefix -> SHA-256)

    public func findDuplicates(in directory: URL, settings: RCleanerSettings = RCleanerSettings()) -> [DuplicateGroup] {
        let files = collectRegularFiles(in: [directory], maxFiles: 10_000)
        return findDuplicates(files: files, settings: settings)
    }

    private func findDuplicates(files: [FileMeta], settings: RCleanerSettings) -> [DuplicateGroup] {
        // Group by exact byte size
        var bySize: [Int64: [FileMeta]] = [:]
        for f in files where f.size >= 4096 {
            if FileSystemHelpers.isIgnored(path: f.url.path, category: .duplicates, settings: settings) { continue }
            bySize[f.size, default: []].append(f)
        }

        var groups: [DuplicateGroup] = []
        for (size, candidates) in bySize where candidates.count >= 2 {
            // Fast 4KB head hash first
            var byPrefix: [String: [FileMeta]] = [:]
            for c in candidates {
                if let prefixHash = quickHash(url: c.url, maxBytes: 4096) {
                    byPrefix[prefixHash, default: []].append(c)
                }
            }

            // Full SHA-256 for prefix collisions
            for (_, samePrefix) in byPrefix where samePrefix.count >= 2 {
                var byFullHash: [String: [FileMeta]] = [:]
                for c in samePrefix {
                    if let full = sha256Hash(url: c.url) {
                        byFullHash[full, default: []].append(c)
                    }
                }

                for (hash, dupes) in byFullHash where dupes.count >= 2 {
                    let sorted = dupes.sorted {
                        ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture)
                    }
                    let entries = sorted.enumerated().map { idx, meta in
                        DuplicateFileEntry(
                            name: meta.url.lastPathComponent,
                            path: meta.url.path,
                            sizeBytes: meta.size,
                            createdDate: meta.created,
                            modifiedDate: meta.modified,
                            isOriginalRecommended: idx == 0,
                            isSelected: idx > 0 // Smart Selection: keep oldest original, select copies
                        )
                    }
                    groups.append(DuplicateGroup(
                        id: hash,
                        hash: hash,
                        fileName: sorted[0].url.lastPathComponent,
                        fileKind: FileSystemHelpers.fileKindLabel(for: sorted[0].url.path),
                        singleFileSize: size,
                        copies: entries
                    ))
                }
            }
        }
        return groups.sorted { $0.totalWastedBytes > $1.totalWastedBytes }
    }

    private func quickHash(url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maxBytes)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 256 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 2. Similar Images (Perceptual dHash + Visual Flaw Blur/Sharpness Scoring)

    private func findSimilarImages(files: [FileMeta], settings: RCleanerSettings) -> [SimilarImageGroup] {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tiff"]
        let images = files.filter {
            imageExts.contains($0.url.pathExtension.lowercased())
                && $0.size >= 20_000
                && !FileSystemHelpers.isIgnored(path: $0.url.path, category: .similar, settings: settings)
        }.prefix(220)

        struct FingerprintedImage {
            let meta: FileMeta
            let dHash: UInt64
            let width: Int
            let height: Int
            let sharpness: Double
        }

        var fingerprinted: [FingerprintedImage] = []
        for meta in images {
            if let fp = computeImageFingerprint(url: meta.url) {
                fingerprinted.append(FingerprintedImage(
                    meta: meta,
                    dHash: fp.dHash,
                    width: fp.width,
                    height: fp.height,
                    sharpness: fp.sharpness
                ))
            }
        }

        var visited = Set<Int>()
        var groups: [SimilarImageGroup] = []

        for i in 0..<fingerprinted.count {
            if visited.contains(i) { continue }
            var cluster: [FingerprintedImage] = [fingerprinted[i]]
            visited.insert(i)

            for j in (i + 1)..<fingerprinted.count where !visited.contains(j) {
                let dist = (fingerprinted[i].dHash ^ fingerprinted[j].dHash).nonzeroBitCount
                if dist <= 8 {
                    cluster.append(fingerprinted[j])
                    visited.insert(j)
                }
            }

            if cluster.count >= 2 {
                // Rank by resolution + sharpness so "Best to Keep" is automatically protected
                let ranked = cluster.sorted {
                    let scoreA = Double($0.width * $0.height) / 1_000_000.0 + $0.sharpness * 2.0
                    let scoreB = Double($1.width * $1.height) / 1_000_000.0 + $1.sharpness * 2.0
                    return scoreA > scoreB
                }
                let entries = ranked.enumerated().map { idx, item in
                    var flaws: [String] = []
                    if item.sharpness < 14.0 { flaws.append("Blur") }
                    return SimilarImageEntry(
                        name: item.meta.url.lastPathComponent,
                        path: item.meta.url.path,
                        sizeBytes: item.meta.size,
                        dimensions: "\(item.width)×\(item.height)",
                        createdDate: item.meta.created,
                        qualityScore: item.sharpness,
                        visualFlaws: flaws,
                        isBestToKeep: idx == 0,
                        isSelected: idx > 0
                    )
                }
                groups.append(SimilarImageGroup(
                    title: ranked[0].meta.url.deletingPathExtension().lastPathComponent,
                    images: entries
                ))
            }
        }

        return groups.sorted { $0.selectedBytes > $1.selectedBytes }
    }

    private func computeImageFingerprint(url: URL) -> (dHash: UInt64, width: Int, height: Int, sharpness: Double)? {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Render into a tiny 9x8 grayscale bitmap for 64-bit difference hash (dHash)
        let w = 9
        let h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hash: UInt64 = 0
        var bit: UInt64 = 1
        var gradientSum: Double = 0
        for row in 0..<h {
            for col in 0..<(w - 1) {
                let left = Int(pixels[row * w + col])
                let right = Int(pixels[row * w + col + 1])
                if left > right { hash |= bit }
                gradientSum += Double(abs(left - right))
                bit <<= 1
            }
        }
        let avgGradient = gradientSum / 64.0
        return (hash, cgImage.width, cgImage.height, avgGradient)
    }

    // MARK: - 3. Large & Old Files

    private func findLargeAndOldFiles(files: [FileMeta], settings: RCleanerSettings) -> [ScanItem] {
        let threshold: Int64 = 25 * 1024 * 1024 // >= 25 MB
        return files
            .filter { $0.size >= threshold && !FileSystemHelpers.isIgnored(path: $0.url.path, category: .largeAndOldFiles, settings: settings) }
            .sorted { $0.size > $1.size }
            .prefix(250)
            .map { meta in
                let kind = FileSystemHelpers.fileKindLabel(for: meta.url.path)
                return ScanItem(
                    name: meta.url.lastPathComponent,
                    path: meta.url.path,
                    sizeBytes: meta.size,
                    subtitle: kind,
                    categoryID: "largeAndOld",
                    groupTitle: kind,
                    isSelected: false,
                    lastModified: meta.modified,
                    lastAccessed: meta.accessed
                )
            }
    }

    // MARK: - 4. Downloads (with macOS com.apple.quarantine source attribution)

    private func scanDownloads(settings: RCleanerSettings) -> [ScanItem] {
        let downloadsDir = FileSystemHelpers.expand("~/Downloads")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: downloadsDir) else { return [] }
        var items: [ScanItem] = []

        for name in names where !name.hasPrefix(".") {
            let full = (downloadsDir as NSString).appendingPathComponent(name)
            if FileSystemHelpers.isIgnored(path: full, category: .downloads, settings: settings) { continue }
            let url = URL(fileURLWithPath: full)
            let size = FileSystemHelpers.fileSize(at: url)
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
            let sourceApp = detectDownloadSource(path: full)
            items.append(ScanItem(
                name: name,
                path: full,
                sizeBytes: size,
                subtitle: "\(sourceApp) • \(FileSystemHelpers.fileKindLabel(for: full))",
                categoryID: "downloads",
                groupTitle: sourceApp,
                isSelected: false,
                lastModified: vals?.contentModificationDate,
                lastAccessed: vals?.contentAccessDate,
                badge: sourceApp == "Downloads" ? nil : sourceApp
            ))
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func detectDownloadSource(path: String) -> String {
        let attrName = "com.apple.quarantine"
        let len = getxattr(path, attrName, nil, 0, 0, 0)
        guard len > 0 else { return "Downloads" }
        var buf = [CChar](repeating: 0, count: len + 1)
        guard getxattr(path, attrName, &buf, len, 0, 0) > 0 else { return "Downloads" }
        let raw = String(cString: buf)
        let parts = raw.split(separator: ";")
        if parts.count >= 3 {
            let agent = String(parts[2]).trimmingCharacters(in: .whitespaces)
            if agent.localizedCaseInsensitiveContains("Safari") { return "Safari" }
            if agent.localizedCaseInsensitiveContains("Chrome") { return "Google Chrome" }
            if agent.localizedCaseInsensitiveContains("Slack") { return "Slack" }
            if agent.localizedCaseInsensitiveContains("Firefox") { return "Firefox" }
            if !agent.isEmpty { return agent }
        }
        return "Downloads"
    }

    // MARK: - Remove Selected Clutter

    public func removeFiles(paths: [(name: String, path: String, sizeBytes: Int64)]) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0

        for item in paths {
            let res = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: true)
            if res.success {
                freed += item.sizeBytes
                ok += 1
                logs.append(CleanupLogEntry(moduleName: "My Clutter", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
            } else {
                fail += 1
                logs.append(CleanupLogEntry(moduleName: "My Clutter", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: res.error))
            }
        }
        return CleanupSummary(bytesFreed: freed, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Removal complete!", subtitle: "successfully removed")
    }
}
