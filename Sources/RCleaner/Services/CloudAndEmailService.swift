import Foundation

public final class CloudAndEmailService {
    public init() {}

    // MARK: - Cloud Cleanup (iCloud Drive, Google Drive, OneDrive, Dropbox)

    public func discoverCloudAccounts() -> [CloudAccountStatus] {
        let fm = FileManager.default
        let cloudStorageRoot = FileSystemHelpers.expand("~/Library/CloudStorage")
        let cloudEntries = (try? fm.contentsOfDirectory(atPath: cloudStorageRoot)) ?? []

        // iCloud Drive
        let icloudPath = FileSystemHelpers.expand("~/Library/Mobile Documents/com~apple~CloudDocs")
        let icloudExists = fm.fileExists(atPath: icloudPath)

        // Google Drive
        let gdriveEntry = cloudEntries.first { $0.lowercased().hasPrefix("googledrive") }
        let gdrivePath = gdriveEntry.map { (cloudStorageRoot as NSString).appendingPathComponent($0) }

        // OneDrive
        let onedriveEntry = cloudEntries.first { $0.lowercased().hasPrefix("onedrive") }
        let onedrivePath = onedriveEntry.map { (cloudStorageRoot as NSString).appendingPathComponent($0) }

        // Dropbox
        let dbCloud = cloudEntries.first { $0.lowercased().hasPrefix("dropbox") }
            .map { (cloudStorageRoot as NSString).appendingPathComponent($0) }
        let dbHome = FileSystemHelpers.expand("~/Dropbox")
        let dropboxPath = dbCloud ?? (fm.fileExists(atPath: dbHome) ? dbHome : nil)

        return [
            CloudAccountStatus(id: "icloud", provider: .iCloud, rootPath: icloudExists ? icloudPath : nil, isDetected: icloudExists, isConnected: icloudExists, totalScannedBytes: 0, locallySyncedBytes: 0, cloudOnlyBytes: 0, items: []),
            CloudAccountStatus(id: "gdrive", provider: .googleDrive, rootPath: gdrivePath, isDetected: gdrivePath != nil, isConnected: gdrivePath != nil, totalScannedBytes: 0, locallySyncedBytes: 0, cloudOnlyBytes: 0, items: []),
            CloudAccountStatus(id: "onedrive", provider: .oneDrive, rootPath: onedrivePath, isDetected: onedrivePath != nil, isConnected: onedrivePath != nil, totalScannedBytes: 0, locallySyncedBytes: 0, cloudOnlyBytes: 0, items: []),
            CloudAccountStatus(id: "dropbox", provider: .dropbox, rootPath: dropboxPath, isDetected: dropboxPath != nil, isConnected: dropboxPath != nil, totalScannedBytes: 0, locallySyncedBytes: 0, cloudOnlyBytes: 0, items: [])
        ]
    }

    public func scanCloudAccount(
        _ account: CloudAccountStatus,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> CloudAccountStatus {
        var updated = account
        guard let rootPath = account.rootPath, FileManager.default.fileExists(atPath: rootPath) else {
            return updated
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentAccessDateKey, .ubiquitousItemDownloadingStatusKey
        ]

        guard let en = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return updated }

        var items: [CloudFileItem] = []
        var total: Int64 = 0
        var localBytes: Int64 = 0
        var cloudOnly: Int64 = 0
        var count = 0

        for case let url as URL in en {
            count += 1
            if count > 4000 { break }
            if count % 250 == 0 {
                progress("Scanning \(account.provider.rawValue): \(url.lastPathComponent)...", min(0.95, Double(count) / 4000.0))
            }
            guard let vals = try? url.resourceValues(forKeys: Set(keys)),
                  vals.isRegularFile == true else { continue }

            let logicalSize = Int64(vals.fileSize ?? 0)
            let allocated = Int64(vals.totalFileAllocatedSize ?? 0)
            let isEvicted = vals.ubiquitousItemDownloadingStatus == .notDownloaded || (logicalSize > 4096 && allocated == 0)
            let isLocallySynced = !isEvicted

            total += logicalSize
            if isLocallySynced {
                localBytes += logicalSize
            } else {
                cloudOnly += logicalSize
            }

            if logicalSize >= 512 * 1024 {
                items.append(CloudFileItem(
                    name: url.lastPathComponent,
                    path: url.path,
                    provider: account.provider,
                    sizeBytes: logicalSize,
                    isLocallySynced: isLocallySynced,
                    lastAccessed: vals.contentAccessDate,
                    fileKind: FileSystemHelpers.fileKindLabel(for: url.path)
                ))
            }
        }

        updated.totalScannedBytes = total
        updated.locallySyncedBytes = localBytes
        updated.cloudOnlyBytes = cloudOnly
        updated.items = items.sorted { $0.sizeBytes > $1.sizeBytes }
        progress("Cloud scan complete", 1.0)
        return updated
    }

