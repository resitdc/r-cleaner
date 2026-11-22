import SwiftUI

public struct EmailCleanupView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: EmailCleanupCategory = .smartCleanup
    @State private var previewMessage: EmailMessageItem? = nil
    private let palette = RCleanerTheme.palette(for: .emailCleanup)

    public init() {}

    public var body: some View {
        switch appState.emailStage {
        case .intro:
            ModuleIntroHero(
                title: "Email Cleanup",
                subtitle: "Clear out inbox clutter, large messages, old promotions, and unwanted newsletters.",
                iconName: "envelope.badge.fill",
                palette: palette,
                features: [
                    ("wand.and.stars", "Smart Cleanup Suggestions", "Automatically surfaces Large Emails, Old Promotions, Automated Emails, and Top Senders."),
                    ("bell.slash.fill", "Subscriptions & Newsletters", "Detects List-Unsubscribe senders so you can tidy up recurring mailing lists."),
                    ("lock.shield.fill", "Private Local Analysis", "Scans local Apple Mail storage on-device — your email content stays strictly private.")
                ],
                primaryActionTitle: "Scan",
                onPrimaryAction: { appState.startEmailScan() }
            )

        case .scanning:
            ScanningProgressView(
                title: "Scanning Mailbox...",
                subtitle: "Analyzing email headers, subscriptions, drafts, and spam.",
                currentPath: appState.emailStatusText,
                progress: appState.emailProgress,
                iconName: "envelope.badge.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .resultsOverview, .dataManager:
            emailManagerView

        case .cleaning:
            ScanningProgressView(
                title: "Moving emails to Trash...",
                subtitle: "Cleaning selected mailbox items.",
                currentPath: "",
                progress: 0.7,
                iconName: "trash.fill",
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )

        case .complete:
            if let summary = appState.emailSummary {
                CleanupCompleteView(summary: summary, palette: palette, onDone: { appState.emailStage = .intro })
            }
        }
    }

    private var emailManagerView: some View {
        let filteredIndices = appState.emailMessages.indices.filter { idx in
            selectedCategory == .smartCleanup || appState.emailMessages[idx].category == selectedCategory
        }
        let selected = appState.emailMessages.filter(\.isSelected)
        let selectedBytes = selected.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "Email Cleanup",
                backTitle: "Start Over",
                trailingText: appState.emailConnectedAccount ?? "Local Mail"
            ) {
                appState.emailStage = .intro
            }

            if appState.emailMessages.isEmpty {
                Spacer()
                Image(systemName: "envelope.open.badge.clock")
                    .font(.system(size: 56))
                    .foregroundStyle(palette.accent)
                Text("No local Apple Mail messages accessible")
                    .font(.title2.bold()).foregroundStyle(.white).padding(.top, 8)
                Text("Grant Full Disk Access in System Settings → Privacy & Security so R-Cleaner can inspect ~/Library/Mail, or configure Apple Mail on this Mac.")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button("Open Full Disk Access Settings") {
                    FileSystemHelpers.openPrivacySettings(pane: "Privacy_AllFiles")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(palette.primary.opacity(0.8)))
                .buttonStyle(.plain)
                .padding(.top, 12)
                Spacer()
            } else {
                HStack(spacing: 14) {
                    // Left Categories Rail
                    VStack(spacing: 6) {
                        ForEach(EmailCleanupCategory.allCases) { cat in
                            let count = cat == .smartCleanup
                                ? appState.emailMessages.count
                                : appState.emailMessages.filter { $0.category == cat }.count
                            Button {
                                selectedCategory = cat
                            } label: {
                                HStack {
                                    Image(systemName: cat.iconName).foregroundStyle(palette.accent).frame(width: 20)
                                    Text(cat.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(count)").font(.caption.bold()).foregroundStyle(.white.opacity(0.65))
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 11).fill(selectedCategory == cat ? palette.primary.opacity(0.45) : Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(width: 230)

                    // Right Messages List
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCategory.rawValue).font(.title3.bold()).foregroundStyle(.white)
                                Text(selectedCategory.description).font(.caption).foregroundStyle(.white.opacity(0.65))
                            }
                            Spacer()
                            if !filteredIndices.isEmpty {
                                let allCategorySelected = filteredIndices.allSatisfy { appState.emailMessages[$0].isSelected }
                                Button(allCategorySelected ? "Deselect All" : "Select All") {
                                    let nextVal = !allCategorySelected
                                    for idx in filteredIndices {
                                        appState.emailMessages[idx].isSelected = nextVal
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                                .buttonStyle(.plain)
                            }
                        }

                        if filteredIndices.isEmpty {
                            VStack(spacing: 10) {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(palette.accent.opacity(0.85))
                                Text("No emails in \(selectedCategory.rawValue)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("This category is currently clean.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 7) {
                                    ForEach(filteredIndices, id: \.self) { idx in
                                        let msg = appState.emailMessages[idx]
                                        HStack(spacing: 10) {
                                            Toggle("", isOn: $appState.emailMessages[idx].isSelected).toggleStyle(.checkbox).labelsHidden()
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(msg.senderName).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                                                    Text(msg.suggestionTag)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                                        .background(Capsule().fill(palette.primary.opacity(0.3)))
                                                        .foregroundStyle(palette.accent)
                                                }
                                                Text(msg.subject).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                                                Text(msg.snippet).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                            }
                                            Spacer()
                                            Text(ByteFormat.string(msg.sizeBytes)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                                            Button {
                                                previewMessage = msg
                                            } label: {
                                                Image(systemName: "eye").foregroundStyle(.white.opacity(0.7))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                UbiquitousButton(
                    title: "Remove",
                    subtitle: selected.isEmpty ? nil : ByteFormat.string(selectedBytes),
                    palette: palette,
                    isDisabled: selected.isEmpty
                ) {
                    Task {
                        appState.emailStage = .cleaning
                        let paths = selected.compactMap { m -> (String, String, Int64)? in
                            guard let p = m.filePath else { return nil }
                            return (m.subject, p, m.sizeBytes)
                        }
                        let res = await appState.clutterService.removeFiles(paths: paths)
                        let cleanedPaths = Set(res.logEntries.filter { $0.status == .cleaned }.map(\.path))
                        appState.emailMessages.removeAll { msg in
                            guard let p = msg.filePath else { return false }
                            return cleanedPaths.contains(p)
                        }
                        appState.stats.totalSystemJunkCleanedBytes += res.bytesFreed
                        appState.stats.monthlyCleanedBytes += res.bytesFreed
                        appState.emailSummary = res
                        appState.emailStage = .complete
                        appState.refreshTelemetry(includeHeavy: true)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .sheet(item: $previewMessage) { msg in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Email Preview").font(.headline)
                    Spacer()
                    Button("Close") { previewMessage = nil }
                }
                Divider()
                Text(msg.subject).font(.title3.bold())
                Text("From: \(msg.senderName) <\(msg.senderEmail)>").font(.callout).foregroundStyle(.secondary)
                Text("Size: \(ByteFormat.string(msg.sizeBytes)) • Category: \(msg.category.rawValue)").font(.caption).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    Text(msg.snippet).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(width: 520, height: 340)
        }
    }
}
