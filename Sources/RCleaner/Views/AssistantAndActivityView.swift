import SwiftUI

// MARK: - Assistant Mac Health Popover (Top-Right Assistant Button)

public struct AssistantPopoverView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Mac Health Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: CGFloat(appState.healthScore) / 100.0)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 56, height: 56)
                    Text("\(appState.healthScore)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Mac Health:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(appState.healthRating.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(scoreColor)
                    }
                    Text(appState.healthRating.descriptionText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Disk Usage Bar
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(ByteFormat.string(appState.telemetry.storage.usedBytes)) of \(ByteFormat.string(appState.telemetry.storage.totalBytes)) used")
                        .font(.caption.bold())
                    Spacer()
                    Text("\(ByteFormat.string(appState.telemetry.storage.availableBytes)) free")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: appState.telemetry.storage.usedPercent, total: 100)
                    .tint(scoreColor)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))

            Divider()

            Text("Recommendations")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(appState.recommendations) { rec in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: rec.iconName)
                                .font(.system(size: 16))
                                .foregroundStyle(rec.severity == 2 ? .red : (rec.severity == 1 ? .orange : .cyan))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rec.title).font(.system(size: 12.5, weight: .semibold))
                                Text(rec.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                Button(rec.actionTitle) {
                                    appState.handleRecommendation(rec)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.link)
                                .padding(.top, 2)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10)))
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(16)
        .frame(width: 360)
    }

    private var scoreColor: Color {
        switch appState.healthRating {
        case .excellent, .good: return Color(hex: "2ED573")
        case .fair: return Color(hex: "FFD166")
        case .requiresAttention, .critical: return Color(hex: "FF5E57")
        }
    }
}

// MARK: - My Activity Statistics Dashboard

public struct MyActivityDashboardView: View {
    @EnvironmentObject var appState: AppState
    private let palette = RCleanerTheme.palette(for: .myActivity)

    public init() {}

    public var body: some View {
        let stats = appState.stats
        let df = DateFormatter()
        let _ = (df.dateStyle = .medium)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Activity")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("From \(df.string(from: stats.firstUsedDate))")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    // 1. Local Storage Cleaned
                    GlassCard(padding: 20, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Local Storage Cleaned", systemImage: "internaldrive.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("+\(ByteFormat.string(stats.monthlyCleanedBytes)) this month")
                                    .font(.caption.bold())
                                    .foregroundStyle(palette.accent)
                            }

                            Text(ByteFormat.string(stats.totalLocalCleanedBytes))
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)

                            VStack(spacing: 6) {
                                breakdownRow("System Junk", bytes: stats.totalSystemJunkCleanedBytes, color: Color(hex: "F44B98"))
                                breakdownRow("Personal Files", bytes: stats.totalPersonalFilesCleanedBytes, color: Color(hex: "9B5DE5"))
                                breakdownRow("Applications", bytes: stats.totalApplicationsCleanedBytes, color: Color(hex: "3A86FF"))
                            }

                            if stats.totalLocalCleanedBytes == 0 {
                                Button("Go to Smart Care") { appState.selectedModule = .smartCare }
                                    .font(.caption.bold()).foregroundStyle(palette.accent).buttonStyle(.plain)
                            }
                        }
                    }

                    // 2. Cloud Cleaned
                    GlassCard(padding: 20, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Cloud Cleaned", systemImage: "icloud.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)

                            Text(ByteFormat.string(stats.totalCloudCleanedBytes))
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)

                            Text(stats.totalCloudCleanedBytes == 0
                                 ? "Start cleaning or unsyncing cloud files to count freed gigabytes."
                                 : "Total space reclaimed across iCloud Drive, Google Drive, OneDrive, and Dropbox.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.68))

                            Spacer(minLength: 4)
                            Button("Go to Cloud Cleanup") { appState.selectedModule = .cloudCleanup }
                                .font(.caption.bold()).foregroundStyle(palette.accent).buttonStyle(.plain)
                        }
                    }

                    // 3. Scanned for Malware
                    GlassCard(padding: 20, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Scanned for Malware", systemImage: "shield.lefthalf.filled.badge.checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)

                            Text("\(stats.totalMalwareItemsScanned) items")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)

                            HStack(spacing: 18) {
                                VStack(alignment: .leading) {
                                    Text("Threats Removed").font(.caption2).foregroundStyle(.white.opacity(0.6))
                                    Text("\(stats.totalThreatsRemoved)").font(.title3.bold()).foregroundStyle(Color(hex: "2ED573"))
                                }
                                VStack(alignment: .leading) {
                                    Text("Last Scan").font(.caption2).foregroundStyle(.white.opacity(0.6))
                                    Text(stats.lastMalwareScanDate.map { df.string(from: $0) } ?? "Not yet")
                                        .font(.callout.bold()).foregroundStyle(.white)
                                }
                            }

                            Button("Go to Protection") { appState.selectedModule = .protection }
                                .font(.caption.bold()).foregroundStyle(palette.accent).buttonStyle(.plain)
                        }
                    }

                    // 4. Total Time Saved
                    GlassCard(padding: 20, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Total Time Saved", systemImage: "clock.badge.checkmark.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)

                            let hours = stats.totalTimeSavedMinutes / 60
                            let mins = stats.totalTimeSavedMinutes % 60
                            Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins) min")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(palette.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Maintenance Tasks Run: \(stats.totalMaintenanceTasksRun)").font(.caption).foregroundStyle(.white.opacity(0.75))
                                Text("• Applications Uninstalled: \(stats.totalAppsUninstalled)").font(.caption).foregroundStyle(.white.opacity(0.75))
                                Text("• Duplicates Removed: \(stats.totalDuplicatesRemoved)").font(.caption).foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func breakdownRow(_ title: String, bytes: Int64, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(ByteFormat.string(bytes)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
    }
}
