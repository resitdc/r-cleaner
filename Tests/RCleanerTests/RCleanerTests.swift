import XCTest
@testable import RCleaner

final class RCleanerTests: XCTestCase {
    func testByteFormatting() {
        XCTAssertEqual(ByteFormat.string(0), "0 KB")
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
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/System/Library/CoreServices"))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/usr/bin/swift"))
        XCTAssertTrue(FileSystemHelpers.isProtectedSystemPath("/"))
        XCTAssertFalse(FileSystemHelpers.isProtectedSystemPath("/tmp/r-cleaner-test-file"))
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
}
