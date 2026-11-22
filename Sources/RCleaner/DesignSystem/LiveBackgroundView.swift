import SwiftUI

/// High-performance GPU-friendly aurora gradient background for R-Cleaner.
/// Uses UnitPoint-anchored RadialGradients with zero GeometryReader, zero CPU blur passes,
/// and zero per-frame layout invalidation so idle CPU stays at 0%.
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
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundMid, palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [palette.primary.opacity(isActiveScan ? 0.36 : 0.25), .clear],
                center: UnitPoint(x: 0.22, y: 0.20),
                startRadius: 10,
                endRadius: 540
            )

            RadialGradient(
                colors: [palette.secondary.opacity(isActiveScan ? 0.32 : 0.21), .clear],
                center: UnitPoint(x: 0.80, y: 0.78),
                startRadius: 10,
                endRadius: 500
            )

            RadialGradient(
                colors: [palette.accent.opacity(isActiveScan ? 0.22 : 0.13), .clear],
                center: UnitPoint(x: 0.56, y: 0.36),
                startRadius: 5,
                endRadius: 380
            )

            // Subtle top-edge silk sheen for crisp depth
            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
