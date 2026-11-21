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
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data(repeating: 0x11, count: 65_536).write(to: subDir.appendingPathComponent("data.bin"))

        let service = SpaceLensService()
        let root = await service.buildTree(at: tempDir, maxDepth: 2) { _, _ in }
        XCTAssertTrue(root.sizeBytes >= 65_536)
        XCTAssertEqual(root.children.first?.name, "BigFolder")
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
