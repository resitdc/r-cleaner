import SwiftUI

/// Glowing circular primary footer action button for R-Cleaner modules.
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
                // Soft glow halo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.primary.opacity(isHovered ? 0.54 : 0.34), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 114, height: 114)

                // Outer crisp luminous ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [palette.primary.opacity(isRunning ? 0.88 : 0.58), palette.accent.opacity(0.48)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isRunning ? 3 : 1.75
                    )
                    .frame(width: 94, height: 94)

                // Main liquid-glass sphere
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDisabled
                                ? [Color.white.opacity(0.14), Color.white.opacity(0.08)]
                                : [palette.primary, palette.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.72 : 0.45),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: palette.primary.opacity(isDisabled ? 0 : 0.45), radius: isHovered ? 18 : 10, y: 4)
                    .scaleEffect(isHovered && !isDisabled ? 1.05 : 1.0)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 114, height: 114)
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
