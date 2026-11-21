import SwiftUI
import AppKit

/// Menu Bar Satellite Monitor built directly into R-Cleaner via MenuBarExtra.
public struct MenuBarMonitorView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedCard: DetailCard? = nil

    enum DetailCard: String {
        case storage, protection, memory, cpu, battery, network, drives
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ResitdcLogoMark(height: 16, glow: false)
                    Text("R-Cleaner Menu")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                Text("Health: \(appState.healthScore)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "2ED573"))
                    .padding(.horizontal, 8)
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
                    NSApp.activate(ignoringOtherApps: true)
                    if let win = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        win.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button {
                    appState.showSettingsWindow = true
                    NSApp.activate(ignoringOtherApps: true)
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
                        NSApp.activate(ignoringOtherApps: true)
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

            // Battery + Network Row
            HStack(spacing: 10) {
                monitorCard(
                    title: "Battery",
                    icon: t.battery.isCharging ? "battery.100.bolt" : "battery.75",
                    tint: Color(hex: "34D399"),
                    value: t.battery.isPresent ? "\(t.battery.percentage)%" : "AC",
                    subtitle: t.battery.isPresent ? "Health \(t.battery.healthPercent)% • \(t.battery.cycleCount) cyc" : "Desktop Power",
                    actionTitle: nil,
                    onAction: {},
                    onTap: { expandedCard = .battery }
                )

                monitorCard(
                    title: "Network",
                    icon: "wifi",
                    tint: Color(hex: "60A5FA"),
                    value: ByteFormat.speed(t.network.downloadBytesPerSec),
                    subtitle: "↑ \(ByteFormat.speed(t.network.uploadBytesPerSec)) • \(t.network.connectionType)",
                    actionTitle: t.network.isTestingSpeed ? "Testing..." : "Test Speed",
                    onAction: { appState.runNetworkSpeedTest() },
                    onTap: { expandedCard = .network }
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
                        Button("Quit") {
                            _ = appState.telemetryService.terminateProcess(pid: proc.id)
                            appState.refreshTelemetry(includeHeavy: true)
                        }
                        .controlSize(.mini)
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
                        Button("Quit") {
                            _ = appState.telemetryService.terminateProcess(pid: proc.id)
                            appState.refreshTelemetry(includeHeavy: true)
                        }
                        .controlSize(.mini)
                    }
                }

            case .battery:
                Text("Battery Details").font(.headline)
                detailRow("Status", t.battery.statusText)
                detailRow("Charge Level", "\(t.battery.percentage)%")
                detailRow("Health Capacity", "\(t.battery.healthPercent)%")
                detailRow("Cycle Count", "\(t.battery.cycleCount)")
                detailRow("Condition", t.battery.condition)
                if let temp = t.battery.temperatureCelsius {
                    detailRow("Temperature", String(format: "%.1f °C", temp))
                }

            case .network:
                Text("Network & Speed Test").font(.headline)
                detailRow("Network", t.network.networkName)
                detailRow("Type", t.network.connectionType)
                detailRow("Security", t.network.securityRating)
                detailRow("Download", ByteFormat.speed(t.network.downloadBytesPerSec))
                detailRow("Upload", ByteFormat.speed(t.network.uploadBytesPerSec))
                if let mbps = t.network.lastSpeedTestMbps {
                    detailRow("Last Speed Test", String(format: "%.1f Mbps", mbps))
                }
                Button(t.network.isTestingSpeed ? "Testing Connection..." : "Test Connection Speed") {
                    appState.runNetworkSpeedTest()
                }
                .disabled(t.network.isTestingSpeed)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

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
                            for d in t.externalDrives { _ = appState.telemetryService.ejectDrive(at: d.mountPath) }
                            appState.refreshTelemetry(includeHeavy: true)
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
                            _ = appState.telemetryService.ejectDrive(at: drive.mountPath)
                            appState.refreshTelemetry(includeHeavy: true)
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

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold())
        }
    }
}
