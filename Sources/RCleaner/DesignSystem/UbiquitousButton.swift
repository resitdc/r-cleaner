import SwiftUI

/// Futuristic arc-reactor inspired glowing circular footer action button.
public struct UbiquitousButton: View {
    public let title: String
    public let subtitle: String?
    public let palette: ModulePalette
    public let isRunning: Bool
    public let isDisabled: Bool
    public let action: () -> Void

    @State private var isHovered = false

    public init(
        title: String,
        subtitle: String? = nil,
        palette: ModulePalette,
        isRunning: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        self.isRunning = isRunning
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Soft outer HUD energy halo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "19F8FF").opacity(isHovered ? 0.34 : 0.16), palette.primary.opacity(isHovered ? 0.28 : 0.14), .clear],
                            center: .center,
                            startRadius: 24,
                            endRadius: 60
                        )
                    )
                    .frame(width: 118, height: 118)

                // Segmented precision outer ring (Stark HUD style)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "19F8FF").opacity(isHovered ? 0.9 : 0.55), palette.primary.opacity(0.65), Color.white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: isRunning ? 2.5 : 1.5, dash: [18, 6])
                    )
                    .frame(width: 98, height: 98)

                // Crisp inner ring
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 90, height: 90)

                // Core glass energy sphere
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDisabled
                                ? [Color.white.opacity(0.10), Color.white.opacity(0.05)]
                                : [palette.primary.opacity(0.95), palette.secondary.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(isHovered ? 0.85 : 0.50), Color(hex: "19F8FF").opacity(0.45), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.4
                            )
                    )
                    .shadow(color: palette.primary.opacity(isDisabled ? 0 : 0.45), radius: isHovered ? 18 : 10, y: 4)
                    .scaleEffect(isHovered && !isDisabled ? 1.05 : 1.0)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 118, height: 118)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
    }
}
