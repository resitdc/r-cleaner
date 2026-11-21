import SwiftUI

public struct MyToolsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText: String = ""
    private let palette = RCleanerTheme.palette(for: .myTools)

    public init() {}

    private var allTools: [QuickToolItem] {
        [
            QuickToolItem(id: "systemJunk", title: "System Junk", description: "Remove redundant caches, logs, and Xcode derived data.", iconName: "sparkles.rectangle.stack.fill", keywords: ["cache", "logs", "junk", "xcode"], badge: nil, targetModule: .cleanup, focusedFlowID: "systemJunk", accentHex: "F44B98"),
            QuickToolItem(id: "aiClutter", title: "AI Clutter", description: "Clean Claude, Codex, Gemini, Cursor caches & local Ollama/LM Studio models.", iconName: "wand.and.rays", keywords: ["ai", "ollama", "lm studio", "claude", "cursor", "gemini"], badge: "New", targetModule: .cleanup, focusedFlowID: "aiClutter", accentHex: "FF7A59"),
            QuickToolItem(id: "mailAttachments", title: "Mail Attachments", description: "Remove locally stored email attachment copies.", iconName: "envelope.open.fill", keywords: ["mail", "attachments"], badge: nil, targetModule: .cleanup, focusedFlowID: "mailAttachments", accentHex: "FFB56B"),
            QuickToolItem(id: "trashBins", title: "Trash Bins", description: "Empty system and external drive Trash bins.", iconName: "trash.fill", keywords: ["trash", "bin", "empty"], badge: nil, targetModule: .cleanup, focusedFlowID: "trashBins", accentHex: "F44B98"),
            QuickToolItem(id: "malwareFinder", title: "Malware Finder", description: "Identify and remove adware, trojans, and suspicious agents.", iconName: "shield.lefthalf.filled.badge.checkmark", keywords: ["malware", "virus", "security", "adware"], badge: nil, targetModule: .protection, focusedFlowID: "malwareFinder", accentHex: "2ED573"),
            QuickToolItem(id: "privacyItems", title: "Privacy Items", description: "Clear browser history, cookies, and recent activity traces.", iconName: "hand.raised.fill", keywords: ["privacy", "cookies", "safari", "chrome", "firefox"], badge: nil, targetModule: .protection, focusedFlowID: "privacyItems", accentHex: "1BC6B4"),
            QuickToolItem(id: "applicationPermissions", title: "App Permissions", description: "Audit Camera, Microphone, Full Disk Access, and Automation grants.", iconName: "lock.shield.fill", keywords: ["permissions", "camera", "microphone", "tcc"], badge: nil, targetModule: .protection, focusedFlowID: "applicationPermissions", accentHex: "6BF2C2"),
            QuickToolItem(id: "maintenanceTasks", title: "Maintenance Tasks", description: "Free Up RAM, Flush DNS, Reindex Spotlight, Speed Up Mail.", iconName: "gauge.with.dots.needle.67percent", keywords: ["ram", "dns", "spotlight", "speed up", "maintenance"], badge: nil, targetModule: .performance, focusedFlowID: "maintenanceTasks", accentHex: "FF6B4A"),
            QuickToolItem(id: "loginItems", title: "Login Items", description: "Manage apps that launch automatically at startup.", iconName: "power.circle.fill", keywords: ["login", "startup", "boot"], badge: nil, targetModule: .performance, focusedFlowID: "loginItems", accentHex: "FF9F43"),
            QuickToolItem(id: "backgroundItems", title: "Background Items", description: "Review Launch Agents and Daemons running silently.", iconName: "cpu.fill", keywords: ["background", "launch agents", "daemons"], badge: nil, targetModule: .performance, focusedFlowID: "backgroundItems", accentHex: "FFD166"),
            QuickToolItem(id: "timeMachine", title: "Time Machine Snapshots", description: "Thin local APFS snapshots without losing backups.", iconName: "clock.arrow.circlepath", keywords: ["time machine", "snapshots", "apfs"], badge: nil, targetModule: .performance, focusedFlowID: "timeMachine", accentHex: "FF6B4A"),
            QuickToolItem(id: "uninstaller", title: "App Uninstaller", description: "Uninstall apps completely with all preferences & caches.", iconName: "square.grid.2x2.fill", keywords: ["uninstall", "apps", "remove", "reset"], badge: nil, targetModule: .applications, focusedFlowID: "uninstaller", accentHex: "3A86FF"),
            QuickToolItem(id: "appUpdater", title: "App Updater", description: "Check Sparkle feeds and macOS Software Updates.", iconName: "arrow.down.app.fill", keywords: ["update", "updater", "versions"], badge: nil, targetModule: .applications, focusedFlowID: "appUpdater", accentHex: "5E60CE"),
            QuickToolItem(id: "appLeftovers", title: "App Leftovers", description: "Find orphaned files from previously removed applications.", iconName: "puzzlepiece.extension.fill", keywords: ["leftovers", "orphan", "remnants"], badge: nil, targetModule: .applications, focusedFlowID: "appLeftovers", accentHex: "64DFDF"),
            QuickToolItem(id: "duplicateFinder", title: "Duplicate Finder", description: "Find exact SHA-256 duplicate copies across folders.", iconName: "doc.on.doc.fill", keywords: ["duplicates", "copies", "identical"], badge: nil, targetModule: .myClutter, focusedFlowID: "duplicateFinder", accentHex: "9B5DE5"),
            QuickToolItem(id: "similarImages", title: "Similar Images", description: "Cluster near-identical photos & flag blurry shots.", iconName: "photo.stack.fill", keywords: ["similar", "photos", "blur", "images"], badge: nil, targetModule: .myClutter, focusedFlowID: "similarImages", accentHex: "F15BB5"),
            QuickToolItem(id: "largeAndOld", title: "Large & Old Files", description: "Locate huge forgotten files eating disk space.", iconName: "externaldrive.fill.badge.timemachine", keywords: ["large", "old", "big", "huge"], badge: nil, targetModule: .myClutter, focusedFlowID: "largeAndOld", accentHex: "C77DFF"),
            QuickToolItem(id: "downloads", title: "Downloads", description: "Tidy up one-time downloaded files and installers.", iconName: "arrow.down.circle.fill", keywords: ["downloads", "dmg", "installers"], badge: nil, targetModule: .myClutter, focusedFlowID: "downloads", accentHex: "9B5DE5"),
            QuickToolItem(id: "spaceLens", title: "Space Lens", description: "Interactive proportional bubble map of disk usage.", iconName: "circle.hexagongrid.fill", keywords: ["space lens", "map", "bubbles", "storage"], badge: nil, targetModule: .spaceLens, focusedFlowID: "spaceLens", accentHex: "00BBF9"),
            QuickToolItem(id: "emailCleanup", title: "Email Cleanup", description: "Declutter newsletters, spam, and large inbox messages.", iconName: "envelope.badge.fill", keywords: ["email", "mail", "newsletters", "spam"], badge: "New", targetModule: .emailCleanup, focusedFlowID: "emailCleanup", accentHex: "F472B6"),
            QuickToolItem(id: "screenCleaning", title: "Screen Cleaning Mode", description: "Locks keyboard & trackpad with a clean dark screen overlay so you can wipe your display.", iconName: "display", keywords: ["screen", "wipe", "keyboard lock", "clean display"], badge: "New", targetModule: .myTools, focusedFlowID: "screenCleaning", accentHex: "34D399")
        ]
    }

    public var body: some View {
        let filtered = allTools.filter { tool in
            searchText.isEmpty
                || tool.title.localizedCaseInsensitiveContains(searchText)
                || tool.description.localizedCaseInsensitiveContains(searchText)
                || tool.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
        let favorites = filtered.filter { appState.settings.favoriteToolIDs.contains($0.id) }
        let others = filtered.filter { !appState.settings.favoriteToolIDs.contains($0.id) }

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Tools")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Quick tools for focused tasks — clean up, protect, and maintain your Mac in just a few clicks.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                    TextField("Search tools...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: 190)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .padding(.trailing, 130) // Space for top-right Assistant pill
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !favorites.isEmpty {
                        sectionHeader("Favorites")
                        toolGrid(favorites)
                    }

                    if !others.isEmpty {
                        sectionHeader(searchText.isEmpty ? "Other Tools" : "\(filtered.count) results found")
                        toolGrid(others)
                    }

                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.system(size: 38)).foregroundStyle(.white.opacity(0.4))
                            Text("No tools match your search.").font(.headline).foregroundStyle(.white)
                            Text("Try a different keyword like 'ai', 'ram', 'duplicates', or 'screen'.").font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.8))
    }

    private func toolGrid(_ tools: [QuickToolItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 14)], spacing: 14) {
            ForEach(tools) { tool in
                let isFav = appState.settings.favoriteToolIDs.contains(tool.id)
                let tint = Color(hex: tool.accentHex)

                GlassCard(padding: 16, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(tint.opacity(0.24))
                                    .frame(width: 36, height: 36)
                                Image(systemName: tool.iconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(tint)
                            }
                            Spacer()
                            if let badge = tool.badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(tint))
                            }
                            Button {
                                if isFav {
                                    appState.settings.favoriteToolIDs.removeAll { $0 == tool.id }
                                } else {
                                    appState.settings.favoriteToolIDs.append(tool.id)
                                }
                            } label: {
                                Image(systemName: isFav ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 12))
                                    .foregroundStyle(isFav ? tint : .white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }

                        Text(tool.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)

                        Text(tool.description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                            .frame(minHeight: 30, alignment: .topLeading)

                        Button(tool.focusedFlowID == "screenCleaning" ? "Open" : "Scan") {
                            appState.launchQuickTool(tool)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint.opacity(0.75)))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
