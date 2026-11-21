import Foundation
import Darwin

/// High-speed Developer & AI Storage Sweeper powered by native macOS `getattrlistbulk`.
/// Discovers stale project build artifacts (node_modules, Rust target, Swift .build, Gradle build,
/// Python .venv, Pods, .next), Xcode & Android SDK bloat, global package manager caches,
/// live Docker/OrbStack reclaimable storage, and local AI model weights / agent caches.
public final class DevAISweeperService: @unchecked Sendable {
    public init() {}

    /// Known developer workspace root folder names auto-detected under `~`.
    public static let defaultWorkspaceCandidates: [String] = [
        "~/working-directory",
        "~/Projects",
        "~/projects",
        "~/Developer",
        "~/developer",
        "~/Code",
        "~/code",
        "~/Workspace",
        "~/workspace",
        "~/dev",
        "~/develop",
        "~/src",
        "~/repos",
        "~/GitHub",
        "~/Documents/Projects",
        "~/Desktop/Projects"
    ]

    /// Resolves unique, existing workspace directories to scan for project build artifacts.
    public func discoverWorkspaceRoots(customPaths: [String] = [], includeDefaults: Bool = true) -> [String] {
        let fm = FileManager.default
        var raw = customPaths.map { FileSystemHelpers.expand($0) }
        if includeDefaults {
            raw.append(contentsOf: Self.defaultWorkspaceCandidates.map { FileSystemHelpers.expand($0) })
        }

        var resolved: [String] = []
        var seen = Set<String>()
        for path in raw {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let std = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
            if seen.insert(std).inserted {
                resolved.append(std)
            }
        }
        // Remove nested roots if an ancestor root is already included (prevents duplicate hits)
        return resolved.filter { candidate in
            !resolved.contains { other in
                other != candidate && candidate.hasPrefix(other + "/")
            }
        }
    }

    // MARK: - Full Multi-Category Scan

    public func scanAll(
        settings: RCleanerSettings,
        customWorkspaces: [String]? = nil,
        includeDefaultWorkspaces: Bool = true,
        includeSystemCategories: Bool = true,
        staleDaysThreshold: Int? = nil,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> DevAISweeperScanResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        let threshold = staleDaysThreshold ?? settings.devStaleDaysThreshold
        let workspaces = discoverWorkspaceRoots(
            customPaths: customWorkspaces ?? settings.devCustomWorkspacePaths,
            includeDefaults: includeDefaultWorkspaces
        )

        var result = DevAISweeperScanResult()
        result.scannedWorkspaces = workspaces

        progress("Scanning developer workspaces for build artifacts...", 0.08)
        let projectItems = await scanProjectArtifacts(
            workspaces: workspaces,
            staleDaysThreshold: threshold,
            settings: settings
        ) { label, pct in
            progress(label, 0.08 + pct * 0.44)
        }
        if Task.isCancelled { return result }

        var xcodeItems: [DevAIArtifactItem] = []
        var pkgItems: [DevAIArtifactItem] = []
        var dockerItems: [DevAIArtifactItem] = []
        var aiItems: [DevAIArtifactItem] = []

        if includeSystemCategories {
            progress("Scanning Xcode, Simulators & Android SDK caches...", 0.56)
            xcodeItems = scanXcodeAndMobile(settings: settings)
            if Task.isCancelled { return result }

            progress("Scanning npm, pnpm, Cargo, Gradle, Go & Homebrew caches...", 0.70)
            pkgItems = scanPackageManagerCaches(settings: settings)
            if Task.isCancelled { return result }

            progress("Checking Docker & container runtimes...", 0.82)
            let (dItems, dockerFound, dockerNote) = scanDockerRuntimes(settings: settings)
            dockerItems = dItems
            result.dockerDetected = dockerFound
            result.dockerStatusNote = dockerNote
            if Task.isCancelled { return result }

            progress("Scanning local AI models & agent caches...", 0.90)
            aiItems = scanAIModelsAndCaches(settings: settings)
            if Task.isCancelled { return result }
        }

        // Deduplicate by canonical path across all categories (keeps first/highest-specificity match)
        var seenPaths = Set<String>()
        var combined: [DevAIArtifactItem] = []
        for item in (projectItems + xcodeItems + pkgItems + dockerItems + aiItems) {
            let key: String
            switch item.actionKind {
            case .dockerPrune(_, let args):
                key = "docker:" + args.joined(separator: ":")
            default:
                key = URL(fileURLWithPath: item.path).standardizedFileURL.path
            }
            if seenPaths.insert(key).inserted {
                combined.append(item)
            }
        }

        combined.sort { $0.sizeBytes > $1.sizeBytes }
        result.items = combined
        result.scanDurationSeconds = CFAbsoluteTimeGetCurrent() - t0
        progress("Dev & AI sweep scan ready", 1.0)
        return result
    }

    // MARK: - 1. Project Build Artifacts (Multi-Core getattrlistbulk with Early Pruning)

    private struct ArtifactRule: Sendable {
        let dirName: String
        let ecosystem: String
        let requiredSiblings: Set<String> // Empty means always match; otherwise at least one sibling must exist
        let rebuildHint: String
        let autoSelectIfStale: Bool
    }

