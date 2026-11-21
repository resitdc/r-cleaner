import Foundation
import AppKit
import ApplicationServices

public enum FileSystemHelpers {
    private static let protectedPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Apple"
    ]

    public static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public static func expand(_ tildePath: String) -> String {
        (tildePath as NSString).expandingTildeInPath
    }

    public static func isProtectedSystemPath(_ path: String) -> Bool {
        let std = (path as NSString).standardizingPath
        if std == "/" || std == homeDirectory { return true }
        return protectedPrefixes.contains { std == $0 || std.hasPrefix($0 + "/") }
    }

    public static func isIgnored(path: String, category: IgnoreListCategory, settings: RCleanerSettings) -> Bool {
        let std = (path as NSString).standardizingPath
        return settings.ignoredItems.contains { item in
            item.category == category && (std == item.path || std.hasPrefix(item.path + "/"))
        }
    }

    public static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return directorySize(at: url)
    }

    public static func directorySize(at url: URL, maxFiles: Int = 20_000) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? Int64) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            count += 1
            if count > maxFiles { break }
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
               values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return total
    }

    public static func safeRemoveItem(at path: String, moveToTrash: Bool = true) -> (success: Bool, error: String?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return (true, nil)
        }
        if isProtectedSystemPath(path) {
            return (false, "Protected macOS system path cannot be removed.")
        }
        let url = URL(fileURLWithPath: path)
        do {
            if moveToTrash {
                var resultingURL: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resultingURL)
            } else {
                try fm.removeItem(at: url)
            }
            return (true, nil)
        } catch {
            // Fallback to direct remove for caches/trash items where trashItem isn't allowed
            if moveToTrash && (path.contains("/.Trash") || path.contains("/Library/Caches/")) {
                do {
                    try fm.removeItem(at: url)
                    return (true, nil)
                } catch {
                    return (false, error.localizedDescription)
                }
            }
            return (false, error.localizedDescription)
        }
    }

    public static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func openFile(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    public static func hasFullDiskAccess() -> Bool {
        let testPaths = [
            expand("~/Library/Safari/Bookmarks.plist"),
            expand("~/Library/Mail"),
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        let fm = FileManager.default
        for p in testPaths {
            if fm.isReadableFile(atPath: p) {
                return true
            }
        }
        return false
    }

    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public static func openPrivacySettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    public static func runProcess(_ launchPath: String, arguments: [String], timeout: TimeInterval = 15) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        // Drain stdout & stderr concurrently so large outputs (>64KB) never deadlock the pipe
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let sem = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sem.signal() }

        if sem.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = sem.wait(timeout: .now() + 1.0)
            _ = group.wait(timeout: .now() + 1.0)
            return (-2, "", "Timed out")
        }

        _ = group.wait(timeout: .now() + 2.0)
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    public static func runAdminShellScript(_ script: String) -> (success: Bool, output: String) {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        let res = runProcess("/usr/bin/osascript", arguments: ["-e", appleScript], timeout: 60)
        return (res.exitCode == 0, res.exitCode == 0 ? res.stdout : res.stderr)
    }

    public static func fileKindLabel(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "tiff", "bmp", "raw", "cr2", "dng", "svg":
            return "Pictures"
        case "mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv":
            return "Videos"
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "aiff":
            return "Audio"
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "pages", "numbers", "key", "csv":
            return "Documents"
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "iso":
            return "Archives"
        case "app":
            return "Applications"
        default:
            return "Other"
        }
    }

    public static func playCompletionSound(enabled: Bool) {
        guard enabled else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
