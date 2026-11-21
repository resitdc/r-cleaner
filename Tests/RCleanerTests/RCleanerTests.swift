import XCTest
@testable import RCleaner

final class RCleanerTests: XCTestCase {
    func testByteFormatting() {
        XCTAssertEqual(ByteFormat.string(0), "0 KB")
        XCTAssertEqual(ByteFormat.string(-42), "0 KB")
        XCTAssertEqual(ByteFormat.string(512), "< 1 KB")
        XCTAssertTrue(ByteFormat.string(1_500_000).contains("MB"))
    }

    func testIgnoreListMatching() {
        var settings = RCleanerSettings()
        settings.ignoredItems = [
            IgnoredItem(category: .systemJunk, path: "/Users/test/Library/Caches/com.example.app", displayName: "com.example.app")
        ]
        XCTAssertTrue(FileSystemHelpers.isIgnored(path: "/Users/test/Library/Caches/com.example.app", category: .systemJunk, settings: settings))
        XCTAssertTrue(FileSystemHelpers.isIgnored(path: "/Users/test/Library/Caches/com.example.app/sub/file.dat", category: .systemJunk, settings: settings))
        XCTAssertFalse(FileSystemHelpers.isIgnored(path: "/Users/test/Library/Caches/com.other.app", category: .systemJunk, settings: settings))
        XCTAssertFalse(FileSystemHelpers.isIgnored(path: "/Users/test/Library/Caches/com.example.app", category: .aiClutter, settings: settings))
    }

