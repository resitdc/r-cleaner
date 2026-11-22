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

        // Verify tangential bubble packing guarantees zero overlaps and full canvas containment
        // even with two massive adjacent folders (e.g. 125 GB + 79 GB) plus smaller siblings
        let canvas = CGSize(width: 620, height: 520)
        let sampleSizes: [Int64] = [
            125_000_000_000, 79_100_000_000, 9_000_000_000, 6_400_000_000,
            3_300_000_000, 2_200_000_000, 1_500_000_000, 800_000_000, 400_000_000
        ]
        let packed = SpaceLensBubblePacker.pack(sizes: sampleSizes, in: canvas)
        XCTAssertEqual(packed.count, sampleSizes.count)

        for i in 0..<packed.count {
            let a = packed[i]
            XCTAssertGreaterThanOrEqual(a.center.x - a.radius, 0, "Bubble \(i) clipped left")
            XCTAssertLessThanOrEqual(a.center.x + a.radius, canvas.width, "Bubble \(i) clipped right")
            XCTAssertGreaterThanOrEqual(a.center.y - a.radius, 0, "Bubble \(i) clipped top")
            XCTAssertLessThanOrEqual(a.center.y + a.radius, canvas.height, "Bubble \(i) clipped bottom")
            for j in (i + 1)..<packed.count {
                let b = packed[j]
                let dist = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                XCTAssertGreaterThanOrEqual(dist, a.radius + b.radius - 0.5, "Bubbles \(i) and \(j) overlapped!")
            }
        }
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

    func testAppUpdaterSemVerChecksumsAndReleaseParsing() throws {
        // SemVer comparison edge cases
        XCTAssertTrue(AppUpdaterService.isVersion("v1.2.0", newerThan: "1.1.0"))
        XCTAssertTrue(AppUpdaterService.isVersion("2.0.0", newerThan: "1.9.9"))
        XCTAssertTrue(AppUpdaterService.isVersion("1.2.0", newerThan: "1.2.0-beta.1"))
        XCTAssertFalse(AppUpdaterService.isVersion("v1.1.0", newerThan: "1.1.0"))
        XCTAssertFalse(AppUpdaterService.isVersion("1.0.9", newerThan: "1.1.0"))
        XCTAssertFalse(AppUpdaterService.isVersion("1.2.0-alpha.1", newerThan: "1.2.0"))

        // SHA256SUMS.txt parsing & live file hashing
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("rcleaner-sha-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try Data("hello r-cleaner".utf8).write(to: tempFile)
        let hash = try AppUpdaterService.sha256Hex(ofFileAt: tempFile)
        XCTAssertEqual(hash.count, 64)

        let sumsText = """
        \(hash)  R-Cleaner-1.2.0-universal.app.zip
        0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef *dist/R-Cleaner-1.2.0-universal.dmg
        """
        let parsedSums = AppUpdaterService.parseSHA256Sums(sumsText)
        XCTAssertEqual(parsedSums["R-Cleaner-1.2.0-universal.app.zip"], hash)
        XCTAssertEqual(parsedSums["R-Cleaner-1.2.0-universal.dmg"], "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

        // GitHub Release API payload parsing
        let payload = """
        {
          "tag_name": "v1.2.0",
          "name": "R-Cleaner v1.2.0",
          "body": "Added Dev & AI Sweeper and Automatic GitHub Releases Updater.",
          "html_url": "https://github.com/resitdc/resitdc-mac-cleaner/releases/tag/v1.2.0",
          "published_at": "2026-11-21T10:00:00Z",
          "assets": [
            {
              "name": "R-Cleaner-1.2.0-universal.dmg",
              "size": 7800000,
              "browser_download_url": "https://github.com/resitdc/resitdc-mac-cleaner/releases/download/v1.2.0/R-Cleaner-1.2.0-universal.dmg"
            },
            {
              "name": "R-Cleaner-1.2.0-universal.app.zip",
              "size": 7600000,
              "browser_download_url": "https://github.com/resitdc/resitdc-mac-cleaner/releases/download/v1.2.0/R-Cleaner-1.2.0-universal.app.zip"
            },
            {
              "name": "SHA256SUMS.txt",
              "size": 196,
              "browser_download_url": "https://github.com/resitdc/resitdc-mac-cleaner/releases/download/v1.2.0/SHA256SUMS.txt"
            }
          ]
        }
        """
        let release = try AppUpdaterService().parseReleaseJSON(Data(payload.utf8))
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertEqual(release.zipAssetName, "R-Cleaner-1.2.0-universal.app.zip")
        XCTAssertEqual(release.dmgAssetName, "R-Cleaner-1.2.0-universal.dmg")
        XCTAssertNotNil(release.checksumsURL)
        XCTAssertTrue(release.supportsInPlaceInstall)
    }

    func testClearVoiceCommandIntentParsing() {
        XCTAssertEqual(VoiceCommandParser.parse("Hey Clear, run Smart Care"), .runSmartCare)
        XCTAssertEqual(VoiceCommandParser.parse("Clear free up RAM"), .freeUpRAM)
        XCTAssertEqual(VoiceCommandParser.parse("Clear memory"), .freeUpRAM)
        XCTAssertEqual(VoiceCommandParser.parse("Flush DNS cache"), .flushDNS)
        XCTAssertEqual(VoiceCommandParser.parse("What's eating my CPU?"), .topCPUConsumers)
        XCTAssertEqual(VoiceCommandParser.parse("What is using my memory"), .topMemoryConsumers)
        XCTAssertEqual(VoiceCommandParser.parse("Hey Clear, scan Space Lens on working directory"), .scanSpaceLens(folderHint: "working-directory"))
        XCTAssertEqual(VoiceCommandParser.parse("Scan Space Lens on Downloads"), .scanSpaceLens(folderHint: "Downloads"))
        XCTAssertEqual(VoiceCommandParser.parse("Clean node modules and Docker"), .runDevAISweeper)
        XCTAssertEqual(VoiceCommandParser.parse("Activate screen cleaning mode"), .screenCleaningMode)
        XCTAssertEqual(VoiceCommandParser.parse("Give me a system briefing"), .systemBriefing)
        XCTAssertEqual(VoiceCommandParser.parse("Check for app updates"), .checkUpdates)
        XCTAssertEqual(VoiceCommandParser.parse("Empty the trash"), .emptyTrash)
        XCTAssertEqual(VoiceCommandParser.parse("Stop"), .stopScan)
        XCTAssertEqual(VoiceCommandParser.parse("Mute voice"), .muteVoice)
        XCTAssertEqual(VoiceCommandParser.parse("Open Applications"), .openModule(.applications))
        if case .unknown = VoiceCommandParser.parse("play some jazz music") {
            // expected
        } else {
            XCTFail("Unrelated phrase should resolve to .unknown")
        }
    }

    func testNetworkBandwidthParserAndConfigurableSmartGuardAlerts() {
        // 1. Parse real macOS nettop CSV output
        let sampleNettop = """
        ,bytes_in,bytes_out,
        apsd.349,4677,29835,
        Google Chrome.1204,1048576,262144,
        mDNSResponder.426,1001047,212010,
        """
        let parsed = SystemTelemetryService.parseNettopOutput(sampleNettop)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].name, "Google Chrome")
        XCTAssertEqual(parsed[1].pid, 1204)
        XCTAssertEqual(parsed[1].inBytes, 1_048_576)
        XCTAssertEqual(parsed[1].outBytes, 262_144)

        // 2. Verify configurable Clear Smart Guard thresholds & runaway CPU sustained duration
        let evaluator = ClearSmartGuardEvaluator()
        var settings = RCleanerSettings()
        settings.enableClearSmartAlerts = true
        settings.warnLowDiskSpaceGB = 8
        settings.ramAlertThresholdPercent = 85
        settings.runawayCPUThresholdPercent = 90
        settings.runawayCPUDurationSeconds = 60
        settings.notifyThermalPressure = true
        settings.smartAlertCooldownMinutes = 10

        var snap = SystemTelemetrySnapshot()
        snap.storage.totalBytes = 500_000_000_000
        snap.storage.availableBytes = 6_000_000_000 // 6 GB (< 8 GB threshold!)
        snap.memory.totalBytes = 16_000_000_000
        snap.memory.activeBytes = 14_400_000_000 // 90% (>= 85% threshold!)
        snap.thermal.state = .serious
        snap.topCPUConsumers = [
            ProcessConsumer(id: 9999, name: "RunawayEncoder", cpuPercent: 115.0, memoryBytes: 500_000_000, isNotResponding: false)
        ]

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let r0 = evaluator.evaluate(snapshot: snap, settings: settings, now: t0)
        // At t=0: lowDisk, criticalRAM, thermalPressure fire; runawayCPU must NOT fire yet (needs 60s)
        XCTAssertTrue(r0.newlyTriggered.contains { $0.kind == .lowDisk })
        XCTAssertTrue(r0.newlyTriggered.contains { $0.kind == .criticalRAM })
        XCTAssertTrue(r0.newlyTriggered.contains { $0.kind == .thermalPressure })
        XCTAssertFalse(r0.newlyTriggered.contains { $0.kind == .runawayCPU })

        // At t=30s: still under 60s duration -> runawayCPU still silent, others suppressed by cooldown
        let r30 = evaluator.evaluate(snapshot: snap, settings: settings, now: t0.addingTimeInterval(30))
        XCTAssertTrue(r30.newlyTriggered.isEmpty)

        // At t=65s: runawayCPU crosses 60s sustained duration and fires!
        let r65 = evaluator.evaluate(snapshot: snap, settings: settings, now: t0.addingTimeInterval(65))
        XCTAssertEqual(r65.newlyTriggered.map(\.kind), [.runawayCPU])
        XCTAssertEqual(r65.newlyTriggered.first?.processName, "RunawayEncoder")

        // Raise thresholds above current values -> active alerts clear cleanly
        settings.warnLowDiskSpaceGB = 4
        settings.ramAlertThresholdPercent = 95
        settings.runawayCPUThresholdPercent = 150
        settings.notifyThermalPressure = false
        let rCleared = evaluator.evaluate(snapshot: snap, settings: settings, now: t0.addingTimeInterval(70))
        XCTAssertTrue(rCleared.activeAlerts.isEmpty)
    }

    func testPortKillerLsofParsingAndClassification() {
        let sampleLsof = """
        COMMAND     PID    USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        ControlCe   576 resitdc    8u  IPv4 0xf33b65b18e9e0559      0t0  TCP *:7000 (LISTEN)
        ControlCe   576 resitdc    9u  IPv6 0x8861560ac6a3f81a      0t0  TCP *:7000 (LISTEN)
        postgres    714 resitdc    7u  IPv6 0x511b88ed42624adc      0t0  TCP [::1]:5432 (LISTEN)
        postgres    714 resitdc    8u  IPv4 0x027704f16ffa6004      0t0  TCP 127.0.0.1:5432 (LISTEN)
        ollama      947 resitdc    4u  IPv6 0x1e2efa1b0de637df      0t0  TCP *:11434 (LISTEN)
        node      47561 resitdc   33u  IPv6 0x91c993fcf70c6cab      0t0  TCP [::1]:5173 (LISTEN)
        """
        let sockets = PortKillerService.parseLsofListenTable(sampleLsof)
        // Must deduplicate dual-stack IPv4 + IPv6 listeners on the same (PID, port)
        XCTAssertEqual(sockets.count, 4)

        let pg = sockets.first { $0.port == 5432 }
        XCTAssertNotNil(pg)
        XCTAssertEqual(pg?.pid, 714)
        XCTAssertFalse(pg?.isExposedToLAN == true)

        let ollama = sockets.first { $0.port == 11434 }
        XCTAssertNotNil(ollama)
        XCTAssertTrue(ollama?.isExposedToLAN == true)

        let viteClass = PortKillerService.classifyPort(
            port: 5173,
            processName: "node",
            fullArgs: "node /Users/demo/projects/posme/template/node_modules/.bin/vite",
            cwd: "/Users/demo/projects/posme/template"
        )
        XCTAssertEqual(viteClass.category, .devWebServer)
        XCTAssertTrue(viteClass.frameworkLabel.contains("Vite"))

        let pgClass = PortKillerService.classifyPort(
            port: 5432,
            processName: "postgres",
            fullArgs: "/opt/homebrew/opt/postgresql@18/bin/postgres",
            cwd: "/opt/homebrew/var/postgresql@18"
        )
        XCTAssertEqual(pgClass.category, .databaseCache)
        XCTAssertEqual(pgClass.frameworkLabel, "PostgreSQL")
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

        // Verify all 27 bundled Clear neural voice clips are included inside the app bundle
        XCTAssertEqual(VoiceAssistantService.bundledClipCount, VoiceCue.allCases.count)
        for cue in VoiceCue.allCases {
            XCTAssertNotNil(VoiceAssistantService.bundledClipURL(for: cue), "Missing bundled voice clip: \(cue.rawValue).m4a")
        }
    }
}
