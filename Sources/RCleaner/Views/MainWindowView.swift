import SwiftUI

public struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            if appState.showIntroFlow {
                IntroFlowView()
                    .environmentObject(appState)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                HStack(spacing: 0) {
                    sidebar
                    Divider().overlay(Color.white.opacity(0.08))
                    detailArea
                }
                .background(
                    LiveBackgroundView(
                        module: appState.selectedModule,
                        isActiveScan: appState.isAnyScanRunning,
                        reduceMotion: appState.settings.reduceMotion
                    )
                )
                .overlay(alignment: .top) {
                    if let message = appState.statusBannerMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: "2ED573"))
                            Text(message)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(radius: 12)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.showIntroFlow)
        .frame(minWidth: 1060, minHeight: 680)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showSettingsWindow) {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 780, height: 540)
        }
    }

    // MARK: - Translucent Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Brand Header with frameless resitdc.svg Logo
            HStack(spacing: 10) {
                ResitdcLogoMark(height: 24, glow: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("R-Cleaner")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("by resitdc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: "19F8FF").opacity(0.8))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(RCleanerModule.allCases.filter(\.isPrimarySection)) { module in
                        SidebarRowView(
                            module: module,
                            isSelected: appState.selectedModule == module
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                appState.selectedModule = module
                            }
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.10))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                    ForEach(RCleanerModule.allCases.filter { !$0.isPrimarySection }) { module in
                        SidebarRowView(
                            module: module,
                            isSelected: appState.selectedModule == module
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                appState.selectedModule = module
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // Bottom Disk Pill + Quick Settings + Screen Cleaning
            VStack(spacing: 8) {
                // Compact storage indicator
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(appState.telemetry.storage.volumeName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("\(ByteFormat.string(appState.telemetry.storage.availableBytes)) free")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "36E2F8"), Color(hex: "FF4FD8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * CGFloat(appState.telemetry.storage.usedPercent / 100.0)))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))

                HStack(spacing: 8) {
                    Button {
                        appState.showSettingsWindow = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.launchScreenCleaningMode()
                    } label: {
                        Image(systemName: "display")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 34, height: 28)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Screen Cleaning Mode")
                }
            }
            .padding(12)
        }
        .frame(width: 226)
        .background(RCleanerTheme.sidebarBackground)
    }

    // MARK: - Main Content Area + Top-Right Assistant Pill

    private var detailArea: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch appState.selectedModule {
                case .smartCare: SmartCareView()
                case .cleanup: CleanupView()
                case .protection: ProtectionView()
                case .performance: PerformanceView()
                case .applications: ApplicationsView()
                case .myClutter: MyClutterView()
                case .spaceLens: SpaceLensView()
                case .cloudCleanup: CloudCleanupView()
                case .emailCleanup: EmailCleanupView()
                case .myTools: MyToolsView()
                case .myActivity: MyActivityDashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Assistant Mac Health Button (Top-Right Pill)
            if appState.settings.showAssistantRecommendations {
                Button {
                    appState.showAssistantPopover.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(healthColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: healthColor, radius: 4)
                        Text("Assistant")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(appState.healthScore)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.28)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $appState.showAssistantPopover, arrowEdge: .bottom) {
                    AssistantPopoverView()
                        .environmentObject(appState)
                }
                .padding(.top, 12)
                .padding(.trailing, 18)
            }
        }
    }

    private var healthColor: Color {
        switch appState.healthRating {
        case .excellent, .good: return Color(hex: "2ED573")
        case .fair: return Color(hex: "FFD166")
        case .requiresAttention, .critical: return Color(hex: "FF5E57")
        }
    }
}

private struct SidebarRowView: View {
    let module: RCleanerModule
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let palette = RCleanerTheme.palette(for: module)

        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: module.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : palette.accent.opacity(0.9))
                }

                Text(module.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.78))

                Spacer()

                if let badge = module.badgeText {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.primary.opacity(0.85)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.15)
                            : (isHovered ? Color.white.opacity(0.07) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.20) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