    func testProtectedSystemPaths() {
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath(""))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/System/Library/CoreServices"))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/usr/bin/swift"))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/"))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/Applications"))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath(FileSystemHelpers.expand("~/Library")))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath(FileSystemHelpers.expand("~/Desktop")))
        XCTAssertFalse(FileSystemHelpers.isProtectedSystemPath("/tmp/r-cleaner-test-file"))
        XCTAssertFalse(FileSystemHelpers.isProtectedSystemPath(FileSystemHelpers.expand("~/Downloads/example.dmg")))
    }

    func testSafeRemoveBrokenSymlink() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rcleaner-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let brokenLink = tempDir.appendingPathComponent("dangling.link")
        try FileManager.default.createSymbolicLink(atPath: brokenLink.path, withDestinationPath: "/nonexistent/target/\(UUID().uuidString)")
        XCTAssertNotNil(try? FileManager.default.attributesOfItem(atPath: brokenLink.path))

        let res = FileSystemHelpers.safeRemoveItem(at: brokenLink.path, moveToTrash: false)
        XCTAssertTrue(res.success)
        XCTAssertNil(try? FileManager.default.attributesOfItem(atPath: brokenLink.path))
    }

    func testResilientSettingsDecodePreservesOldConfig() throws {
        // Simulate legacy settings.json from an older version without Voice AI keys
        let legacyJSON = """
        {
          "hasCompletedIntro": true,
          "playSounds": false,
          "warnLowDiskSpaceGB": 25
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RCleanerSettings.self, from: legacyJSON)
        XCTAssertTrue(decoded.hasCompletedIntro)
        XCTAssertFalse(decoded.playSounds)
        XCTAssertEqual(decoded.warnLowDiskSpaceGB, 25)
        // New Voice AI fields gracefully receive defaults instead of failing decode
        XCTAssertTrue(decoded.enableVoiceAssistant)
        XCTAssertTrue(decoded.useBundledVoicePack)
        XCTAssertEqual(decoded.voiceAddressTitle, "sir")
    }

    func testTerminateProcessSafetyGuards() {
        let service = SystemTelemetryService()
        XCTAssertFalse(service.terminateProcess(pid: 0))
        XCTAssertFalse(service.terminateProcess(pid: 1))
        XCTAssertFalse(service.terminateProcess(pid: getpid()))
    }

    func testQuarantineSourceNormalization() {
        // Empty agent field with UUID in slot 4 must NOT leak the UUID
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;;53284369-0D70-4BD4-9B4F-C0E93175221F"), "Downloads")
        // Internal macOS daemon & bundle IDs normalize cleanly
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;sharingd;UUID"), "AirDrop")
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;com.apple.photos.ImageConversionService;UUID"), "Photos")
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;PhotosPluginAddToPhotos;UUID"), "Photos")
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;Google Chrome;UUID"), "Chrome")
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;Microsoft Word;UUID"), "Word")
        XCTAssertEqual(ClutterScannerService.normalizeQuarantineRaw("0083;66123abc;com.vendor.SomeInternalHelper;UUID"), "Other Apps")
    }

    func testDuplicateFinderDetectsExactCopies() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rcleaner-dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = Data(repeating: 0xAB, count: 16_384)
        let uniquePayload = Data(repeating: 0xCD, count: 16_384)

        try payload.write(to: tempDir.appendingPathComponent("fileA.bin"))
        try payload.write(to: tempDir.appendingPathComponent("fileA_copy.bin"))
        try uniquePayload.write(to: tempDir.appendingPathComponent("fileB.bin"))

        let service = ClutterScannerService()
        let groups = service.findDuplicates(in: tempDir)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].copies.count, 2)
        // Smart selection keeps 1 original unselected and selects 1 copy
        XCTAssertEqual(groups[0].copies.filter(\.isOriginalRecommended).count, 1)
        XCTAssertEqual(groups[0].copies.filter(\.isSelected).count, 1)
    }

    func testSpaceLensTreeCalculation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rcleaner-lens-\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("BigFolder")
        let pkgDir = subDir.appendingPathComponent("NestedApp.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = subDir.appendingPathComponent("data.bin")
        let pkgBin = pkgDir.appendingPathComponent("AppBin")
        let hardLink = subDir.appendingPathComponent("data_hardlink.bin")
        let symLink = subDir.appendingPathComponent("data_symlink.bin")

        try Data(repeating: 0x11, count: 65_536).write(to: fileA)
        try Data(repeating: 0x22, count: 65_536).write(to: pkgBin)
        try FileManager.default.linkItem(at: fileA, to: hardLink)
        try FileManager.default.createSymbolicLink(at: symLink, withDestinationURL: fileA)

        let service = SpaceLensService()
        let root = await service.buildTree(at: tempDir, maxDepth: 2) { _, _ in }
        // Must count data.bin (64KB), package descendant AppBin (64KB), AND hard link (64KB, matching
        // Finder/APFS per-folder sizing invariance), while NOT following or double-counting the symlink (< 240KB).
        XCTAssertGreaterThanOrEqual(root.sizeBytes, 196_608)
        XCTAssertLessThan(root.sizeBytes, 240_000)
        XCTAssertEqual(root.children.first?.name, "BigFolder")
        // Counts regular files only (data.bin, AppBin, data_hardlink.bin) — excludes directories and symlinks
        XCTAssertEqual(root.itemCount, 3)
        XCTAssertEqual(ByteFormat.itemCount(2_763_088), "2M items")
        XCTAssertEqual(ByteFormat.itemCount(4_354_232), "4M items")
    }

    func testDevAISweeperArtifactDetectionAndSafety() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("rcleaner-devsweep-\(UUID().uuidString)")
        let fm = FileManager.default
        defer { try? fm.removeItem(at: tempRoot) }

        // 1. Valid stale Node.js project with nested node_modules (nested must be pruned, not reported twice)
        let nodeProj = tempRoot.appendingPathComponent("old-web-app")
        let nodeMods = nodeProj.appendingPathComponent("node_modules/pkg/node_modules")
        try fm.createDirectory(at: nodeMods, withIntermediateDirectories: true)
        let pkgJSON = nodeProj.appendingPathComponent("package.json")
        try Data("{}".utf8).write(to: pkgJSON)
        let bigJS = nodeProj.appendingPathComponent("node_modules/bundle.js")
        try Data(repeating: 0x41, count: 1_500_000).write(to: bigJS)

        // Backdate old-web-app by 45 days so it's detected as stale
        let oldDate = Date().addingTimeInterval(-45 * 86_400)
        for u in [pkgJSON, bigJS, nodeProj.appendingPathComponent("node_modules"), nodeProj] {
            try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: u.path)
        }

        // 2. Valid active Rust project (modified today -> must NOT be auto-selected)
        let rustProj = tempRoot.appendingPathComponent("active-rust")
        let rustTarget = rustProj.appendingPathComponent("target/debug")
        try fm.createDirectory(at: rustTarget, withIntermediateDirectories: true)
        try Data("[package]\nname = \"demo\"".utf8).write(to: rustProj.appendingPathComponent("Cargo.toml"))
        try Data(repeating: 0x42, count: 1_500_000).write(to: rustTarget.appendingPathComponent("demo"))

        // 3. Decoy user folder named "build" with NO manifest sibling -> must NEVER be flagged
        let decoy = tempRoot.appendingPathComponent("my-photos/build")
        try fm.createDirectory(at: decoy, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 1_500_000).write(to: decoy.appendingPathComponent("photo.jpg"))

        let service = DevAISweeperService()
        let result = await service.scanAll(
            settings: RCleanerSettings(),
            customWorkspaces: [tempRoot.path],
            includeDefaultWorkspaces: false,
            includeSystemCategories: false,
            staleDaysThreshold: 30
        ) { _, _ in }

        let tempHits = result.items.filter { $0.path.hasPrefix(tempRoot.path) }
        XCTAssertEqual(tempHits.count, 2, "Expected exactly old-web-app/node_modules and active-rust/target")

        let nodeHit = tempHits.first { $0.projectName == "old-web-app" }
        XCTAssertNotNil(nodeHit)
        XCTAssertEqual(nodeHit?.ecosystem, "Node.js")
        XCTAssertTrue(nodeHit?.isSelected == true, "Stale 45d node_modules should be auto-selected")
        XCTAssertGreaterThanOrEqual(nodeHit?.ageDays ?? 0, 40)

        let rustHit = tempHits.first { $0.projectName == "active-rust" }
        XCTAssertNotNil(rustHit)
        XCTAssertEqual(rustHit?.ecosystem, "Rust")
        XCTAssertFalse(rustHit?.isSelected == true, "Active Rust target/ modified today must NOT be auto-selected")

        XCTAssertFalse(tempHits.contains { $0.path.contains("my-photos/build") }, "Decoy build folder without manifest must never be flagged")
        XCTAssertEqual(DevAISweeperService.parseDockerSize("12.5GB (85%)"), 12_500_000_000)
        XCTAssertEqual(DevAISweeperService.parseDockerSize("480MB"), 480_000_000)
    }

    func testAssistantHealthScoring() {
        let assistant = AssistantService()
        var telemetry = SystemTelemetrySnapshot()
        telemetry.storage.totalBytes = 500_000_000_000
        telemetry.storage.availableBytes = 250_000_000_000
        telemetry.memory.totalBytes = 16_000_000_000
        telemetry.memory.activeBytes = 4_000_000_000

        var stats = ActivityStatistics.empty
        stats.lastSmartCareDate = Date()

        let healthy = assistant.evaluateHealth(telemetry: telemetry, stats: stats, settings: RCleanerSettings(), threatsFound: 0)
        XCTAssertGreaterThanOrEqual(healthy.score, 80)

        let infected = assistant.evaluateHealth(telemetry: telemetry, stats: stats, settings: RCleanerSettings(), threatsFound: 2)
        XCTAssertLessThan(infected.score, healthy.score)
        XCTAssertTrue(infected.recommendations.contains { $0.id == "malwareDetected" })
    }

    func testLiveTelemetrySnapshot() {
        let service = SystemTelemetryService()
        let snap = service.captureSnapshot(includeProcessesAndDrives: false)
        XCTAssertGreaterThan(snap.memory.totalBytes, 0)
        XCTAssertGreaterThan(snap.storage.totalBytes, 0)
        XCTAssertGreaterThan(snap.cpu.coreCount, 0)
    }

    func testResitdcVectorLogoPaths() {
        let rect = CGRect(x: 0, y: 0, width: 130, height: 93)
        let cyanPath = ResitdcCyanShape().path(in: rect)
        let whitePath = ResitdcWhiteShape().path(in: rect)
        XCTAssertFalse(cyanPath.isEmpty)
        XCTAssertFalse(whitePath.isEmpty)
        XCTAssertEqual(cyanPath.boundingRect.width, 81, accuracy: 0.5)
        XCTAssertEqual(whitePath.boundingRect.maxX, 129.5, accuracy: 0.5)

        // Verify aspect ratio is preserved even inside a tall/distorted container
        let tallRect = CGRect(x: 0, y: 0, width: 130, height: 260)
        let tallCyan = ResitdcCyanShape().path(in: tallRect)
        XCTAssertEqual(tallCyan.boundingRect.width / tallCyan.boundingRect.height, 81.0 / 92.5, accuracy: 0.01)
    }

    @MainActor
    func testVoiceAssistantGreetingAndBriefing() {
        let greeting = VoiceAssistantService.timeOfDayGreeting(address: "sir")
        XCTAssertTrue(greeting.contains("sir"))
        XCTAssertTrue(greeting.contains("R-Cleaner"))

        var snap = SystemTelemetrySnapshot()
        snap.storage.totalBytes = 500_000_000_000
        snap.storage.availableBytes = 200_000_000_000
        let briefing = VoiceAssistantService.systemBriefing(telemetry: snap, healthScore: 95, address: "sir")
        XCTAssertTrue(briefing.contains("95 percent"))
        XCTAssertTrue(briefing.contains("nominal"))

        // Verify live modular briefing cue selection adapts to telemetry
        let healthyCues = VoiceAssistantService.briefingCues(telemetry: snap, healthScore: 95, threatsCount: 0)
        XCTAssertEqual(healthyCues, [.briefingHealthExcellent, .briefingStoragePlenty, .briefingPerfNominal, .briefingOutroNominal])

        var stressedSnap = snap
        stressedSnap.storage.availableBytes = 5_000_000_000
        stressedSnap.cpu.userPercent = 70
        stressedSnap.cpu.systemPercent = 18
        let stressedCues = VoiceAssistantService.briefingCues(telemetry: stressedSnap, healthScore: 42, threatsCount: 2)
        XCTAssertEqual(stressedCues, [.briefingHealthAttention, .briefingStorageLow, .briefingPerfHeavy, .briefingOutroThreats])

        // Verify all 27 bundled Jarvis neural voice clips are included inside the app bundle
        XCTAssertEqual(VoiceAssistantService.bundledClipCount, VoiceCue.allCases.count)
        for cue in VoiceCue.allCases {
            XCTAssertNotNil(VoiceAssistantService.bundledClipURL(for: cue), "Missing bundled voice clip: \(cue.rawValue).m4a")
        }
    }
}
