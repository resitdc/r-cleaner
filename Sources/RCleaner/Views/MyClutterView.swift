import SwiftUI
import AppKit
import ImageIO

public struct MyClutterView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ClutterTab = .duplicates
    @State private var sizeFilter: SizeFilter = .all
    @State private var accessDateFilter: AccessDateFilter = .all
    @State private var kindFilter: String = "All"
    @State private var downloadSourceFilter: String = "All"
    @State private var showAllCopiesWarning: Bool = false
    private let palette = RCleanerTheme.palette(for: .myClutter)

    enum ClutterTab: String, CaseIterable {
        case duplicates = "Duplicates"
        case similarImages = "Similar Images"
        case largeAndOld = "Large & Old Files"
        case downloads = "Downloads"
    }

    enum SizeFilter: String, CaseIterable {
        case all = "All Sizes"
        case huge = "Huge (>500 MB)"
        case average = "Average (100–500 MB)"
        case small = "Small (<100 MB)"
    }

    enum AccessDateFilter: String, CaseIterable {
        case all = "Any Access Date"
        case lastWeek = "Last Week"
        case overWeek = "> 1 Week Ago"
        case overMonth = "> 1 Month Ago"
        case overSixMonths = "> 6 Months Ago"
        case overYear = "> 1 Year Ago"

        func matches(_ date: Date?) -> Bool {
            guard self != .all else { return true }
            guard let date else { return true }
            let age = Date().timeIntervalSince(date)
            switch self {
            case .all: return true
            case .lastWeek: return age <= 7 * 86400
            case .overWeek: return age > 7 * 86400
            case .overMonth: return age > 30 * 86400
            case .overSixMonths: return age > 180 * 86400
            case .overYear: return age > 365 * 86400
            }
        }
    }

    public init() {}

    public var body: some View {
        switch appState.clutterStage {
        case .intro:
            ModuleIntroHero(
                title: "My Clutter",
                subtitle: "Sort through your files and reduce the mess in just a few clicks.",
                iconName: "doc.on.doc.fill",
                palette: palette,
                features: [
                    ("doc.on.doc.fill", "Duplicates", "SHA-256 exact duplicate finder with Smart Selection to keep originals safe."),
                    ("photo.stack.fill", "Similar Images", "Clusters near-identical photos, detects blur flaws, and recommends Best to Keep."),
                    ("externaldrive.fill.badge.timemachine", "Large & Old Files", "Filter space hogs by Size, Access Date, and File Kind."),
                    ("arrow.down.circle.fill", "Downloads", "Tidy up one-time downloaded installers, archives, and documents.")
                ],
                primaryActionTitle: "Scan",
                secondaryActionTitle: "Choose Folder...",
                onPrimaryAction: { appState.startClutterScan(customFolder: nil) },
                onSecondaryAction: { chooseFolderAndScan() }
            )

        case .scanning:
            ScanningProgressView(
                title: "Digging through...",
                subtitle: "Looking for duplicates, similar photos, large files, and downloads.",
                currentPath: appState.clutterStatusText,
                progress: appState.clutterProgress,
                iconName: "doc.on.doc.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            clutterManagerView

        case .cleaning:
            ScanningProgressView(
                title: "Removing files...",
                subtitle: "Moving selected clutter safely to Trash.",
                currentPath: "",
                progress: 0.65,
                iconName: "trash.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.clutterSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: { appState.clutterStage = .intro })
            }
        }
    }

    private func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.startClutterScan(customFolder: url)
        }
    }

    private var clutterManagerView: some View {
        VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "My Clutter",
                backTitle: "Start Over",
                trailingText: appState.clutterCustomFolder?.lastPathComponent ?? "Home Folders"
            ) {
                appState.clutterStage = .intro
            }

            HStack(spacing: 8) {
                ForEach(ClutterTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selectedTab == tab ? palette.primary.opacity(0.85) : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            switch selectedTab {
            case .duplicates: duplicatesView
            case .similarImages: similarImagesView
            case .largeAndOld: largeAndOldView
            case .downloads: downloadsView
            }
        }
    }

    private var duplicatesView: some View {
        let selectedCopies = appState.clutterResult.duplicateGroups.flatMap(\.copies).filter(\.isSelected)
        let selectedBytes = selectedCopies.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 10) {
            if appState.clutterResult.duplicateGroups.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Color(hex: "2ED573"))
                Text("No duplicate files found").font(.title3.bold()).foregroundStyle(.white)
                Spacer()
            } else {
                HStack(spacing: 10) {
                    Text("\(appState.clutterResult.duplicateGroups.count) duplicate sets")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Menu {
                        Button("Select Smartly (Keep Oldest Original)") { applyDuplicateSelection(keepNewest: false) }
                        Button("Keep Newest Copy") { applyDuplicateSelection(keepNewest: true) }
                        Divider()
                        Button("Deselect All") { deselectAllDuplicates() }
                    } label: {
                        Label("Select: Smartly", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 24)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.clutterResult.duplicateGroups.indices, id: \.self) { gIdx in
                            let group = appState.clutterResult.duplicateGroups[gIdx]
                            GlassCard(padding: 14, cornerRadius: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(group.fileName).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                        Text("\(group.copies.count) copies • \(group.fileKind)")
                                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                                        Spacer()
                                        Text(ByteFormat.string(group.singleFileSize) + " each")
                                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.accent)
                                    }
                                    ForEach(appState.clutterResult.duplicateGroups[gIdx].copies.indices, id: \.self) { cIdx in
                                        let copy = appState.clutterResult.duplicateGroups[gIdx].copies[cIdx]
                                        HStack(spacing: 8) {
                                            Toggle("", isOn: $appState.clutterResult.duplicateGroups[gIdx].copies[cIdx].isSelected)
                                                .toggleStyle(.checkbox)
                                                .labelsHidden()
                                            Text(copy.path)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.8))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            if copy.isOriginalRecommended {
                                                Text("Original")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(Color(hex: "2ED573"))
                                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                                    .background(Capsule().fill(Color(hex: "2ED573").opacity(0.2)))
                                            }
                                            Button { FileSystemHelpers.revealInFinder(path: copy.path) } label: {
                                                Image(systemName: "magnifyingglass.circle").foregroundStyle(.white.opacity(0.6))
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                UbiquitousButton(title: "Remove", subtitle: ByteFormat.string(selectedBytes), palette: palette, isDisabled: selectedCopies.isEmpty) {
                    let anyGroupAllSelected = appState.clutterResult.duplicateGroups.contains { !$0.copies.isEmpty && $0.copies.allSatisfy(\.isSelected) }
                    if anyGroupAllSelected {
                        showAllCopiesWarning = true
                    } else {
                        removeItems(selectedCopies.map { ($0.name, $0.path, $0.sizeBytes) }, isDuplicates: true)
                    }
                }
                .padding(.bottom, 12)
                .alert("Are you sure you want to remove all copies?", isPresented: $showAllCopiesWarning) {
                    Button("Cancel", role: .cancel) {}
                    Button("Remove All Copies", role: .destructive) {
                        removeItems(selectedCopies.map { ($0.name, $0.path, $0.sizeBytes) }, isDuplicates: true)
                    }
                } message: {
                    Text("You have selected every copy in one or more duplicate groups. Removing them will delete all instances of those files.")
                }
            }
        }
    }

    private func applyDuplicateSelection(keepNewest: Bool) {
        for gIdx in appState.clutterResult.duplicateGroups.indices {
            let copies = appState.clutterResult.duplicateGroups[gIdx].copies
            guard copies.count >= 2 else { continue }
            let keepIndex: Int
            if keepNewest {
                keepIndex = copies.indices.max(by: { (copies[$0].modifiedDate ?? .distantPast) < (copies[$1].modifiedDate ?? .distantPast) }) ?? 0
            } else {
                keepIndex = copies.indices.min(by: { (copies[$0].createdDate ?? .distantFuture) < (copies[$1].createdDate ?? .distantFuture) }) ?? 0
            }
            for cIdx in copies.indices {
                appState.clutterResult.duplicateGroups[gIdx].copies[cIdx].isSelected = (cIdx != keepIndex)
                appState.clutterResult.duplicateGroups[gIdx].copies[cIdx].isOriginalRecommended = (cIdx == keepIndex)
            }
        }
    }

    private func deselectAllDuplicates() {
        for gIdx in appState.clutterResult.duplicateGroups.indices {
            for cIdx in appState.clutterResult.duplicateGroups[gIdx].copies.indices {
                appState.clutterResult.duplicateGroups[gIdx].copies[cIdx].isSelected = false
            }
        }
    }

    private var similarImagesView: some View {
        let selectedImgs = appState.clutterResult.similarImageGroups.flatMap(\.images).filter(\.isSelected)
        let selectedBytes = selectedImgs.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 10) {
            if appState.clutterResult.similarImageGroups.isEmpty {
                Spacer()
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 52)).foregroundStyle(palette.accent)
                Text("No similar images detected").font(.title3.bold()).foregroundStyle(.white)
                Text("Try choosing your Photos or Pictures folder for a targeted visual similarity scan.")
                    .font(.callout).foregroundStyle(.white.opacity(0.65))
                Spacer()
            } else {
                HStack(spacing: 10) {
                    Text("\(appState.clutterResult.similarImageGroups.count) similar photo sets")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("Smart Select (Keep Best)") {
                        for gIdx in appState.clutterResult.similarImageGroups.indices {
                            for iIdx in appState.clutterResult.similarImageGroups[gIdx].images.indices {
                                let isBest = appState.clutterResult.similarImageGroups[gIdx].images[iIdx].isBestToKeep
                                appState.clutterResult.similarImageGroups[gIdx].images[iIdx].isSelected = !isBest
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.clutterResult.similarImageGroups.indices, id: \.self) { gIdx in
                            let group = appState.clutterResult.similarImageGroups[gIdx]
                            GlassCard(padding: 14, cornerRadius: 14) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Similar Set: \(group.title)")
                                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                        Spacer()
                                        Text("\(group.images.count) photos")
                                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                                    }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(appState.clutterResult.similarImageGroups[gIdx].images.indices, id: \.self) { iIdx in
                                                let img = appState.clutterResult.similarImageGroups[gIdx].images[iIdx]
                                                VStack(alignment: .leading, spacing: 6) {
                                                    ZStack(alignment: .topTrailing) {
                                                        AsyncThumbnailView(path: img.path, size: CGSize(width: 140, height: 100))
                                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                                        if img.isBestToKeep {
                                                            Text("Best to Keep")
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundStyle(.white)
                                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                                .background(Capsule().fill(Color(hex: "2ED573")))
                                                                .padding(6)
                                                        } else if !img.visualFlaws.isEmpty {
                                                            Text(img.visualFlaws.joined(separator: ", "))
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundStyle(.white)
                                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                                .background(Capsule().fill(Color.orange))
                                                                .padding(6)
                                                        }
                                                    }
                                                    HStack {
                                                        Toggle("", isOn: $appState.clutterResult.similarImageGroups[gIdx].images[iIdx].isSelected)
                                                            .toggleStyle(.checkbox).labelsHidden()
                                                        Text(img.name).font(.caption).foregroundStyle(.white).lineLimit(1)
                                                    }
                                                    Text("\(img.dimensions) • \(ByteFormat.string(img.sizeBytes))")
                                                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                                                }
                                                .frame(width: 140)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                UbiquitousButton(title: "Remove", subtitle: ByteFormat.string(selectedBytes), palette: palette, isDisabled: selectedImgs.isEmpty) {
                    removeItems(selectedImgs.map { ($0.name, $0.path, $0.sizeBytes) }, isDuplicates: false)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var largeAndOldView: some View {
        let filteredIndices = appState.clutterResult.largeAndOldFiles.indices.filter { idx in
            let item = appState.clutterResult.largeAndOldFiles[idx]
            let matchesKind = kindFilter == "All" || item.groupTitle == kindFilter
            let matchesDate = accessDateFilter.matches(item.lastAccessed ?? item.lastModified)
            let matchesSize: Bool
            switch sizeFilter {
            case .all: matchesSize = true
            case .huge: matchesSize = item.sizeBytes >= 500 * 1024 * 1024
            case .average: matchesSize = item.sizeBytes >= 100 * 1024 * 1024 && item.sizeBytes < 500 * 1024 * 1024
            case .small: matchesSize = item.sizeBytes < 100 * 1024 * 1024
            }
            return matchesKind && matchesDate && matchesSize
        }
        let selected = appState.clutterResult.largeAndOldFiles.filter(\.isSelected)
        let selectedBytes = selected.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Picker("Size", selection: $sizeFilter) {
                        ForEach(SizeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 155)

                    Picker("Access Date", selection: $accessDateFilter) {
                        ForEach(AccessDateFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 145)

                    ForEach(["All", "Videos", "Archives", "Documents", "Pictures", "Other"], id: \.self) { kind in
                        Button { kindFilter = kind } label: {
                            Text(kind)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(kindFilter == kind ? palette.primary.opacity(0.75) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(filteredIndices, id: \.self) { idx in
                        let item = appState.clutterResult.largeAndOldFiles[idx]
                        HStack(spacing: 10) {
                            Toggle("", isOn: $appState.clutterResult.largeAndOldFiles[idx].isSelected).toggleStyle(.checkbox).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text("\(item.groupTitle) • \(item.path)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(ByteFormat.string(item.sizeBytes)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(palette.accent)
                            Button { FileSystemHelpers.revealInFinder(path: item.path) } label: {
                                Image(systemName: "magnifyingglass.circle").foregroundStyle(.white.opacity(0.65))
                            }.buttonStyle(.plain)
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 24)
            }

            UbiquitousButton(title: "Remove", subtitle: ByteFormat.string(selectedBytes), palette: palette, isDisabled: selected.isEmpty) {
                removeItems(selected.map { ($0.name, $0.path, $0.sizeBytes) }, isDuplicates: false)
            }
            .padding(.bottom, 12)
        }
    }

    private var downloadsView: some View {
        let sources = ["All"] + Array(Set(appState.clutterResult.downloads.map(\.groupTitle))).sorted()
        let filteredIndices = appState.clutterResult.downloads.indices.filter { idx in
            downloadSourceFilter == "All" || appState.clutterResult.downloads[idx].groupTitle == downloadSourceFilter
        }
        let selected = appState.clutterResult.downloads.filter(\.isSelected)
        let selectedBytes = selected.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(sources, id: \.self) { src in
                        Button {
                            downloadSourceFilter = src
                        } label: {
                            Text(src)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(downloadSourceFilter == src ? palette.primary.opacity(0.82) : Color.white.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(filteredIndices, id: \.self) { idx in
                        let item = appState.clutterResult.downloads[idx]
                        HStack(spacing: 10) {
                            Toggle("", isOn: $appState.clutterResult.downloads[idx].isSelected).toggleStyle(.checkbox).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Text(ByteFormat.string(item.sizeBytes)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                            Button { FileSystemHelpers.revealInFinder(path: item.path) } label: {
                                Image(systemName: "magnifyingglass.circle").foregroundStyle(.white.opacity(0.65))
                            }.buttonStyle(.plain)
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 24)
            }

            UbiquitousButton(title: "Remove", subtitle: ByteFormat.string(selectedBytes), palette: palette, isDisabled: selected.isEmpty) {
                removeItems(selected.map { ($0.name, $0.path, $0.sizeBytes) }, isDuplicates: false)
            }
            .padding(.bottom, 12)
        }
    }

    private func removeItems(_ list: [(name: String, path: String, sizeBytes: Int64)], isDuplicates: Bool) {
        Task {
            appState.clutterStage = .cleaning
            let res = await appState.clutterService.removeFiles(paths: list)
            appState.stats.totalPersonalFilesCleanedBytes += res.bytesFreed
            appState.stats.monthlyCleanedBytes += res.bytesFreed
            if isDuplicates { appState.stats.totalDuplicatesRemoved += res.itemsProcessed }
            appState.clutterSummary = res
            appState.clutterStage = .complete
            appState.refreshTelemetry(includeHeavy: true)
        }
    }
}

/// Decodes photo thumbnails asynchronously off the Main Thread using ImageIO and caches them in memory.
private struct AsyncThumbnailView: View {
    let path: String
    let size: CGSize
    @State private var image: NSImage? = nil

    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 180
        return c
    }()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.3)))
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: path) {
            if let cached = Self.cache.object(forKey: path as NSString) {
                self.image = cached
                return
            }
            let targetPath = path
            let maxDim = Int(max(size.width, size.height) * 2)
            let decodedCG: CGImage? = await Task.detached(priority: .utility) {
                let url = URL(fileURLWithPath: targetPath)
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDim,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            }.value
            if let cg = decodedCG {
                let nsImg = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                Self.cache.setObject(nsImg, forKey: targetPath as NSString)
                self.image = nsImg
            }
        }
    }
}
