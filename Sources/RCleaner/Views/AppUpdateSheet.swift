import SwiftUI
import AppKit

public struct AppUpdateSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00D2A0"), Color(hex: "00BBF9")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: headerIcon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Installed version: v\(AppUpdaterService.currentAppVersion) (build \(AppUpdaterService.currentBuildNumber))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Main Content by Update State
            Group {
                switch appState.updateState {
                case .idle, .checking:
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Checking GitHub Releases...")
                            .font(.headline)
                        Text("Contacting github.com/\(AppUpdaterService.repoOwner)/\(AppUpdaterService.repoName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)

                case .upToDate(let latest):
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(Color(hex: "2ED573"))
                        Text("R-Cleaner is up to date!")
                            .font(.title3.bold())
                        Text("You are running v\(AppUpdaterService.currentAppVersion) (latest release: v\(latest)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)

                case .updateAvailable(let release):
                    releaseDetailsView(release: release)

                case .downloading(let release, let progress, let downloaded, let total):
                    VStack(spacing: 16) {
                        Text("Downloading \(release.title)")
                            .font(.headline)
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 420)
                        HStack(spacing: 12) {
                            Text("\(Int(progress * 100))%")
                                .font(.callout.bold().monospacedDigit())
                            if total > 0 {
                                Text("• \(ByteFormat.string(downloaded)) / \(ByteFormat.string(total))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if release.checksumsURL != nil {
                            Label("Will verify SHA-256 cryptographic signature after download", systemImage: "lock.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)

                case .verifying(let release):
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Verifying SHA-256 Checksum...")
                            .font(.headline)
                        Text("Confirming integrity of \(release.preferredAssetName ?? release.tagName) against SHA256SUMS.txt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)

                case .installing(let release):
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Installing R-Cleaner \(release.tagName)...")
                            .font(.headline)
                        Text("Unpacking verified app bundle and preparing atomic relaunch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)

                case .readyToReveal(let release, let fileURL, let note):
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color(hex: "00D2A0"))
                        Text("R-Cleaner \(release.tagName) Verified & Ready")
                            .font(.title3.bold())
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)

                case .failed(let message):
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.orange)
                        Text("Update Check Failed")
                            .font(.title3.bold())
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                        HStack(spacing: 12) {
                            Button("Retry") {
                                appState.checkForUpdates(userInitiated: true)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Open GitHub Releases") {
                                NSWorkspace.shared.open(AppUpdaterService.releasesPageURL)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                }
            }

            Divider()

            // Footer Actions
            footerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 560, height: 430)
    }

    private func releaseDetailsView(release: AppReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("v\(AppUpdaterService.currentAppVersion)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(release.tagName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "00D2A0")))

                if release.preferredAssetSizeBytes > 0 {
                    Text(ByteFormat.string(release.preferredAssetSizeBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if release.checksumsURL != nil {
                    Label("SHA-256 Verified", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "2ED573"))
                }
            }

            if let date = release.publishedAt {
                Text("Published \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Release Notes")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ScrollView {
                Text(release.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "Includes stability improvements, performance upgrades, and macOS Universal (Apple Silicon & Intel) support."
                     : release.releaseNotes)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        }
        .padding(20)
    }

    @ViewBuilder
    private var footerBar: some View {
        switch appState.updateState {
        case .updateAvailable(let release):
            HStack(spacing: 10) {
                Button("Skip \(release.tagName)") {
                    appState.skipUpdateVersion(release.version)
                    dismiss()
                }
                .foregroundStyle(.secondary)

                Button("View on GitHub") {
                    NSWorkspace.shared.open(release.htmlURL)
                }

                Spacer()

                Button("Later") { dismiss() }

                Button(release.supportsInPlaceInstall ? "Install & Relaunch" : "Download Installer") {
                    appState.installAvailableUpdate(release)
                }
                .buttonStyle(.borderedProminent)
                .disabled(release.preferredDownloadURL == nil)
            }

        case .downloading, .verifying, .installing:
            HStack {
                Text("Do not close R-Cleaner while updating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    appState.cancelUpdateInstall()
                }
            }

        default:
            HStack {
                Button("Open GitHub Releases") {
                    NSWorkspace.shared.open(AppUpdaterService.releasesPageURL)
                }
                Spacer()
                Button("Check Again") {
                    appState.checkForUpdates(userInitiated: true)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var headerIcon: String {
        switch appState.updateState {
        case .updateAvailable: return "arrow.down.app.fill"
        case .upToDate: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var headerTitle: String {
        switch appState.updateState {
        case .updateAvailable(let r): return "Update Available — \(r.tagName)"
        case .upToDate: return "Software Update"
        case .downloading: return "Downloading Update"
        case .verifying: return "Verifying Update"
        case .installing: return "Installing Update"
        case .readyToReveal: return "Update Ready"
        default: return "Check for Updates"
        }
    }
}
