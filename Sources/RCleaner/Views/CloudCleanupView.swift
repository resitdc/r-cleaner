import SwiftUI

public struct CloudCleanupView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAccountID: String? = nil
    @State private var filterLocalOnly: Bool = false
    private let palette = RCleanerTheme.palette(for: .cloudCleanup)

    public init() {}

    public var body: some View {
        if let summary = appState.cloudSummary {
            CleanupCompleteView(summary: summary, palette: palette, onDone: { appState.cloudSummary = nil })
        } else if let provider = appState.cloudScanningProvider {
            ScanningProgressView(
                title: "Scanning \(provider.rawValue) storage...",
                subtitle: "Looking for large and unused cloud files that take up space.",
                currentPath: appState.cloudStatusText,
                progress: appState.cloudScanProgress,
                iconName: provider.iconName,
                palette: palette,
                onStop: { appState.stopCurrentTask() }
            )
        } else if let accID = selectedAccountID, let accIdx = appState.cloudAccounts.firstIndex(where: { $0.id == accID }) {
            cloudAccountDetailView(accountIdx: accIdx)
        } else {
            cloudAccountsHubView
        }
    }

    private var cloudAccountsHubView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud Cleanup")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Tidy up your cloud files across iCloud Drive, Google Drive, OneDrive, and Dropbox. Unsync locally cached files to reclaim Mac storage without deleting them from the cloud.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 680, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 18)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 16)], spacing: 16) {
                ForEach(appState.cloudAccounts) { account in
                    GlassCard(padding: 20, cornerRadius: 18, highlightColor: account.isDetected ? palette.primary : nil) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(palette.primary.opacity(0.22))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: account.provider.iconName)
                                        .font(.system(size: 20))
                                        .foregroundStyle(palette.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.provider.rawValue)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(account.isDetected ? "Connected via Desktop / macOS" : "Not detected on this Mac")
                                        .font(.system(size: 11))
                                        .foregroundStyle(account.isDetected ? Color(hex: "2ED573") : .white.opacity(0.55))
                                }
                                Spacer()
                            }

                            if account.totalScannedBytes > 0 {
                                // Segmented Cloud Storage Indicator Bar (Locally Synced vs Cloud-Only)
                                GeometryReader { geo in
                                    let total = max(1, Double(account.totalScannedBytes))
                                    let localW = geo.size.width * CGFloat(Double(account.locallySyncedBytes) / total)
                                    HStack(spacing: 1) {
                                        Rectangle().fill(palette.accent).frame(width: max(3, localW))
                                        Rectangle().fill(palette.secondary.opacity(0.55))
                                    }
                                    .clipShape(Capsule())
                                }
                                .frame(height: 6)

                                HStack(spacing: 16) {
                                    VStack(alignment: .leading) {
                                        Text("Total Scanned").font(.caption2).foregroundStyle(.white.opacity(0.55))
                                        Text(ByteFormat.string(account.totalScannedBytes)).font(.callout.bold()).foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("Locally Synced").font(.caption2).foregroundStyle(.white.opacity(0.55))
                                        Text(ByteFormat.string(account.locallySyncedBytes)).font(.callout.bold()).foregroundStyle(palette.accent)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("Cloud-Only").font(.caption2).foregroundStyle(.white.opacity(0.55))
                                        Text(ByteFormat.string(account.cloudOnlyBytes)).font(.callout.bold()).foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            } else if let path = account.rootPath {
                                Text(path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Sign in to \(account.provider.rawValue) desktop app or iCloud Drive in System Settings, then click Refresh.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.55))
                            }

                            HStack {
                                if account.isDetected {
                                    Button(account.items.isEmpty ? "Scan Cloud" : "Rescan") {
                                        selectedAccountID = account.id
                                        appState.scanCloudProvider(account)
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(palette.primary.opacity(0.85)))
                                    .buttonStyle(.plain)

                                    if !account.items.isEmpty {
                                        Button("Review \(account.items.count) Files") {
                                            selectedAccountID = account.id
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(Color.white.opacity(0.14)))
                                        .buttonStyle(.plain)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 30)

            Spacer()

            HStack {
                Image(systemName: "lock.shield.fill").foregroundStyle(palette.accent)
                Text("R-Cleaner only scans file names and sizes locally — it never reads or uploads file contents.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button("Refresh Accounts") {
                    appState.cloudAccounts = appState.cloudEmailService.discoverCloudAccounts()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
    }

    private func cloudAccountDetailView(accountIdx: Int) -> some View {
        let account = appState.cloudAccounts[accountIdx]
        let filteredIndices = account.items.indices.filter { idx in
            !filterLocalOnly || account.items[idx].isLocallySynced
        }
        let selectedItems = account.items.filter(\.isSelected)
        let selectedBytes = selectedItems.reduce(0) { $0 + $1.sizeBytes }

        return VStack(spacing: 0) {
            ModuleHeaderBar(
                title: "\(account.provider.rawValue) Files",
                backTitle: "All Clouds",
                trailingText: "Local: \(ByteFormat.string(account.locallySyncedBytes))"
            ) {
                selectedAccountID = nil
            }

            HStack {
                Toggle("Show Locally Synced Only (Eligible for Unsync)", isOn: $filterLocalOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(filteredIndices.count) large files")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            if filteredIndices.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 50)).foregroundStyle(Color(hex: "2ED573"))
                Text("How did you keep it this tidy?").font(.title3.bold()).foregroundStyle(.white)
                Text("No large cloud files found in this view.").foregroundStyle(.white.opacity(0.65))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredIndices, id: \.self) { idx in
                            let item = appState.cloudAccounts[accountIdx].items[idx]
                            HStack(spacing: 10) {
                                Toggle("", isOn: $appState.cloudAccounts[accountIdx].items[idx].isSelected)
                                    .toggleStyle(.checkbox).labelsHidden()
                                Image(systemName: item.isLocallySynced ? "arrow.down.circle.fill" : "icloud")
                                    .foregroundStyle(item.isLocallySynced ? palette.accent : .white.opacity(0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text("\(item.isLocallySynced ? "Synced Locally" : "Cloud-Only") • \(item.fileKind)")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                                Text(ByteFormat.string(item.sizeBytes))
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.white)
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
            }

            HStack(spacing: 18) {
                Button {
                    Task {
                        let res = await appState.cloudEmailService.unsyncCloudItems(selectedItems)
                        appState.stats.totalCloudCleanedBytes += res.bytesFreed
                        appState.cloudSummary = res
                    }
                } label: {
                    Label("Unsync Local Copy", systemImage: "icloud.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(selectedItems.filter(\.isLocallySynced).isEmpty)

                UbiquitousButton(
                    title: "Remove",
                    subtitle: selectedItems.isEmpty ? nil : ByteFormat.string(selectedBytes),
                    palette: palette,
                    isDisabled: selectedItems.isEmpty
                ) {
                    Task {
                        let res = await appState.cloudEmailService.removeCloudItems(selectedItems)
                        appState.stats.totalCloudCleanedBytes += res.bytesFreed
                        appState.cloudSummary = res
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}