    public func unsyncCloudItems(_ items: [CloudFileItem]) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0
        let fm = FileManager.default

        for item in items where item.isSelected && item.isLocallySynced {
            let url = URL(fileURLWithPath: item.path)
            do {
                try fm.evictUbiquitousItem(at: url)
                freed += item.sizeBytes
                ok += 1
                logs.append(CleanupLogEntry(moduleName: "Cloud Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
            } catch {
                // Fallback to brctl evict for iCloud Drive
                let res = FileSystemHelpers.runProcess("/usr/bin/brctl", arguments: ["evict", item.path], timeout: 10)
                if res.exitCode == 0 {
                    freed += item.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Cloud Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Cloud Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: error.localizedDescription))
                }
            }
        }
        return CleanupSummary(bytesFreed: freed, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Unsyncing complete!", subtitle: "successfully unsynced")
    }

    public func removeCloudItems(_ items: [CloudFileItem]) async -> CleanupSummary {
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0
        for item in items where item.isSelected {
            let res = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: true)
            if res.success {
                freed += item.sizeBytes
                ok += 1
                logs.append(CleanupLogEntry(moduleName: "Cloud Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
            } else {
                fail += 1
                logs.append(CleanupLogEntry(moduleName: "Cloud Cleanup", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: res.error))
            }
        }
        return CleanupSummary(bytesFreed: freed, itemsProcessed: ok, itemsFailed: fail, logEntries: logs, title: "Removal complete!", subtitle: "cloud files removed")
    }

    // MARK: - Email Cleanup (Local Apple Mail .emlx Analyzer)

    public func scanLocalAppleMail(
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> [EmailMessageItem] {
        let mailRoot = FileSystemHelpers.expand("~/Library/Mail")
        guard FileManager.default.fileExists(atPath: mailRoot) else {
            return []
        }

        progress("Scanning local Apple Mail folders...", 0.25)
        let url = URL(fileURLWithPath: mailRoot)
        guard let en = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var messages: [EmailMessageItem] = []
        var scanned = 0

        for case let fileURL as URL in en {
            guard fileURL.pathExtension == "emlx" else { continue }
            scanned += 1
            if scanned > 400 { break }
            if scanned % 40 == 0 {
                progress("Analyzing email headers (\(scanned) scanned)...", min(0.95, 0.25 + Double(scanned) / 500.0))
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data.prefix(8192), encoding: .utf8) ?? String(data: data.prefix(8192), encoding: .isoLatin1) else { continue }

            let headers = parseHeaders(from: text)
            let subject = headers["subject"] ?? "<no subject>"
            let fromRaw = headers["from"] ?? "Unknown sender"
            let (senderName, senderEmail) = parseSender(fromRaw)
            let hasUnsub = headers["list-unsubscribe"] != nil
            let lowerPath = fileURL.path.lowercased()
            let lowerSub = subject.lowercased()
            let lowerFrom = fromRaw.lowercased()
            let size = Int64(data.count)
            let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

            let category: EmailCleanupCategory
            let tag: String
            if lowerPath.contains("junk") || lowerPath.contains("spam") {
                category = .spam
                tag = "Spam"
            } else if lowerPath.contains("draft") {
                category = .drafts
                tag = "Unfinished Draft"
            } else if hasUnsub || lowerFrom.contains("newsletter") || lowerFrom.contains("noreply") || lowerFrom.contains("no-reply") {
                category = hasUnsub ? .subscriptions : .newsletters
                tag = lowerSub.contains("sale") || lowerSub.contains("off") || lowerSub.contains("promo") ? "Old Promotions" : "Automated Emails"
            } else if size > 1_000_000 {
                category = .smartCleanup
                tag = "Large Emails"
            } else {
                category = .senders
                tag = "Top Senders"
            }

            messages.append(EmailMessageItem(
                subject: subject,
                senderName: senderName,
                senderEmail: senderEmail,
                snippet: extractSnippet(from: text),
                date: date,
                sizeBytes: size,
                hasAttachments: text.contains("Content-Disposition: attachment"),
                isUnread: false,
                hasUnsubscribeHeader: hasUnsub,
                category: category,
                suggestionTag: tag,
                filePath: fileURL.path
            ))
        }

        progress("Email analysis complete", 1.0)
        return messages.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func parseHeaders(from text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !result.isEmpty { break }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let val = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if result[key] == nil { result[key] = val }
            }
        }
        return result
    }

    private func parseSender(_ raw: String) -> (String, String) {
        if let open = raw.firstIndex(of: "<"), let close = raw.firstIndex(of: ">"), open < close {
            let name = raw[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            let email = String(raw[raw.index(after: open)..<close])
            return (name.isEmpty ? email : name, email)
        }
        return (raw, raw)
    }

    private func extractSnippet(from text: String) -> String {
        let parts = text.components(separatedBy: "\n\n")
        guard parts.count > 1 else { return "<no preview>" }
        let body = parts[1].replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "<no preview>" : String(body.prefix(160))
    }
}
