import Foundation
import AppKit
import ApplicationServices
import Darwin

public enum FileSystemHelpers {
    private static let protectedPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Apple"
    ]

    /// Critical root directories that must never be deleted directly (items inside them may still be managed).
    private static var protectedExactDirectories: Set<String> {
        let home = homeDirectory
        return [
            "/",
            "/Applications",
            "/Library",
            "/Users",
            "/Volumes",
            "/private",
            "/etc",
            "/var",
            home,
            "\(home)/Library",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Pictures",
            "\(home)/Movies",
            "\(home)/Music"
        ]
    }

    public static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public static func expand(_ tildePath: String) -> String {
        (tildePath as NSString).expandingTildeInPath
    }

    public static func isProtectedSystemPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let std = (trimmed as NSString).standardizingPath
        if protectedExactDirectories.contains(std) { return true }
        return protectedPrefixes.contains { std == $0 || std.hasPrefix($0 + "/") }
    }

    public static func isIgnored(path: String, category: IgnoreListCategory, settings: RCleanerSettings) -> Bool {
        let std = (path as NSString).standardizingPath
        return settings.ignoredItems.contains { item in
            item.category == category && (std == item.path || std.hasPrefix(item.path + "/"))
        }
    }

    public static func fileSize(at url: URL) -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        let mode = st.st_mode & S_IFMT
        if mode == S_IFLNK { return 0 }
        if mode == S_IFDIR {
            return directorySize(at: url, maxFiles: 0)
        }
        // Dataless cloud-only placeholders occupy 0 local bytes
        if (st.st_flags & UInt32(SF_DATALESS)) != 0 { return 0 }
        let alloc = Int64(st.st_blocks) * 512
        return alloc > 0 ? alloc : Int64(st.st_size)
    }

    /// High-speed APFS-aware recursive directory measurement powered by macOS `getattrlistbulk`.
    /// Measures ALL regular files including packages/bundles without skipping descendants, skips symlinks
    /// and cross-volume mount points, and excludes dataless cloud-only placeholders (`SF_DATALESS`).
    /// Uses physical allocated disk bytes (`ATTR_FILE_ALLOCSIZE`), matching macOS Finder & Space Lens.
    /// Pass `maxFiles: 0` for unlimited exact totals.
    public static func directorySize(at url: URL, maxFiles: Int = 0) -> Int64 {
        let (bytes, _) = bulkMeasureSubtree(atPath: url.path, rootDev: nil, maxFiles: maxFiles)
        return bytes
    }

    public struct BulkDirEntry: Sendable {
        public let name: String
        public let isDirectory: Bool
        public let isRegularFile: Bool
        public let isSymlink: Bool
        public let isDataless: Bool
        public let devID: dev_t
        public let allocatedSize: Int64
    }

    /// Reads all direct children of `dirPath` in batches using macOS `getattrlistbulk`.
    public static func readDirectoryBulk(atPath dirPath: String) -> [BulkDirEntry] {
        let fd = open(dirPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS)
            | UInt32(ATTR_CMN_NAME)
            | UInt32(ATTR_CMN_DEVID)
            | UInt32(ATTR_CMN_OBJTYPE)
            | UInt32(ATTR_CMN_FLAGS)
        al.fileattr = UInt32(ATTR_FILE_TOTALSIZE)
            | UInt32(ATTR_FILE_ALLOCSIZE)

        let bufSize = 128 * 1024
        let rawBuf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { rawBuf.deallocate() }

        var entries: [BulkDirEntry] = []
        entries.reserveCapacity(64)

        while true {
            if Task.isCancelled { break }
            let count = getattrlistbulk(fd, &al, rawBuf, bufSize, 0)
            if count <= 0 { break }

            var entryOffset = 0
            for _ in 0..<count {
                guard entryOffset + 4 <= bufSize else { break }
                let entryBase = rawBuf.advanced(by: entryOffset)
                let entryLen = Int(entryBase.loadUnaligned(as: UInt32.self))
                guard entryLen >= 24, entryOffset + entryLen <= bufSize else { break }
                defer { entryOffset += entryLen }

                var cur = 4
                let returned = entryBase.advanced(by: cur).loadUnaligned(as: attribute_set_t.self)
                cur += MemoryLayout<attribute_set_t>.size

                var name = ""
                var devID: dev_t = 0
                var objType: UInt32 = 0
                var flags: UInt32 = 0
                var totalSize: Int64 = 0
                var allocSize: Int64 = 0
                var hasAllocSize = false

                // Common attributes in exact ascending bit order
                if (returned.commonattr & UInt32(ATTR_CMN_NAME)) != 0, cur + MemoryLayout<attrreference_t>.size <= entryLen {
                    let refPos = cur
                    let ref = entryBase.advanced(by: cur).loadUnaligned(as: attrreference_t.self)
                    cur += MemoryLayout<attrreference_t>.size
                    let nameOff = refPos + Int(ref.attr_dataoffset)
                    if nameOff >= 0, nameOff < entryLen {
                        name = String(cString: entryBase.advanced(by: nameOff).assumingMemoryBound(to: CChar.self))
                    }
                }
                if (returned.commonattr & UInt32(ATTR_CMN_DEVID)) != 0, cur + 4 <= entryLen {
                    devID = entryBase.advanced(by: cur).loadUnaligned(as: dev_t.self)
                    cur += 4
                }
                if (returned.commonattr & UInt32(ATTR_CMN_OBJTYPE)) != 0, cur + 4 <= entryLen {
                    objType = entryBase.advanced(by: cur).loadUnaligned(as: UInt32.self)
                    cur += 4
                }
                if (returned.commonattr & UInt32(ATTR_CMN_FLAGS)) != 0, cur + 4 <= entryLen {
                    flags = entryBase.advanced(by: cur).loadUnaligned(as: UInt32.self)
                    cur += 4
                }

                // File attributes (returned for non-directories) in ascending bit order
                if (returned.fileattr & UInt32(ATTR_FILE_TOTALSIZE)) != 0, cur + 8 <= entryLen {
                    totalSize = entryBase.advanced(by: cur).loadUnaligned(as: Int64.self)
                    cur += 8
                }
                if (returned.fileattr & UInt32(ATTR_FILE_ALLOCSIZE)) != 0, cur + 8 <= entryLen {
                    allocSize = entryBase.advanced(by: cur).loadUnaligned(as: Int64.self)
                    hasAllocSize = true
                    cur += 8
                }

                guard !name.isEmpty, name != ".", name != ".." else { continue }
                let isDir = objType == VDIR.rawValue
                let isReg = objType == VREG.rawValue
                let isLink = objType == VLNK.rawValue
                let isDataless = (flags & UInt32(SF_DATALESS)) != 0
                let effectiveSize: Int64
                if isDir || isLink || isDataless || !isReg {
                    effectiveSize = 0
                } else {
                    effectiveSize = hasAllocSize ? allocSize : totalSize
                }

                entries.append(BulkDirEntry(
                    name: name,
                    isDirectory: isDir,
                    isRegularFile: isReg,
                    isSymlink: isLink,
                    isDataless: isDataless,
                    devID: devID,
                    allocatedSize: effectiveSize
                ))
            }
        }
        return entries
    }

    /// Ultra-fast iterative stack-based `getattrlistbulk` subtree measurement (zero URL allocations,
    /// at most 1 open file descriptor at any instant, handles millions of files cleanly).
    /// Returns physical allocated bytes (`ATTR_FILE_ALLOCSIZE`) and regular file count.
    public static func bulkMeasureSubtree(
        atPath rootPath: String,
        rootDev: dev_t?,
        maxFiles: Int = 0
    ) -> (bytes: Int64, itemCount: Int) {
        var rootSt = stat()
        guard lstat(rootPath, &rootSt) == 0 else { return (0, 0) }
        let mode = rootSt.st_mode & S_IFMT
        if mode == S_IFLNK { return (0, 0) }
        if mode != S_IFDIR {
            if (rootSt.st_flags & UInt32(SF_DATALESS)) != 0 { return (0, 1) }
            let alloc = Int64(rootSt.st_blocks) * 512
            return (alloc > 0 ? alloc : Int64(rootSt.st_size), 1)
        }

        let targetDev = rootDev ?? rootSt.st_dev
        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS)
            | UInt32(ATTR_CMN_NAME)
            | UInt32(ATTR_CMN_DEVID)
            | UInt32(ATTR_CMN_OBJTYPE)
            | UInt32(ATTR_CMN_FLAGS)
        al.fileattr = UInt32(ATTR_FILE_TOTALSIZE)
            | UInt32(ATTR_FILE_ALLOCSIZE)

        let bufSize = 128 * 1024
        let rawBuf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { rawBuf.deallocate() }

        var totalBytes: Int64 = 0
        var totalItems: Int = 0
        var dirStack: [String] = [rootPath]
        dirStack.reserveCapacity(1024)

        while let dirPath = dirStack.popLast() {
            if Task.isCancelled { break }
            if maxFiles > 0 && totalItems >= maxFiles { break }

            let fd = open(dirPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { continue }
            defer { close(fd) }

            let basePrefix = dirPath == "/" ? "/" : (dirPath + "/")

            while true {
                if Task.isCancelled { break }
                if maxFiles > 0 && totalItems >= maxFiles { break }
                let count = getattrlistbulk(fd, &al, rawBuf, bufSize, 0)
                if count <= 0 { break }

                var entryOffset = 0
                for _ in 0..<count {
                    guard entryOffset + 4 <= bufSize else { break }
                    let entryBase = rawBuf.advanced(by: entryOffset)
                    let entryLen = Int(entryBase.loadUnaligned(as: UInt32.self))
                    guard entryLen >= 24, entryOffset + entryLen <= bufSize else { break }
                    defer { entryOffset += entryLen }

                    var cur = 4
                    let returned = entryBase.advanced(by: cur).loadUnaligned(as: attribute_set_t.self)
                    cur += MemoryLayout<attribute_set_t>.size

                    var nameOff = -1
                    var devID: dev_t = targetDev
                    var objType: UInt32 = 0
                    var flags: UInt32 = 0
                    var totalSize: Int64 = 0
                    var allocSize: Int64 = 0
                    var hasAllocSize = false

                    if (returned.commonattr & UInt32(ATTR_CMN_NAME)) != 0, cur + MemoryLayout<attrreference_t>.size <= entryLen {
                        let refPos = cur
                        let ref = entryBase.advanced(by: cur).loadUnaligned(as: attrreference_t.self)
                        cur += MemoryLayout<attrreference_t>.size
                        nameOff = refPos + Int(ref.attr_dataoffset)
                    }
                    if (returned.commonattr & UInt32(ATTR_CMN_DEVID)) != 0, cur + 4 <= entryLen {
                        devID = entryBase.advanced(by: cur).loadUnaligned(as: dev_t.self)
                        cur += 4
                    }
                    if (returned.commonattr & UInt32(ATTR_CMN_OBJTYPE)) != 0, cur + 4 <= entryLen {
                        objType = entryBase.advanced(by: cur).loadUnaligned(as: UInt32.self)
                        cur += 4
                    }
                    if (returned.commonattr & UInt32(ATTR_CMN_FLAGS)) != 0, cur + 4 <= entryLen {
                        flags = entryBase.advanced(by: cur).loadUnaligned(as: UInt32.self)
                        cur += 4
                    }

                    if (returned.fileattr & UInt32(ATTR_FILE_TOTALSIZE)) != 0, cur + 8 <= entryLen {
                        totalSize = entryBase.advanced(by: cur).loadUnaligned(as: Int64.self)
                        cur += 8
                    }
                    if (returned.fileattr & UInt32(ATTR_FILE_ALLOCSIZE)) != 0, cur + 8 <= entryLen {
                        allocSize = entryBase.advanced(by: cur).loadUnaligned(as: Int64.self)
                        hasAllocSize = true
                        cur += 8
                    }

                    // Skip symlinks and cross-volume mounts
                    if objType == VLNK.rawValue { continue }
                    if devID != targetDev { continue }

                    if objType == VDIR.rawValue {
                        guard nameOff >= 0, nameOff < entryLen else { continue }
                        let cName = entryBase.advanced(by: nameOff).assumingMemoryBound(to: CChar.self)
                        // Fast skip "." and ".." without allocating String
                        if cName[0] == 46 && (cName[1] == 0 || (cName[1] == 46 && cName[2] == 0)) { continue }
                        let childPath = basePrefix + String(cString: cName)
                        // Avoid APFS Data volume firmlink recursion when scanning root
                        if childPath == "/System/Volumes/Data" || childPath == "/dev" { continue }
                        dirStack.append(childPath)
                    } else if objType == VREG.rawValue {
                        totalItems += 1
                        if (flags & UInt32(SF_DATALESS)) != 0 { continue }
                        let sz = hasAllocSize ? allocSize : totalSize
                        if sz > 0 { totalBytes += sz }
                    }
                }
            }
        }
        return (totalBytes, totalItems)
    }

    public static func safeRemoveItem(at path: String, moveToTrash: Bool = true) -> (success: Bool, error: String?) {
        let fm = FileManager.default
        if isProtectedSystemPath(path) {
            return (false, "Protected macOS system path cannot be removed.")
        }
        // Use attributesOfItem in addition to fileExists so broken symlinks are still detected and removable
        let existsOrSymlink = fm.fileExists(atPath: path) || ((try? fm.attributesOfItem(atPath: path)) != nil)
        guard existsOrSymlink else {
            return (true, nil)
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