    private static let artifactRules: [String: ArtifactRule] = [
        "node_modules": ArtifactRule(
            dirName: "node_modules",
            ecosystem: "Node.js",
            requiredSiblings: ["package.json"],
            rebuildHint: "Restore with npm / pnpm / yarn install",
            autoSelectIfStale: true
        ),
        ".next": ArtifactRule(
            dirName: ".next",
            ecosystem: "Next.js",
            requiredSiblings: ["package.json"],
            rebuildHint: "Rebuilds automatically on next dev / build",
            autoSelectIfStale: true
        ),
        ".nuxt": ArtifactRule(
            dirName: ".nuxt",
            ecosystem: "Nuxt",
            requiredSiblings: ["package.json"],
            rebuildHint: "Rebuilds automatically on nuxt dev / build",
            autoSelectIfStale: true
        ),
        ".turbo": ArtifactRule(
            dirName: ".turbo",
            ecosystem: "Turborepo",
            requiredSiblings: ["package.json", "turbo.json"],
            rebuildHint: "Local build cache — regenerates on next run",
            autoSelectIfStale: true
        ),
        ".svelte-kit": ArtifactRule(
            dirName: ".svelte-kit",
            ecosystem: "SvelteKit",
            requiredSiblings: ["package.json"],
            rebuildHint: "Rebuilds on next dev / build",
            autoSelectIfStale: true
        ),
        ".angular": ArtifactRule(
            dirName: ".angular",
            ecosystem: "Angular",
            requiredSiblings: ["angular.json", "package.json"],
            rebuildHint: "Angular CLI cache — regenerates automatically",
            autoSelectIfStale: true
        ),
        ".parcel-cache": ArtifactRule(
            dirName: ".parcel-cache",
            ecosystem: "Parcel",
            requiredSiblings: ["package.json"],
            rebuildHint: "Parcel bundler cache — safe to remove",
            autoSelectIfStale: true
        ),
        "target": ArtifactRule(
            dirName: "target",
            ecosystem: "Rust / Maven",
            requiredSiblings: ["Cargo.toml", "pom.xml"],
            rebuildHint: "Rebuilds via cargo build / mvn package",
            autoSelectIfStale: true
        ),
        ".build": ArtifactRule(
            dirName: ".build",
            ecosystem: "SwiftPM",
            requiredSiblings: ["Package.swift"],
            rebuildHint: "Rebuilds via swift build",
            autoSelectIfStale: true
        ),
        "Pods": ArtifactRule(
            dirName: "Pods",
            ecosystem: "CocoaPods",
            requiredSiblings: ["Podfile"],
            rebuildHint: "Restore via pod install",
            autoSelectIfStale: true
        ),
        ".venv": ArtifactRule(
            dirName: ".venv",
            ecosystem: "Python",
            requiredSiblings: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "uv.lock"],
            rebuildHint: "Recreate via python -m venv / uv sync",
            autoSelectIfStale: true
        ),
        "venv": ArtifactRule(
            dirName: "venv",
            ecosystem: "Python",
            requiredSiblings: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile"],
            rebuildHint: "Recreate via python -m venv / pip install",
            autoSelectIfStale: true
        ),
        "__pycache__": ArtifactRule(
            dirName: "__pycache__",
            ecosystem: "Python",
            requiredSiblings: [],
            rebuildHint: "Compiled bytecode cache — regenerates automatically",
            autoSelectIfStale: true
        ),
        ".pytest_cache": ArtifactRule(
            dirName: ".pytest_cache",
            ecosystem: "Python",
            requiredSiblings: [],
            rebuildHint: "Pytest cache — regenerates on next test run",
            autoSelectIfStale: true
        ),
        ".mypy_cache": ArtifactRule(
            dirName: ".mypy_cache",
            ecosystem: "Python",
            requiredSiblings: [],
            rebuildHint: "Mypy type-check cache — regenerates automatically",
            autoSelectIfStale: true
        ),
        "build": ArtifactRule(
            dirName: "build",
            ecosystem: "Gradle / Flutter",
            requiredSiblings: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pubspec.yaml", "CMakeLists.txt"],
            rebuildHint: "Rebuilds via gradle / flutter / cmake",
            autoSelectIfStale: true
        ),
        ".dart_tool": ArtifactRule(
            dirName: ".dart_tool",
            ecosystem: "Flutter / Dart",
            requiredSiblings: ["pubspec.yaml"],
            rebuildHint: "Restore via flutter pub get",
            autoSelectIfStale: true
        ),
        ".gradle": ArtifactRule(
            dirName: ".gradle",
            ecosystem: "Gradle",
            requiredSiblings: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
            rebuildHint: "Project Gradle cache — regenerates on next build",
            autoSelectIfStale: true
        ),
        "vendor": ArtifactRule(
            dirName: "vendor",
            ecosystem: "PHP / Go",
            requiredSiblings: ["composer.json", "go.mod"],
            rebuildHint: "Restore via composer install / go mod vendor",
            autoSelectIfStale: false
        ),
        "dist": ArtifactRule(
            dirName: "dist",
            ecosystem: "Web Build",
            requiredSiblings: ["package.json", "tsconfig.json"],
            rebuildHint: "Build output — unselected by default for safety",
            autoSelectIfStale: false
        )
    ]

    /// Directories we never descend into while hunting for project artifact directories.
    private static let skippedTraversalDirs: Set<String> = [
        ".git", ".hg", ".svn", ".Trash", "Library", ".Spotlight-V100", ".fseventsd",
        "__MACOSX", ".DS_Store", ".idea", ".vscode", ".fleet"
    ]

    private struct ArtifactCandidate: Sendable {
        let rule: ArtifactRule
        let artifactPath: String
        let parentPath: String
        let rootDev: dev_t
        let siblingNames: Set<String>
    }

    private func scanProjectArtifacts(
        workspaces: [String],
        staleDaysThreshold: Int,
        settings: RCleanerSettings,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> [DevAIArtifactItem] {
        guard !workspaces.isEmpty else { return [] }

        // Phase A: Fast pruned directory discovery (skips descending into matched artifacts & .git!)
        var candidates: [ArtifactCandidate] = []
        let maxSearchDepth = 7

        for (idx, root) in workspaces.enumerated() {
            if Task.isCancelled { break }
            let rootName = URL(fileURLWithPath: root).lastPathComponent
            progress("Indexing \(rootName)...", Double(idx) / Double(max(1, workspaces.count)) * 0.35)

            var rootSt = stat()
            guard lstat(root, &rootSt) == 0 else { continue }
            let rootDev = rootSt.st_dev

            var stack: [(path: String, depth: Int)] = [(root, 0)]
            stack.reserveCapacity(1024)

            while let current = stack.popLast() {
                if Task.isCancelled { break }
                if current.depth > maxSearchDepth { continue }

                let entries = FileSystemHelpers.readDirectoryBulk(atPath: current.path)
                if entries.isEmpty { continue }

                var siblingNames = Set<String>()
                siblingNames.reserveCapacity(entries.count)
                for e in entries { siblingNames.insert(e.name) }

                let prefix = current.path == "/" ? "/" : (current.path + "/")

                for entry in entries {
                    guard entry.isDirectory, !entry.isSymlink, entry.devID == rootDev else { continue }
                    if Self.skippedTraversalDirs.contains(entry.name) { continue }
                    // Never descend inside macOS app/framework/xcode bundles while hunting project artifacts
                    if entry.name.hasSuffix(".app") || entry.name.hasSuffix(".framework") || entry.name.hasSuffix(".xcarchive") || entry.name.hasSuffix(".photoslibrary") {
                        continue
                    }

                    let childPath = prefix + entry.name
                    if FileSystemHelpers.isIgnored(path: childPath, category: .devAISweeper, settings: settings) {
                        continue
                    }

                    if let rule = Self.artifactRules[entry.name] {
                        let matchesMarker = rule.requiredSiblings.isEmpty || !rule.requiredSiblings.isDisjoint(with: siblingNames)
                        if matchesMarker {
                            candidates.append(ArtifactCandidate(
                                rule: rule,
                                artifactPath: childPath,
                                parentPath: current.path,
                                rootDev: rootDev,
                                siblingNames: siblingNames
                            ))
                            // CRITICAL: Prune! Do NOT descend inside node_modules / target / .build / .venv!
                            continue
                        }
                    }

                    // Skip other hidden dot-dirs unless explicitly a known rule target
                    if entry.name.hasPrefix(".") { continue }

                    if current.depth < maxSearchDepth {
                        stack.append((childPath, current.depth + 1))
                    }
                }
            }
        }

        guard !candidates.isEmpty else { return [] }

        // Phase B: Measure all discovered artifact directories in parallel across CPU cores
        let totalCount = candidates.count
        let maxWorkers = min(10, max(4, ProcessInfo.processInfo.activeProcessorCount))
        let now = Date()
        let minArtifactBytes: Int64 = 1 * 1024 * 1024 // 1 MB threshold keeps results meaningful

        var measuredItems: [DevAIArtifactItem] = []
        measuredItems.reserveCapacity(totalCount)

        await withTaskGroup(of: DevAIArtifactItem?.self) { group in
            var active = 0
            var completed = 0
            var lastReport = CFAbsoluteTimeGetCurrent()

            for candidate in candidates {
                if Task.isCancelled { break }
                if active >= maxWorkers {
                    if let finished = await group.next() {
                        if let item = finished { measuredItems.append(item) }
                        completed += 1
                        let t = CFAbsoluteTimeGetCurrent()
                        if t - lastReport >= 0.15 {
                            lastReport = t
                            progress(
                                "Measuring \(completed)/\(totalCount) build artifacts...",
                                0.35 + (Double(completed) / Double(totalCount)) * 0.65
                            )
                        }
                    }
                    active -= 1
                }

                active += 1
                group.addTask(priority: .userInitiated) {
                    if Task.isCancelled { return nil }
                    let (bytes, fileCount) = FileSystemHelpers.bulkMeasureSubtree(
                        atPath: candidate.artifactPath,
                        rootDev: candidate.rootDev,
                        maxFiles: 0
                    )
                    guard bytes >= minArtifactBytes else { return nil }

                    let ageDays = Self.projectActivityAgeDays(
                        parentPath: candidate.parentPath,
                        artifactPath: candidate.artifactPath,
                        now: now
                    )
                    let isStale = ageDays >= staleDaysThreshold
                    let ecosystem = Self.refineEcosystem(rule: candidate.rule, siblings: candidate.siblingNames)
                    let projectName = Self.readableProjectName(for: candidate.parentPath)
                    let safeSelect = candidate.rule.autoSelectIfStale && isStale

                    let badge: String
                    if isStale {
                        badge = "Stale • \(ageDays)d"
                    } else if ageDays == 0 {
                        badge = "Active • Today"
                    } else {
                        badge = "Active • \(ageDays)d"
                    }

                    return DevAIArtifactItem(
                        name: "\(projectName) / \(candidate.rule.dirName)",
                        projectName: projectName,
                        ecosystem: ecosystem,
                        category: .projectArtifacts,
                        path: candidate.artifactPath,
                        sizeBytes: bytes,
                        itemCount: fileCount,
                        ageDays: ageDays,
                        rebuildHint: candidate.rule.rebuildHint,
                        badge: badge,
                        isSafeAutoSelect: safeSelect,
                        isSelected: safeSelect,
                        actionKind: .filesystemPath
                    )
                }
            }

            while let finished = await group.next() {
                if let item = finished { measuredItems.append(item) }
            }
        }

        return measuredItems.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static let genericSubmoduleNames: Set<String> = [
        "app", "android", "ios", "macos", "web", "frontend", "backend",
        "client", "server", "mobile", "api", "core", "packages", "apps", "src"
    ]

    private static func readableProjectName(for parentPath: String) -> String {
        let parentURL = URL(fileURLWithPath: parentPath)
        let leaf = parentURL.lastPathComponent
        if genericSubmoduleNames.contains(leaf.lowercased()) {
            let grand = parentURL.deletingLastPathComponent().lastPathComponent
            if !grand.isEmpty && grand != "/" {
                if genericSubmoduleNames.contains(grand.lowercased()) {
                    let greatGrand = parentURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                    if !greatGrand.isEmpty && greatGrand != "/" {
                        return "\(greatGrand)/\(grand)/\(leaf)"
                    }
                }
                return "\(grand)/\(leaf)"
            }
        }
        return leaf
    }

    private static func refineEcosystem(rule: ArtifactRule, siblings: Set<String>) -> String {
        if rule.dirName == "target" {
            return siblings.contains("Cargo.toml") ? "Rust" : "Maven"
        }
        if rule.dirName == "build" {
            if siblings.contains("pubspec.yaml") { return "Flutter" }
            if siblings.contains("CMakeLists.txt") { return "CMake" }
            return "Gradle"
        }
        if rule.dirName == "vendor" {
            return siblings.contains("go.mod") ? "Go" : "PHP"
        }
        return rule.ecosystem
    }

    /// Computes how many days ago the project was last touched using git index, manifests, and artifact mtime.
    /// Picks the MOST RECENT modification so active projects are never misclassified as stale.
    private static func projectActivityAgeDays(parentPath: String, artifactPath: String, now: Date) -> Int {
        let probes = [
            "\(parentPath)/.git/index",
            "\(parentPath)/.git/HEAD",
            "\(parentPath)/package.json",
            "\(parentPath)/Cargo.toml",
            "\(parentPath)/Package.swift",
            "\(parentPath)/pubspec.yaml",
            "\(parentPath)/pyproject.toml",
            "\(parentPath)/build.gradle",
            "\(parentPath)/build.gradle.kts",
            parentPath,
            artifactPath
        ]
        var latestMtime: TimeInterval = 0
        var st = stat()
        for probe in probes {
            if lstat(probe, &st) == 0 {
                let mtime = TimeInterval(st.st_mtimespec.tv_sec)
                if mtime > latestMtime { latestMtime = mtime }
            }
        }
        guard latestMtime > 0 else { return 0 }
        let days = Int(max(0, now.timeIntervalSince1970 - latestMtime) / 86_400.0)
        return days
    }

    // MARK: - 2. Xcode, Simulators & Android Mobile SDKs

    private func scanXcodeAndMobile(settings: RCleanerSettings) -> [DevAIArtifactItem] {
        let fm = FileManager.default
        var items: [DevAIArtifactItem] = []

        // A. Direct child directories of multi-project Xcode folders
        let childTargets: [(rawDir: String, ecosystem: String, hint: String, autoSelect: Bool, minBytes: Int64)] = [
            ("~/Library/Developer/Xcode/DerivedData", "Xcode", "Intermediate build files — Xcode recreates automatically", true, 5 * 1024 * 1024),
            ("~/Library/Developer/Xcode/iOS DeviceSupport", "Xcode iOS", "Old iOS debug symbols — redownloads when device connects", true, 20 * 1024 * 1024),
            ("~/Library/Developer/Xcode/watchOS DeviceSupport", "Xcode watchOS", "Old watchOS debug symbols", true, 20 * 1024 * 1024),
            ("~/Library/Developer/Xcode/tvOS DeviceSupport", "Xcode tvOS", "Old tvOS debug symbols", true, 20 * 1024 * 1024),
            ("~/Library/Developer/Xcode/visionOS DeviceSupport", "Xcode visionOS", "Old visionOS debug symbols", true, 20 * 1024 * 1024),
            ("~/Library/Developer/Xcode/Archives", "Xcode Archive", "Release .xcarchive bundles — unselected to preserve dSYMs", false, 10 * 1024 * 1024),
            ("~/.android/avd", "Android AVD", "Android Virtual Device disk image — recreate in Android Studio", false, 20 * 1024 * 1024),
            ("~/Library/Android/sdk/system-images", "Android SDK", "Android emulator OS system images", false, 50 * 1024 * 1024)
        ]

        for target in childTargets {
            let root = FileSystemHelpers.expand(target.rawDir)
            guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for child in children where !child.hasPrefix(".") {
                let full = (root as NSString).appendingPathComponent(child)
                if FileSystemHelpers.isIgnored(path: full, category: .devAISweeper, settings: settings) { continue }
                let (bytes, count) = FileSystemHelpers.bulkMeasureSubtree(atPath: full, rootDev: nil, maxFiles: 0)
                guard bytes >= target.minBytes else { continue }
                let age = Self.pathAgeDays(full)
                items.append(DevAIArtifactItem(
                    name: child,
                    projectName: target.ecosystem,
                    ecosystem: target.ecosystem,
                    category: .xcodeMobile,
                    path: full,
                    sizeBytes: bytes,
                    itemCount: count,
                    ageDays: age,
                    rebuildHint: target.hint,
                    badge: target.autoSelect ? "Safe Cache" : "Manual Review",
                    isSafeAutoSelect: target.autoSelect,
                    isSelected: target.autoSelect,
                    actionKind: .filesystemPath
                ))
            }
        }

        // B. Whole-directory mobile caches
        let wholeTargets: [(name: String, rawPath: String, ecosystem: String, hint: String, autoSelect: Bool)] = [
            ("Xcode CoreSimulator Caches", "~/Library/Developer/CoreSimulator/Caches", "Xcode Sim", "Simulator dyld caches — regenerates on launch", true),
            ("Xcode App Caches", "~/Library/Caches/com.apple.dt.Xcode", "Xcode", "Xcode download & documentation caches", true),
            ("Xcode Previews Caches", "~/Library/Developer/Xcode/UserData/Previews", "Xcode", "SwiftUI canvas preview containers", true),
            ("Android Build Cache", "~/.android/build-cache", "Android", "AGP build cache — regenerates automatically", true),
            ("Android General Cache", "~/.android/cache", "Android", "Android SDK temporary cache", true),
            ("CoreSimulator Devices", "~/Library/Developer/CoreSimulator/Devices", "Xcode Sim", "All simulator data — unselected to keep active simulators", false)
        ]

        for target in wholeTargets {
            let full = FileSystemHelpers.expand(target.rawPath)
            guard fm.fileExists(atPath: full),
                  !FileSystemHelpers.isIgnored(path: full, category: .devAISweeper, settings: settings) else { continue }
            let (bytes, count) = FileSystemHelpers.bulkMeasureSubtree(atPath: full, rootDev: nil, maxFiles: 0)
            guard bytes >= 5 * 1024 * 1024 else { continue }
            items.append(DevAIArtifactItem(
                name: target.name,
                projectName: target.ecosystem,
                ecosystem: target.ecosystem,
                category: .xcodeMobile,
                path: full,
                sizeBytes: bytes,
                itemCount: count,
                ageDays: Self.pathAgeDays(full),
                rebuildHint: target.hint,
                badge: target.autoSelect ? "Safe Cache" : "Manual Review",
                isSafeAutoSelect: target.autoSelect,
                isSelected: target.autoSelect,
                actionKind: .filesystemPath
            ))
        }

        return items
    }

    // MARK: - 3. Global Package Manager Caches & Toolchains

    private func scanPackageManagerCaches(settings: RCleanerSettings) -> [DevAIArtifactItem] {
        let fm = FileManager.default
        let targets: [(name: String, rawPath: String, ecosystem: String, hint: String, autoSelect: Bool)] = [
            ("npm Package Cache", "~/.npm/_cacache", "npm", "Re-downloads packages on demand", true),
            ("pnpm Global Store", "~/Library/pnpm/store", "pnpm", "Content-addressable store — unselected to preserve hard-linked repos", false),
            ("pnpm Store (~/.pnpm-store)", "~/.pnpm-store", "pnpm", "Content-addressable store — unselected to preserve hard-linked repos", false),
            ("pnpm Store (~/.local/share)", "~/.local/share/pnpm/store", "pnpm", "Content-addressable store — unselected to preserve hard-linked repos", false),
            ("Yarn Cache", "~/Library/Caches/Yarn", "Yarn", "Yarn global download cache", true),
            ("Bun Install Cache", "~/.bun/install/cache", "Bun", "Bun package download cache", true),
            ("Gradle Build Caches", "~/.gradle/caches", "Gradle", "Re-downloads JARs & Gradle caches on next build", true),
            ("Gradle Wrapper Distributions", "~/.gradle/wrapper/dists", "Gradle", "Cached Gradle runtime zips", true),
            ("Maven Local Repository", "~/.m2/repository", "Maven", "Local Maven JAR repository — unselected by default", false),
            ("Cargo Registry Cache", "~/.cargo/registry/cache", "Rust", "Downloaded .crate tarballs — safe to clean", true),
            ("Cargo Registry Sources", "~/.cargo/registry/src", "Rust", "Unpacked crate sources — re-extracted on cargo build", true),
            ("Cargo Git Checkouts", "~/.cargo/git", "Rust", "Cached git dependencies for Cargo", true),
            ("Go Build Cache", "~/Library/Caches/go-build", "Go", "Compiled Go object cache — regenerates on go build", true),
            ("Go Module Download Cache", "~/go/pkg/mod/cache", "Go", "Downloaded Go module zip cache", true),
            ("Homebrew Download Cache", "~/Library/Caches/Homebrew", "Homebrew", "Downloaded bottle tarballs — safe to purge", true),
            ("CocoaPods Cache", "~/Library/Caches/CocoaPods", "CocoaPods", "Cached podspecs and archives", true),
            ("SwiftPM Cache", "~/Library/Caches/org.swift.swiftpm", "SwiftPM", "Swift Package Manager repository cache", true),
            ("pip Cache", "~/Library/Caches/pip", "Python", "Downloaded Python wheels and sdists", true),
            ("uv Package Cache", "~/.cache/uv", "Python uv", "Fast uv wheel & archive cache", true),
            ("Poetry Cache", "~/Library/Caches/pypoetry", "Python", "Poetry artifact download cache", true),
            ("Flutter / Dart Pub Cache", "~/.pub-cache", "Flutter", "Global Dart package cache — unselected by default", false),
            ("Rustup Toolchains", "~/.rustup/toolchains", "Rust", "Installed Rust toolchains — review before removing", false)
        ]

        var items: [DevAIArtifactItem] = []
        for t in targets {
            let full = FileSystemHelpers.expand(t.rawPath)
            guard fm.fileExists(atPath: full),
                  !FileSystemHelpers.isIgnored(path: full, category: .devAISweeper, settings: settings) else { continue }
            let (bytes, count) = FileSystemHelpers.bulkMeasureSubtree(atPath: full, rootDev: nil, maxFiles: 0)
            guard bytes >= 2 * 1024 * 1024 else { continue }
            items.append(DevAIArtifactItem(
                name: t.name,
                projectName: t.ecosystem,
                ecosystem: t.ecosystem,
                category: .packageCaches,
                path: full,
                sizeBytes: bytes,
                itemCount: count,
                ageDays: Self.pathAgeDays(full),
                rebuildHint: t.hint,
                badge: t.autoSelect ? "Safe Cache" : "Manual Review",
                isSafeAutoSelect: t.autoSelect,
                isSelected: t.autoSelect,
                actionKind: .filesystemPath
            ))
        }
        return items
    }

    // MARK: - 4. Docker & Container Runtimes

    private func scanDockerRuntimes(settings: RCleanerSettings) -> (items: [DevAIArtifactItem], detected: Bool, note: String?) {
        let fm = FileManager.default
        let dockerPaths = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            FileSystemHelpers.expand("~/.orbstack/bin/docker")
        ]

        guard let dockerBin = dockerPaths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return ([], false, nil)
        }

        let df = FileSystemHelpers.runProcess(dockerBin, arguments: ["system", "df", "--format", "{{json .}}"], timeout: 5)
        guard df.exitCode == 0 else {
            return ([], true, "Docker CLI found, but daemon is currently stopped.")
        }

        var items: [DevAIArtifactItem] = []
        let lines = df.stdout.split(separator: "\n").map(String.init)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["Type"] as? String else { continue }

            let reclaimRaw = (obj["Reclaimable"] as? String) ?? "0B"
            let totalRaw = (obj["Size"] as? String) ?? "0B"
            let reclaimBytes = Self.parseDockerSize(reclaimRaw)
            guard reclaimBytes >= 1024 * 1024 else { continue }

            let lower = type.lowercased()
            if lower.contains("build cache") {
                items.append(DevAIArtifactItem(
                    name: "Docker Build Cache",
                    projectName: "Docker",
                    ecosystem: "Docker",
                    category: .dockerContainers,
                    path: "docker builder prune -af",
                    sizeBytes: reclaimBytes,
                    rebuildHint: "Total: \(totalRaw) • Runs docker builder prune -af",
                    badge: "Docker CLI",
                    isSafeAutoSelect: true,
                    isSelected: true,
                    actionKind: .dockerPrune(binaryPath: dockerBin, arguments: ["builder", "prune", "-a", "-f"])
                ))
            } else if lower.contains("images") {
                items.append(DevAIArtifactItem(
                    name: "Unused Docker Images",
                    projectName: "Docker",
                    ecosystem: "Docker",
                    category: .dockerContainers,
                    path: "docker image prune -af",
                    sizeBytes: reclaimBytes,
                    rebuildHint: "Total: \(totalRaw) • Removes images not used by active containers",
                    badge: "Docker CLI",
                    isSafeAutoSelect: false,
                    isSelected: false,
                    actionKind: .dockerPrune(binaryPath: dockerBin, arguments: ["image", "prune", "-a", "-f"])
                ))
            } else if lower.contains("containers") {
                items.append(DevAIArtifactItem(
                    name: "Stopped Docker Containers",
                    projectName: "Docker",
                    ecosystem: "Docker",
                    category: .dockerContainers,
                    path: "docker container prune -f",
                    sizeBytes: reclaimBytes,
                    rebuildHint: "Total: \(totalRaw) • Removes exited containers",
                    badge: "Docker CLI",
                    isSafeAutoSelect: true,
                    isSelected: true,
                    actionKind: .dockerPrune(binaryPath: dockerBin, arguments: ["container", "prune", "-f"])
                ))
            } else if lower.contains("volumes") {
                items.append(DevAIArtifactItem(
                    name: "Unused Docker Volumes",
                    projectName: "Docker",
                    ecosystem: "Docker",
                    category: .dockerContainers,
                    path: "docker volume prune -f",
                    sizeBytes: reclaimBytes,
                    rebuildHint: "Total: \(totalRaw) • Unselected by default to protect DB data",
                    badge: "Caution",
                    isSafeAutoSelect: false,
                    isSelected: false,
                    actionKind: .dockerPrune(binaryPath: dockerBin, arguments: ["volume", "prune", "-f"])
                ))
            }
        }

        return (items, true, items.isEmpty ? "Docker daemon is running with minimal reclaimable cache." : nil)
    }

    /// Parses Docker human-readable sizes like `"12.4GB (85%)"`, `"482.1MB"`, `"912kB"`.
    public static func parseDockerSize(_ raw: String) -> Int64 {
        let token = raw.split(separator: " ").first.map(String.init) ?? raw
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var numStr = ""
        var unitStr = ""
        for ch in trimmed {
            if ch.isNumber || ch == "." {
                numStr.append(ch)
            } else {
                unitStr.append(ch)
            }
        }
        guard let value = Double(numStr) else { return 0 }
        switch unitStr.uppercased() {
        case "TB", "TIB": return Int64(value * 1_000_000_000_000)
        case "GB", "GIB": return Int64(value * 1_000_000_000)
        case "MB", "MIB": return Int64(value * 1_000_000)
        case "KB", "KIB": return Int64(value * 1_000)
        case "B", "": return Int64(value)
        default: return 0
        }
    }

    // MARK: - 5. Local AI Model Weights & Coding Agent Caches

    private func scanAIModelsAndCaches(settings: RCleanerSettings) -> [DevAIArtifactItem] {
        let fm = FileManager.default
        let totalRAM = Int64(ProcessInfo.processInfo.physicalMemory)
        var items: [DevAIArtifactItem] = []

        // A. Safe AI Coding Agent & IDE caches (NEVER deletes user prompts, settings, or auth)
        let agentCaches: [(name: String, rawPath: String, ecosystem: String, hint: String)] = [
            ("Cursor GPU & Code Cache", "~/Library/Application Support/Cursor/Cache", "Cursor", "Electron HTTP & script cache — regenerates automatically"),
            ("Cursor CachedData", "~/Library/Application Support/Cursor/CachedData", "Cursor", "V8 bytecode cache — safe to clean"),
            ("VS Code Cache", "~/Library/Application Support/Code/Cache", "VS Code", "Electron cache — safe to clean"),
            ("VS Code CachedData", "~/Library/Application Support/Code/CachedData", "VS Code", "V8 bytecode cache — safe to clean"),
            ("Claude Desktop Cache", "~/Library/Application Support/Claude/Cache", "Claude", "Claude Desktop web cache — preserves conversations"),
            ("Claude Code Cache", "~/Library/Application Support/Claude/Code Cache", "Claude", "V8 script cache — safe to clean"),
            ("Gemini Temp Scratch", "~/.gemini/tmp", "Gemini", "Temporary workspace files — preserves settings & memory"),
            ("Antigravity Browser Recordings", "~/.gemini/antigravity/browser_recordings", "Gemini", "Archived browser automation recordings"),
            ("PyTorch Hub Cache", "~/.cache/torch", "PyTorch", "Downloaded PyTorch model checkpoints"),
            ("Whisper Model Cache", "~/.cache/whisper", "Whisper", "Downloaded local speech recognition weights"),
            ("Apple MLX Cache", "~/.cache/mlx", "MLX", "Apple Silicon MLX model cache")
        ]

        for cache in agentCaches {
            let full = FileSystemHelpers.expand(cache.rawPath)
            guard fm.fileExists(atPath: full),
                  !FileSystemHelpers.isIgnored(path: full, category: .devAISweeper, settings: settings) else { continue }
            let (bytes, count) = FileSystemHelpers.bulkMeasureSubtree(atPath: full, rootDev: nil, maxFiles: 0)
            guard bytes >= 2 * 1024 * 1024 else { continue }
            let isWeight = cache.ecosystem == "PyTorch" || cache.ecosystem == "Whisper" || cache.ecosystem == "MLX"
            items.append(DevAIArtifactItem(
                name: cache.name,
                projectName: cache.ecosystem,
                ecosystem: cache.ecosystem,
                category: .aiModelsAndCaches,
                path: full,
                sizeBytes: bytes,
                itemCount: count,
                ageDays: Self.pathAgeDays(full),
                rebuildHint: cache.hint,
                badge: isWeight ? "AI Cache" : "Safe Cache",
                isSafeAutoSelect: !isWeight,
                isSelected: !isWeight,
                actionKind: .filesystemPath
            ))
        }

        // B. Ollama local LLM models (manifest-aware, shared-blob safe!)
        items.append(contentsOf: scanOllamaModels(settings: settings, totalRAM: totalRAM))

        // C. LM Studio, HuggingFace Hub, Jan, GPT4All model directories (individual models, unselected by default)
        let modelRoots: [(engine: String, rawPath: String)] = [
            ("LM Studio", "~/.lmstudio/models"),
            ("LM Studio", "~/.cache/lm-studio/models"),
            ("HuggingFace", "~/.cache/huggingface/hub"),
            ("Jan AI", "~/jan/models"),
            ("GPT4All", "~/Library/Application Support/nomic.ai/GPT4All")
        ]
        for root in modelRoots {
            let fullRoot = FileSystemHelpers.expand(root.rawPath)
            guard let children = try? fm.contentsOfDirectory(atPath: fullRoot) else { continue }
            for child in children where !child.hasPrefix(".") {
                let full = (fullRoot as NSString).appendingPathComponent(child)
                if FileSystemHelpers.isIgnored(path: full, category: .devAISweeper, settings: settings) { continue }
                let (bytes, count) = FileSystemHelpers.bulkMeasureSubtree(atPath: full, rootDev: nil, maxFiles: 0)
                guard bytes >= 10 * 1024 * 1024 else { continue }
                let fitsRAM = Double(bytes) * 1.2 < Double(totalRAM)
                let cleanName = child.replacingOccurrences(of: "models--", with: "").replacingOccurrences(of: "--", with: "/")
                items.append(DevAIArtifactItem(
                    name: cleanName,
                    projectName: root.engine,
                    ecosystem: root.engine,
                    category: .aiModelsAndCaches,
                    path: full,
                    sizeBytes: bytes,
                    itemCount: count,
                    ageDays: Self.pathAgeDays(full),
                    rebuildHint: "Local \(root.engine) weights — unselected by default",
                    badge: fitsRAM ? "Model • Fits RAM" : "Exceeds RAM",
                    isSafeAutoSelect: false,
                    isSelected: false,
                    actionKind: .filesystemPath
                ))
            }
        }

        return items
    }

    private func scanOllamaModels(settings: RCleanerSettings, totalRAM: Int64) -> [DevAIArtifactItem] {
        let fm = FileManager.default
        let manifestRoots = [
            FileSystemHelpers.expand("~/.ollama/models/manifests"),
            FileSystemHelpers.expand("~/.ollama/models/manifests-v2")
        ]
        let blobsRoot = FileSystemHelpers.expand("~/.ollama/models/blobs")

        var models: [DevAIArtifactItem] = []
        var referencedBlobs = Set<String>()

        for manifestsRoot in manifestRoots where fm.fileExists(atPath: manifestsRoot) {
            guard let en = fm.enumerator(at: URL(fileURLWithPath: manifestsRoot), includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let fileURL as URL in en {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if FileSystemHelpers.isIgnored(path: fileURL.path, category: .devAISweeper, settings: settings) { continue }
                guard let data = try? Data(contentsOf: fileURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let layers = json["layers"] as? [[String: Any]] else { continue }

                let tag = fileURL.lastPathComponent
                let modelName = fileURL.deletingLastPathComponent().lastPathComponent
                let displayName = "\(modelName):\(tag)"

                var totalBytes: Int64 = 0
                var blobPaths: [String] = []
                for layer in layers {
                    if let digest = layer["digest"] as? String {
                        let blobPath = "\(blobsRoot)/\(digest.replacingOccurrences(of: ":", with: "-"))"
                        if fm.fileExists(atPath: blobPath) {
                            blobPaths.append(blobPath)
                            referencedBlobs.insert(blobPath)
                        }
                    }
                    if let s = layer["size"] as? Int64 {
                        totalBytes += s
                    } else if let s = layer["size"] as? NSNumber {
                        totalBytes += s.int64Value
                    }
                }
                if let config = json["config"] as? [String: Any], let digest = config["digest"] as? String {
                    referencedBlobs.insert("\(blobsRoot)/\(digest.replacingOccurrences(of: ":", with: "-"))")
                }
                guard totalBytes >= 1024 * 1024 else { continue }

                let fitsRAM = Double(totalBytes) * 1.2 < Double(totalRAM)
                models.append(DevAIArtifactItem(
                    name: displayName,
                    projectName: "Ollama",
                    ecosystem: "Ollama",
                    category: .aiModelsAndCaches,
                    path: fileURL.path,
                    sizeBytes: totalBytes,
                    itemCount: blobPaths.count,
                    ageDays: Self.pathAgeDays(fileURL.path),
                    rebuildHint: "Redownload anytime via ollama pull \(displayName)",
                    badge: fitsRAM ? "Ollama • Fits RAM" : "Exceeds RAM",
                    isSafeAutoSelect: false,
                    isSelected: false,
                    actionKind: .ollamaModel(blobPaths: blobPaths)
                ))
            }
        }

        // Also detect unreferenced Ollama model blobs (e.g. orphaned weights after manifest removal/migration)
        if fm.fileExists(atPath: blobsRoot),
           !FileSystemHelpers.isIgnored(path: blobsRoot, category: .devAISweeper, settings: settings),
           let blobNames = try? fm.contentsOfDirectory(atPath: blobsRoot) {
            var orphanPaths: [String] = []
            var orphanBytes: Int64 = 0
            for name in blobNames where !name.hasPrefix(".") {
                let full = (blobsRoot as NSString).appendingPathComponent(name)
                if referencedBlobs.contains(full) { continue }
                let sz = FileSystemHelpers.fileSize(at: URL(fileURLWithPath: full))
                if sz > 0 {
                    orphanBytes += sz
                    orphanPaths.append(full)
                }
            }
            if orphanBytes >= 10 * 1024 * 1024 {
                models.append(DevAIArtifactItem(
                    name: "Ollama Model Blobs (\(orphanPaths.count) unreferenced)",
                    projectName: "Ollama",
                    ecosystem: "Ollama",
                    category: .aiModelsAndCaches,
                    path: blobsRoot,
                    sizeBytes: orphanBytes,
                    itemCount: orphanPaths.count,
                    ageDays: Self.pathAgeDays(blobsRoot),
                    rebuildHint: "Model blobs not linked to an active manifest — review before removing",
                    badge: "Manual Review",
                    isSafeAutoSelect: false,
                    isSelected: false,
                    actionKind: .ollamaModel(blobPaths: orphanPaths)
                ))
            }
        }

        return models
    }

    // MARK: - Cleaning Execution

    public func cleanSelected(
        items: [DevAIArtifactItem],
        moveToTrash: Bool,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async -> CleanupSummary {
        let selected = items.filter(\.isSelected)
        var logs: [CleanupLogEntry] = []
        var freed: Int64 = 0
        var ok = 0
        var fail = 0

        for (index, item) in selected.enumerated() {
            if Task.isCancelled { break }
            let pct = Double(index + 1) / Double(max(1, selected.count))
            progress("Sweeping \(item.name)...", pct)

            switch item.actionKind {
            case .dockerPrune(let binary, let args):
                let res = FileSystemHelpers.runProcess(binary, arguments: args, timeout: 60)
                if res.exitCode == 0 {
                    freed += item.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(
                        moduleName: "Dev & AI Sweeper",
                        itemName: item.name,
                        path: item.path,
                        sizeBytes: item.sizeBytes,
                        status: .cleaned
                    ))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(
                        moduleName: "Dev & AI Sweeper",
                        itemName: item.name,
                        path: item.path,
                        sizeBytes: item.sizeBytes,
                        status: .failed,
                        errorMessage: res.stderr.isEmpty ? "Docker prune failed (exit \(res.exitCode))" : res.stderr
                    ))
                }

            case .ollamaModel(let blobPaths):
                var allOK = true
                // Only remove item.path when it is an individual manifest file (never delete the blobs root directory itself)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue {
                    let mRes = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: false)
                    if !mRes.success { allOK = false }
                }
                let stillReferenced = collectReferencedOllamaBlobs()
                for b in blobPaths where !stillReferenced.contains(b) {
                    let r = FileSystemHelpers.safeRemoveItem(at: b, moveToTrash: false)
                    if !r.success { allOK = false }
                }
                if allOK {
                    freed += item.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(moduleName: "Dev & AI Sweeper", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .cleaned))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(moduleName: "Dev & AI Sweeper", itemName: item.name, path: item.path, sizeBytes: item.sizeBytes, status: .failed, errorMessage: "Could not remove all Ollama model files"))
                }

            case .filesystemPath:
                let res = FileSystemHelpers.safeRemoveItem(at: item.path, moveToTrash: moveToTrash)
                if res.success {
                    freed += item.sizeBytes
                    ok += 1
                    logs.append(CleanupLogEntry(
                        moduleName: "Dev & AI Sweeper",
                        itemName: item.name,
                        path: item.path,
                        sizeBytes: item.sizeBytes,
                        status: .cleaned
                    ))
                } else {
                    fail += 1
                    logs.append(CleanupLogEntry(
                        moduleName: "Dev & AI Sweeper",
                        itemName: item.name,
                        path: item.path,
                        sizeBytes: item.sizeBytes,
                        status: .failed,
                        errorMessage: res.error
                    ))
                }
            }
        }

        return CleanupSummary(
            bytesFreed: freed,
            itemsProcessed: ok,
            itemsFailed: fail,
            logEntries: logs,
            title: ok > 0 ? "Dev & AI Sweep Complete!" : "Sweep Finished",
            subtitle: moveToTrash ? "moved safely to Trash" : "reclaimed immediately from disk"
        )
    }

    // MARK: - Utilities

    private static func pathAgeDays(_ path: String) -> Int {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        let mtime = TimeInterval(st.st_mtimespec.tv_sec)
        return Int(max(0, Date().timeIntervalSince1970 - mtime) / 86_400.0)
    }

    private func collectReferencedOllamaBlobs() -> Set<String> {
        let fm = FileManager.default
        let manifestRoots = [
            FileSystemHelpers.expand("~/.ollama/models/manifests"),
            FileSystemHelpers.expand("~/.ollama/models/manifests-v2")
        ]
        let blobsRoot = FileSystemHelpers.expand("~/.ollama/models/blobs")
        var referenced = Set<String>()
        for manifestsRoot in manifestRoots where fm.fileExists(atPath: manifestsRoot) {
            guard let en = fm.enumerator(at: URL(fileURLWithPath: manifestsRoot), includingPropertiesForKeys: [.isRegularFileKey]) else {
                continue
            }
            for case let fileURL as URL in en {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let data = try? Data(contentsOf: fileURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let layers = json["layers"] as? [[String: Any]] {
                    for layer in layers {
                        if let digest = layer["digest"] as? String {
                            referenced.insert("\(blobsRoot)/\(digest.replacingOccurrences(of: ":", with: "-"))")
                        }
                    }
                }
                if let config = json["config"] as? [String: Any], let digest = config["digest"] as? String {
                    referenced.insert("\(blobsRoot)/\(digest.replacingOccurrences(of: ":", with: "-"))")
                }
            }
        }
        return referenced
    }
}
