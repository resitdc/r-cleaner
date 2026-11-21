import SwiftUI

/// High-performance obsidian-aurora futuristic HUD background for R-Cleaner.
/// Zero GeometryReader, zero CPU blur passes, zero idle frame invalidation.
public struct LiveBackgroundView: View {
    public let module: RCleanerModule
    public let isActiveScan: Bool
    public let reduceMotion: Bool

    public init(module: RCleanerModule, isActiveScan: Bool = false, reduceMotion: Bool = false) {
        self.module = module
        self.isActiveScan = isActiveScan
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        let palette = RCleanerTheme.palette(for: module)

        ZStack {
            // Deep obsidian base for crisp contrast & futuristic clarity
            LinearGradient(
                colors: [Color(hex: "060913"), palette.backgroundTop.opacity(0.88), Color(hex: "050811")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Precision HUD radial light pools
            RadialGradient(
                colors: [palette.primary.opacity(isActiveScan ? 0.28 : 0.17), .clear],
                center: UnitPoint(x: 0.20, y: 0.16),
                startRadius: 10,
                endRadius: 500
            )

            RadialGradient(
                colors: [Color(hex: "19F8FF").opacity(isActiveScan ? 0.16 : 0.09), .clear],
                center: UnitPoint(x: 0.84, y: 0.22),
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [palette.secondary.opacity(isActiveScan ? 0.22 : 0.13), .clear],
                center: UnitPoint(x: 0.78, y: 0.84),
                startRadius: 10,
                endRadius: 460
            )

            // Ultra-subtle futuristic precision dot-grid overlay
            Canvas { ctx, size in
                let spacing: CGFloat = 34
                let dotColor = Color(hex: "19F8FF").opacity(0.045)
                var x: CGFloat = 17
                while x < size.width {
                    var y: CGFloat = 17
                    while y < size.height {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(dotColor))
                        y += spacing
                    }
                    x += spacing
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.50), value: module)
        .ignoresSafeArea()
    }
}
