import SwiftUI
import AppKit

/// Menu Bar Satellite Monitor built directly into R-Cleaner via MenuBarExtra.
public struct MenuBarMonitorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var expandedCard: DetailCard? = nil

    enum DetailCard: String {
        case storage, protection, memory, cpu, battery, network, drives, alerts
    }

    public init() {}

    public var body: some View {
        let thermal = appState.telemetry.thermal
        let thermalTint = Color(hex: thermal.state.accentHex)

        VStack(spacing: 0) {
            // Header with Health Score, Live Thermal Pill & Smart Alerts Button
            HStack(spacing: 6) {
                HStack(spacing: 7) {
                    ResitdcLogoMark(height: 16, glow: false)
                    Text("R-Cleaner")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                // Live Thermal State Pill
                Button {
                    expandedCard = .battery
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: thermal.state == .nominal ? "thermometer.low" : "thermometer.high")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(thermal.state.shortLabel)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(thermalTint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(thermalTint.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .help("Thermal Pressure: \(thermal.state.rawValue) — \(thermal.state.descriptionText)")

                // Clear Smart Alerts Config / Active Bell
                Button {
                    expandedCard = (expandedCard == .alerts) ? nil : .alerts
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: appState.settings.enableClearSmartAlerts ? "bell.badge.fill" : "bell.slash")
                            .font(.system(size: 10.5, weight: .semibold))
                        if !appState.activeSmartAlerts.isEmpty {
                            Text("\(appState.activeSmartAlerts.count)")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                    }
                    .foregroundStyle(!appState.activeSmartAlerts.isEmpty ? Color(hex: "FF5E57") : (appState.settings.enableClearSmartAlerts ? Color(hex: "36E2F8") : .secondary))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((!appState.activeSmartAlerts.isEmpty ? Color(hex: "FF5E57") : Color.secondary).opacity(0.16)))
                }
                .buttonStyle(.plain)
                .help("Configure Clear Smart Alerts thresholds")

                Text("\(appState.healthScore)%")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color(hex: "2ED573"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "2ED573").opacity(0.18)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    if let card = expandedCard {
                        detailOverlay(for: card)
                    } else {
                        overviewGrid
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 460)

            Divider()

            // Footer
            HStack {
                Button("Open R-Cleaner") {
                    openMainWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button {
                    openMainWindow()
                    appState.showSettingsWindow = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit R-Cleaner")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 380)
        .onAppear {
            appState.refreshTelemetry(includeHeavy: true)
        }
    }

    // MARK: - 2-Column Telemetry Cards Grid

    private var overviewGrid: some View {
        let t = appState.telemetry
        return VStack(spacing: 10) {
            // Active Clear Smart Alerts Strip (only visible when a configured threshold trips)
            if !appState.activeSmartAlerts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(appState.activeSmartAlerts) { alert in
                        let alertTint = Color(hex: alert.accentHex)
                        HStack(spacing: 8) {
                            Image(systemName: alert.iconName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(alertTint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alert.title)
                                    .font(.system(size: 11.5, weight: .bold))
                                Text(alert.message)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            switch alert.kind {
                            case .criticalRAM:
                                Button("Free RAM") { appState.quickFreeUpRAM() }
                                    .controlSize(.mini)
                                    .buttonStyle(.borderedProminent)
                            case .lowDisk:
                                Button("Sweep") {
                                    appState.selectedModule = .devAISweeper
                                    openMainWindow()
                                }
                                .controlSize(.mini)
                                .buttonStyle(.borderedProminent)
                            case .runawayCPU:
                                if let pid = alert.processID {
                                    Button("Quit") {
                                        _ = appState.telemetryService.terminateProcess(pid: pid)
                                        appState.dismissSmartAlert(alert)
                                        appState.refreshTelemetry(includeHeavy: true)
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                            case .thermalPressure:
                                Button("Inspect") { expandedCard = .cpu }
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                            }
                            Button {
                                appState.dismissSmartAlert(alert)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 11).fill(alertTint.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(alertTint.opacity(0.35), lineWidth: 1))
                    }
                }
            }

            // Storage + Protection Row
            HStack(spacing: 10) {
                monitorCard(
                    title: t.storage.volumeName,
                    icon: "internaldrive.fill",
                    tint: Color(hex: "38BDF8"),
                    value: ByteFormat.string(t.storage.availableBytes),
                    subtitle: "Available • Trash: \(ByteFormat.string(t.storage.trashBytes))",
                    actionTitle: "Free Up",
                    onAction: { appState.quickEmptyTrash() },
                    onTap: { expandedCard = .storage }
                )

                monitorCard(
                    title: "Protection",
                    icon: "shield.lefthalf.filled.badge.checkmark",
                    tint: Color(hex: "2ED573"),
                    value: appState.protectionResult.threats.isEmpty ? "Protected" : "\(appState.protectionResult.threats.count) Threats",
                    subtitle: appState.settings.enableRealTimeMalwareMonitor ? "Real-time monitor ON" : "Monitor OFF",
                    actionTitle: "Scan",
                    onAction: {
                        appState.selectedModule = .protection
                        appState.startProtectionScan()
                        openMainWindow()
                    },
                    onTap: { expandedCard = .protection }
                )
            }

            // Memory + CPU Row
            HStack(spacing: 10) {
                monitorCard(
                    title: "Memory",
                    icon: "memorychip",
                    tint: Color(hex: "A855F7"),
                    value: ByteFormat.string(t.memory.availableBytes),
                    subtitle: "Available • Pressure: \(t.memory.pressureLabel)",
                    actionTitle: "Free Up",
                    onAction: { appState.quickFreeUpRAM() },
                    onTap: { expandedCard = .memory }
                )

                monitorCard(
                    title: "CPU",
                    icon: "cpu.fill",
                    tint: Color(hex: "FF6B4A"),
                    value: String(format: "%.0f%%", t.cpu.totalLoadPercent),
                    subtitle: "Load • Up \(ByteFormat.uptime(t.cpu.uptimeSeconds))",
                    actionTitle: nil,
                    onAction: {},
                    onTap: { expandedCard = .cpu }
                )
            }

            // Battery & Thermal + Live Network Guard Row
            HStack(spacing: 10) {
                let thermalSuffix = "Thermal: \(t.thermal.state.shortLabel)"
                let batSub: String = {
                    if t.battery.isPresent {
                        let wStr = t.battery.powerWatts.map { String(format: " • %.1fW", $0) } ?? ""
                        return "Health \(t.battery.healthPercent)% • \(t.battery.cycleCount) cyc\(wStr)\n\(thermalSuffix)"
                    }
                    return "AC Power • \(thermalSuffix)"
                }()

                monitorCard(
                    title: "Battery & Thermal",
                    icon: t.battery.isCharging ? "battery.100.bolt" : "thermometer.medium",
                    tint: Color(hex: t.thermal.state == .nominal ? "34D399" : t.thermal.state.accentHex),
                    value: t.battery.isPresent ? "\(t.battery.percentage)%" : t.thermal.state.shortLabel,
                    subtitle: batSub,
                    actionTitle: nil,
                    onAction: {},
                    onTap: { expandedCard = .battery }
                )

                let topNetApp = t.topNetworkConsumers.first(where: { $0.totalRateBytesPerSec > 0 }) ?? t.topNetworkConsumers.first
                let netSub = topNetApp != nil
                    ? "↑ \(ByteFormat.speed(t.network.uploadBytesPerSec)) • \(topNetApp!.name)"
                    : "↑ \(ByteFormat.speed(t.network.uploadBytesPerSec)) • \(t.network.connectionType)"

                monitorCard(
                    title: "Network Guard",
                    icon: "network",
                    tint: Color(hex: "60A5FA"),
                    value: ByteFormat.speed(t.network.downloadBytesPerSec),
                    subtitle: netSub,
                    actionTitle: t.network.isTestingSpeed ? "Testing..." : "Test Speed",
                    onAction: { appState.runNetworkSpeedTest() },
                    onTap: {
                        expandedCard = .network
                        appState.refreshTelemetry(includeHeavy: true, includeNetworkProcesses: true)
                        appState.refreshListeningPorts(silent: true)
                    }
                )
            }

            // External Drives Strip
            if !t.externalDrives.isEmpty {
                HStack {
                    Image(systemName: "externaldrive.connected.to.line.below").foregroundStyle(.cyan)
                    Text("\(t.externalDrives.count) External Drive(s) Connected")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Manage") { expandedCard = .drives }
                        .font(.caption.bold())
                        .buttonStyle(.link)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
            }

            // Today's Recommendation
            if appState.settings.enableMenuRecommendations, let topRec = appState.recommendations.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's Recommendation")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: topRec.iconName).foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(topRec.title).font(.system(size: 12, weight: .semibold))
                            Text(topRec.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button(topRec.actionTitle) {
                            appState.handleRecommendation(topRec)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    private func monitorCard(
        title: String,
        icon: String,
        tint: Color,
        value: String,
        subtitle: String,
        actionTitle: String?,
        onAction: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 24, alignment: .topLeading)

            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.secondary.opacity(0.12)))
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onTapGesture(perform: onTap)
    }

    // MARK: - Expanded Detailed Sub-Views

    @ViewBuilder
    private func detailOverlay(for card: DetailCard) -> some View {
        let t = appState.telemetry
        VStack(alignment: .leading, spacing: 10) {
            Button {
                expandedCard = nil
            } label: {
                Label("Back to Dashboard", systemImage: "chevron.left")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)

            switch card {
            case .storage:
                Text("Storage — \(t.storage.volumeName)").font(.headline)
                ProgressView(value: t.storage.usedPercent, total: 100)
                detailRow("Total Capacity", ByteFormat.string(t.storage.totalBytes))
                detailRow("Used Space", ByteFormat.string(t.storage.usedBytes))
                detailRow("Available Space", ByteFormat.string(t.storage.availableBytes))
                detailRow("Purgeable Space", ByteFormat.string(t.storage.purgeableBytes))
                detailRow("Trash Bin", ByteFormat.string(t.storage.trashBytes))
                Button("Empty Trash") { appState.quickEmptyTrash() }.buttonStyle(.borderedProminent).controlSize(.small)

            case .memory:
                Text("Memory Breakdown").font(.headline)
                // Visual segmented RAM bar (Active / Wired / Compressed / Available)
                GeometryReader { geo in
                    let total = max(1, Double(t.memory.totalBytes))
                    let activeW = geo.size.width * CGFloat(Double(t.memory.activeBytes) / total)
                    let wiredW = geo.size.width * CGFloat(Double(t.memory.wiredBytes) / total)
                    let compW = geo.size.width * CGFloat(Double(t.memory.compressedBytes) / total)
                    HStack(spacing: 1) {
                        Rectangle().fill(Color(hex: "A855F7")).frame(width: max(2, activeW))
                        Rectangle().fill(Color(hex: "FF6B4A")).frame(width: max(2, wiredW))
                        Rectangle().fill(Color(hex: "FFD166")).frame(width: max(2, compW))
                        Rectangle().fill(Color.white.opacity(0.14))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                detailRow("Active", ByteFormat.string(t.memory.activeBytes))
                detailRow("Wired", ByteFormat.string(t.memory.wiredBytes))
                detailRow("Compressed", ByteFormat.string(t.memory.compressedBytes))
                detailRow("Available", ByteFormat.string(t.memory.availableBytes))
                detailRow("Swap Used", ByteFormat.string(t.memory.swapUsedBytes))
                Button("Free Up RAM") { appState.quickFreeUpRAM() }.buttonStyle(.borderedProminent).controlSize(.small)
                Divider()
                Text("Top Memory Consumers").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(t.topMemoryConsumers) { proc in
                    HStack {
                        Text(proc.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(proc.memoryBytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if proc.id > 1 && proc.id != getpid() && proc.name != "kernel_task" && proc.name != "launchd" {
                            Button("Quit") {
                                _ = appState.telemetryService.terminateProcess(pid: proc.id)
                                appState.refreshTelemetry(includeHeavy: true)
                            }
                            .controlSize(.mini)
                        }
                    }
                }

            case .cpu:
                Text("CPU Load & Top Consumers").font(.headline)
                // Real-time CPU History Sparkline Chart
                Canvas { ctx, size in
                    let pts = t.cpu.history
                    guard pts.count > 1 else { return }
                    var line = Path()
                    var fill = Path()
                    let stepX = size.width / CGFloat(pts.count - 1)
                    for (i, v) in pts.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = size.height - (CGFloat(min(100, max(0, v))) / 100.0) * size.height
                        if i == 0 {
                            line.move(to: CGPoint(x: x, y: y))
                            fill.move(to: CGPoint(x: x, y: size.height))
                            fill.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            line.addLine(to: CGPoint(x: x, y: y))
                            fill.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(Gradient(colors: [Color(hex: "FF6B4A").opacity(0.45), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.stroke(line, with: .color(Color(hex: "FF6B4A")), lineWidth: 2)
                }
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.20)))
                detailRow("User", String(format: "%.1f%%", t.cpu.userPercent))
                detailRow("System", String(format: "%.1f%%", t.cpu.systemPercent))
                detailRow("Idle", String(format: "%.1f%%", t.cpu.idlePercent))
                detailRow("Uptime", ByteFormat.uptime(t.cpu.uptimeSeconds))
                detailRow("Cores", "\(t.cpu.coreCount)")
                Divider()
                Text("Top CPU Consumers").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(t.topCPUConsumers) { proc in
                    HStack {
                        Text(proc.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", proc.cpuPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if proc.id > 1 && proc.id != getpid() && proc.name != "kernel_task" && proc.name != "launchd" {
                            Button("Quit") {
                                _ = appState.telemetryService.terminateProcess(pid: proc.id)
                                appState.refreshTelemetry(includeHeavy: true)
                            }
                            .controlSize(.mini)
                        }
                    }
                }

            case .battery:
                Text("Battery & Thermal Guard").font(.headline)
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: t.thermal.state.accentHex))
                        .frame(width: 9, height: 9)
                    Text("Thermal Pressure: \(t.thermal.state.rawValue)")
                        .font(.callout.bold())
                    Spacer()
                    if t.thermal.isLowPowerMode {
                        Text("Low Power")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.22)))
                    }
                }
                Text(t.thermal.state.descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let temp = t.battery.temperatureCelsius {
                    detailRow("Sensor Temperature", String(format: "%.1f °C", temp))
                }
                if let watts = t.battery.powerWatts {
                    detailRow(t.battery.isCharging ? "Charging Power" : "Power Draw", String(format: "%.1f W", watts))
                }
                Divider()
                detailRow("Battery Status", t.battery.statusText)
                if t.battery.isPresent {
                    detailRow("Charge Level", "\(t.battery.percentage)%")
                    detailRow("Battery Health", "\(t.battery.healthPercent)%")
                    detailRow("Cycle Count", "\(t.battery.cycleCount)")
                    detailRow("Condition", t.battery.condition)
                }

            case .network:
                Text("Live Network Guard").font(.headline)
                detailRow("Network", "\(t.network.networkName) (\(t.network.connectionType))")
                detailRow("Security", t.network.securityRating)
                detailRow("Total Download", "↓ \(ByteFormat.speed(t.network.downloadBytesPerSec))")
                detailRow("Total Upload", "↑ \(ByteFormat.speed(t.network.uploadBytesPerSec))")
                if let mbps = t.network.lastSpeedTestMbps {
                    detailRow("Last Speed Test", String(format: "%.1f Mbps", mbps))
                }
                Button(t.network.isTestingSpeed ? "Testing Connection..." : "Test Connection Speed") {
                    appState.runNetworkSpeedTest()
                }
                .disabled(t.network.isTestingSpeed)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Divider()
                HStack {
                    Text("Per-App Live Bandwidth").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { appState.refreshTelemetry(includeHeavy: true, includeNetworkProcesses: true) }
                        .font(.caption2)
                        .buttonStyle(.link)
                }
                if t.topNetworkConsumers.isEmpty {
                    Text("Collecting per-app socket rates...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(t.topNetworkConsumers.prefix(6)) { proc in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(proc.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text("Total: ↓\(ByteFormat.string(proc.totalInBytes)) ↑\(ByteFormat.string(proc.totalOutBytes))")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("↓ \(ByteFormat.speed(proc.downloadBytesPerSec))")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color(hex: "36E2F8"))
                                Text("↑ \(ByteFormat.speed(proc.uploadBytesPerSec))")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color(hex: "FFB703"))
                            }
                            if proc.id > 1 && proc.id != getpid() && proc.name != "kernel_task" && proc.name != "launchd" {
                                Button("Quit") {
                                    _ = appState.telemetryService.terminateProcess(pid: proc.id)
                                    appState.refreshTelemetry(includeHeavy: true)
                                }
                                .controlSize(.mini)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()
                HStack {
                    Text("Active Local Ports").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Port Killer") {
                        appState.selectedModule = .portKiller
                        openMainWindow()
                    }
                    .font(.caption2.bold())
                    .buttonStyle(.link)
                }
                let devPorts = appState.portKillerSnapshot.items.filter { !$0.isSystemProtected }.prefix(5)
                if devPorts.isEmpty {
                    Text("No active dev ports detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(devPorts)) { portItem in
                        HStack(spacing: 6) {
                            Text(":\(String(portItem.port))")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "00F5D4"))
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(portItem.displayTitle)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text(portItem.frameworkLabel)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Kill") {
                                appState.killListeningPort(portItem, force: true)
                            }
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 1)
                    }
                }

            case .alerts:
                Text("Clear Smart Alerts").font(.headline)
                Text("Configure exact thresholds for live HUD & Clear voice alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable Clear Smart Alerts", isOn: $appState.settings.enableClearSmartAlerts)
                    .font(.callout.bold())

                if appState.settings.enableClearSmartAlerts {
                    Divider()
                    Stepper("Low Disk: < \(appState.settings.warnLowDiskSpaceGB) GB", value: $appState.settings.warnLowDiskSpaceGB, in: 1...100, step: 1)
                        .font(.caption)

                    Toggle("High RAM Pressure Alert", isOn: $appState.settings.notifyLowRAM)
                        .font(.caption)
                    if appState.settings.notifyLowRAM {
                        Stepper("RAM Threshold: ≥ \(appState.settings.ramAlertThresholdPercent)%", value: $appState.settings.ramAlertThresholdPercent, in: 60...98, step: 5)
                            .font(.caption)
                    }

                    Toggle("Runaway CPU Process Alert", isOn: $appState.settings.notifyRunawayCPU)
                        .font(.caption)
                    if appState.settings.notifyRunawayCPU {
                        Stepper("CPU Threshold: ≥ \(appState.settings.runawayCPUThresholdPercent)%", value: $appState.settings.runawayCPUThresholdPercent, in: 50...300, step: 10)
                            .font(.caption)
                        Stepper("Sustained For: \(appState.settings.runawayCPUDurationSeconds)s", value: $appState.settings.runawayCPUDurationSeconds, in: 15...300, step: 15)
                            .font(.caption)
                    }

                    Toggle("Thermal Throttling Alert", isOn: $appState.settings.notifyThermalPressure)
                        .font(.caption)

                    Stepper("Alert Cooldown: \(appState.settings.smartAlertCooldownMinutes) min", value: $appState.settings.smartAlertCooldownMinutes, in: 1...60, step: 1)
                        .font(.caption)
                }

            case .protection:
                Text("Real-Time Protection").font(.headline)
                Toggle("Enable Malware Monitor", isOn: $appState.settings.enableRealTimeMalwareMonitor)
                Toggle("Look for threats in background", isOn: $appState.settings.enableBackgroundScan)
                detailRow("Scan Mode", appState.settings.malwareScanMode.rawValue)
                detailRow("Items Scanned", "\(appState.stats.totalMalwareItemsScanned)")

            case .drives:
                HStack {
                    Text("Connected External Drives").font(.headline)
                    Spacer()
                    if t.externalDrives.count > 1 {
                        Button("Eject All") {
                            let paths = t.externalDrives.map(\.mountPath)
                            let service = appState.telemetryService
                            Task.detached(priority: .userInitiated) {
                                var ejected = 0
                                for p in paths {
                                    if service.ejectDrive(at: p) { ejected += 1 }
                                }
                                let ejectedCount = ejected
                                await MainActor.run {
                                    appState.showBanner("Ejected \(ejectedCount) of \(paths.count) drive(s)")
                                    appState.refreshTelemetry(includeHeavy: true)
                                }
                            }
                        }
                        .controlSize(.mini)
                    }
                }
                ForEach(t.externalDrives) { drive in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(drive.name).font(.callout.bold())
                            Text("Available: \(ByteFormat.string(drive.availableBytes)) • Junk: \(ByteFormat.string(drive.junkBytes))").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Eject") {
                            let path = drive.mountPath
                            let name = drive.name
                            let service = appState.telemetryService
                            Task.detached(priority: .userInitiated) {
                                let ok = service.ejectDrive(at: path)
                                await MainActor.run {
                                    appState.showBanner(ok ? "Ejected \(name)" : "Could not eject \(name) (in use)")
                                    appState.refreshTelemetry(includeHeavy: true)
                                }
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.10)))
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold())
        }
    }
}
