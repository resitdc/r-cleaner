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

    private var healthColor: Color {
        switch appState.healthRating {
        case .excellent, .good: return Color(hex: "2ED573")
        case .fair: return Color(hex: "FFD166")
        case .requiresAttention, .critical: return Color(hex: "FF5E57")
        }
    }

    public var body: some View {
        let stats = appState.stats
        let df = DateFormatter()
        let _ = (df.dateStyle = .medium)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Clean Top Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My Activity")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Lifetime optimization & security history since \(df.string(from: stats.firstUsedDate))")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 360) // Keeps header clear of top-right HUD pills
                }

                // 2. Full-Width Mac Health & Live System Overview Banner
                healthHeroBanner(stats: stats, df: df)

                // 3. Symmetrical 2x2 Activity Grid (Equal Width & Height Cards)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    storageCleanedCard(stats: stats)
                    securityAuditCard(stats: stats, df: df)
                    devAndProcessPulseCard(stats: stats)
                    timeSavedCard(stats: stats)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Top Health Hero Banner

    private func healthHeroBanner(stats: ActivityStatistics, df: DateFormatter) -> some View {
        GlassCard(padding: 18, cornerRadius: 20) {
            HStack(spacing: 18) {
                // Animated Health Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 6)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: CGFloat(appState.healthScore) / 100.0)
                        .stroke(healthColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 60, height: 60)
                    Text("\(appState.healthScore)%")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Mac Health: \(appState.healthRating.rawValue)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(stats.lastSmartCareDate.map { "Last Smart Care: \(df.string(from: $0))" } ?? "Smart Care Ready")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(palette.primary.opacity(0.18)))
                    }
                    Text(appState.healthRating.descriptionText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                // Live Telemetry Mini Pills
                HStack(spacing: 10) {
                    heroMiniStat(
                        label: "Free Disk",
                        value: ByteFormat.string(appState.telemetry.storage.availableBytes),
                        icon: "internaldrive",
                        tint: Color(hex: "00F5D4")
                    )
                    heroMiniStat(
                        label: "Free RAM",
                        value: ByteFormat.string(appState.telemetry.memory.availableBytes),
                        icon: "memorychip",
                        tint: Color(hex: "38BDF8")
                    )
                    heroMiniStat(
                        label: "CPU Load",
                        value: "\(Int(appState.telemetry.cpu.totalLoadPercent.rounded()))%",
                        icon: "cpu",
                        tint: Color(hex: "FFB703")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heroMiniStat(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.20)))
    }

    // MARK: - 4 Symmetrical Dashboard Cards

    private func storageCleanedCard(stats: ActivityStatistics) -> some View {
        GlassCard(padding: 20, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Local Storage Cleaned", systemImage: "internaldrive.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("+\(ByteFormat.string(stats.monthlyCleanedBytes)) this month")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(palette.primary.opacity(0.16)))
                }

                Text(ByteFormat.string(stats.totalLocalCleanedBytes))
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)

                VStack(spacing: 7) {
                    breakdownRow("System Junk & Dev Caches", value: ByteFormat.string(stats.totalSystemJunkCleanedBytes), color: Color(hex: "F44B98"))
                    breakdownRow("Personal & Clutter Files", value: ByteFormat.string(stats.totalPersonalFilesCleanedBytes), color: Color(hex: "9B5DE5"))
                    breakdownRow("Applications & Leftovers", value: ByteFormat.string(stats.totalApplicationsCleanedBytes), color: Color(hex: "3A86FF"))
                }

                Spacer(minLength: 4)

                HStack {
                    Button {
                        appState.selectedModule = .smartCare
                    } label: {
                        HStack(spacing: 4) {
                            Text("Go to Smart Care")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appState.selectedModule = .devAISweeper
                    } label: {
                        Text("Dev & AI Sweeper")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 192, alignment: .topLeading)
        }
    }

    private func securityAuditCard(stats: ActivityStatistics, df: DateFormatter) -> some View {
        GlassCard(padding: 20, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Scanned for Malware", systemImage: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "2ED573"))
                            .frame(width: 6, height: 6)
                        Text(appState.settings.enableRealTimeMalwareMonitor ? "Shield Active" : "Manual Mode")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "2ED573"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "2ED573").opacity(0.15)))
                }

                Text("\(stats.totalMalwareItemsScanned) items")
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)

                VStack(spacing: 7) {
                    breakdownRow("Threats Removed", value: "\(stats.totalThreatsRemoved)", color: Color(hex: "2ED573"))
                    breakdownRow("Last Security Scan", value: stats.lastMalwareScanDate.map { df.string(from: $0) } ?? "Not yet", color: Color(hex: "38BDF8"))
                    breakdownRow("Scan Depth Profile", value: appState.settings.malwareScanMode.rawValue, color: Color(hex: "FFB703"))
                }

                Spacer(minLength: 4)

                HStack {
                    Button {
                        appState.selectedModule = .protection
                    } label: {
                        HStack(spacing: 4) {
                            Text("Go to Protection")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 192, alignment: .topLeading)
        }
    }

    private func devAndProcessPulseCard(stats: ActivityStatistics) -> some View {
        let portSnap = appState.portKillerSnapshot
        let cryoSnap = appState.cryoSnapshot

        return GlassCard(padding: 20, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Servers & Process Pulse", systemImage: "snowflake")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(cryoSnap.frozenCount > 0 ? "\(cryoSnap.frozenCount) Cryo-Frozen" : "Live Monitor")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "38BDF8"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "38BDF8").opacity(0.16)))
                }

                Text("\(portSnap.items.count) Active Ports")
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)

                VStack(spacing: 7) {
                    breakdownRow("Local Dev & Web Servers", value: "\(portSnap.devServersCount) running", color: Color(hex: "00F5D4"))
                    breakdownRow("Cryo-Frozen Apps (0% CPU)", value: "\(cryoSnap.frozenCount) paused", color: Color(hex: "38BDF8"))
                    breakdownRow("LAN-Exposed Ports (0.0.0.0)", value: "\(portSnap.lanExposedCount) ports", color: Color(hex: "FFB703"))
                }

                Spacer(minLength: 4)

                HStack {
                    Button {
                        appState.selectedModule = .portKiller
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open Port Killer")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appState.selectedModule = .cryoFreezer
                    } label: {
                        Text("Open Cryo-Freezer")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(hex: "38BDF8"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 192, alignment: .topLeading)
        }
    }

    private func timeSavedCard(stats: ActivityStatistics) -> some View {
        let hours = stats.totalTimeSavedMinutes / 60
        let mins = stats.totalTimeSavedMinutes % 60

        return GlassCard(padding: 20, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Total Time Saved", systemImage: "clock.badge.checkmark.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Automated Care")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(palette.primary.opacity(0.16)))
                }

                Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins) min")
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.accent)

                VStack(spacing: 7) {
                    breakdownRow("Maintenance & Port Tasks Run", value: "\(stats.totalMaintenanceTasksRun)", color: Color(hex: "34D399"))
                    breakdownRow("Applications Uninstalled", value: "\(stats.totalAppsUninstalled)", color: Color(hex: "60A5FA"))
                    breakdownRow("Duplicate Files Removed", value: "\(stats.totalDuplicatesRemoved)", color: Color(hex: "C77DFF"))
                }

                Spacer(minLength: 4)

                HStack {
                    Button {
                        appState.selectedModule = .performance
                    } label: {
                        HStack(spacing: 4) {
                            Text("Go to Performance")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 192, alignment: .topLeading)
        }
    }

    private func breakdownRow(_ title: String, value: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
