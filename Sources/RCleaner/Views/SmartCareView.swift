import SwiftUI

public struct SmartCareView: View {
    @EnvironmentObject var appState: AppState
    private let palette = RCleanerTheme.palette(for: .smartCare)

    public init() {}

    public var body: some View {
        switch appState.smartCareStage {
        case .intro:
            ModuleIntroHero(
                title: appState.stats.lastSmartCareDate == nil ? "Welcome to R-Cleaner" : "Smart Care",
                subtitle: "Quick maintenance that takes care of the essentials — one scan checks junk, threats, performance, apps, and clutter.",
                iconName: "sparkles",
                palette: palette,
                features: [
                    ("trash.circle.fill", "Quick Scan & Cleanup", "Removes system caches, logs, trash, and AI tool clutter."),
                    ("shield.lefthalf.filled.badge.checkmark", "Security Check", "Scans persistence agents, apps, and downloads for threats."),
                    ("gauge.with.dots.needle.67percent", "System Tune-up", "Prepares maintenance tasks, app leftovers, and duplicate downloads.")
                ],
                primaryActionTitle: "Scan",
                onPrimaryAction: { appState.startSmartCareScan() }
            )

        case .scanning:
            smartCareLiveScanView(isCleaning: false)

        case .resultsOverview, .dataManager:
            smartCareResultsView

        case .cleaning:
            smartCareLiveScanView(isCleaning: true)

        case .complete:
            if let summary = appState.smartCareSummary {
                CleanupCompleteView(
                    summary: summary,
                    palette: palette,
                    onDone: {
                        appState.smartCareStage = .intro
                        appState.resetSmartCarePillars()
                    }
                )
            }
        }
    }

    private func smartCareLiveScanView(isCleaning: Bool) -> some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 8) {
                Text(isCleaning ? "Taking care of your Mac..." : "Smart Care Scan")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(appState.smartCareStatusText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            // 5 Pillar Live Cards
            HStack(spacing: 14) {
                ForEach(appState.smartCarePillars) { pillar in
                    let pPal = RCleanerTheme.palette(for: pillar.targetModule)
                    GlassCard(padding: 16, cornerRadius: 18, highlightColor: pillar.status == .scanning || pillar.status == .running ? pPal.primary : nil) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(pPal.primary.opacity(0.20))
                                    .frame(width: 52, height: 52)
                                if pillar.status == .scanning || pillar.status == .running {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Image(systemName: pillar.iconName)
                                        .font(.system(size: 22))
                                        .foregroundStyle(pPal.accent)
                                }
                            }
                            Text(pillar.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(pillar.metricText)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(pPal.accent)
                                .lineLimit(1)
                            Text(pillar.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 124, height: 148)
                    }
                }
            }
            .padding(.horizontal, 28)

            ProgressView(value: appState.smartCareProgress)
                .tint(palette.accent)
                .frame(maxWidth: 420)

            Spacer()

            UbiquitousButton(title: "Stop", palette: palette, isRunning: true) {
                appState.stopCurrentTask()
            }
            .padding(.bottom, 22)
        }
    }

    private var smartCareResultsView: some View {
        VStack(spacing: 0) {
            ModuleHeaderBar(title: "Smart Care", backTitle: "Start Over") {
                appState.smartCareStage = .intro
            }

            VStack(spacing: 8) {
                Text("Your tasks are ready to run. Look what we found:")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Review individual categories or click Run to optimize everything at once.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 8)
            .padding(.bottom, 18)

            // 5 Result Cards Grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 16)], spacing: 16) {
                ForEach(appState.smartCarePillars) { pillar in
                    let pPal = RCleanerTheme.palette(for: pillar.targetModule)
                    GlassCard(padding: 18, cornerRadius: 20, highlightColor: pillar.status == .found ? pPal.primary : nil) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(pPal.primary.opacity(0.24))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: pillar.iconName)
                                        .font(.system(size: 20))
                                        .foregroundStyle(pPal.accent)
                                }
                                Spacer()
                                if pillar.status == .clean {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(Color(hex: "2ED573"))
                                        .font(.system(size: 18))
                                } else if pillar.status == .disabled {
                                    Text("Disabled")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(pillar.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                Text(pillar.metricText)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(pillar.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            Divider().overlay(Color.white.opacity(0.10))

                            HStack {
                                Button {
                                    appState.selectedModule = pillar.targetModule
                                } label: {
                                    Text("Review")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.white.opacity(0.14)))
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 30)

            Spacer()

            // Screen Cleaning Easter Egg Nudge
            HStack(spacing: 12) {
                Image(systemName: "display")
                    .foregroundStyle(palette.accent)
                Text("Your Mac is about to shine inside — give the screen a wipe with Screen Cleaning Mode.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                Button("Try Screen Cleaning Mode") {
                    appState.launchScreenCleaningMode()
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .padding(.bottom, 10)

            UbiquitousButton(title: "Run", subtitle: "All Tasks", palette: palette) {
                appState.runSmartCareActions()
            }
            .padding(.bottom, 20)
        }
    }
}
