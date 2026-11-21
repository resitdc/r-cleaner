import SwiftUI

// MARK: - Exact Aspect-Preserving Vector Shapes from resitdc.svg (viewBox: 0 0 130 93)

/// Left interlocking neon-cyan ribbon path:
/// M81 25 L43 92.5 H27 L0 46 L27 0 H42.5 L16 46 L34.5 79.5 L65.5 25 H81 Z
public struct ResitdcCyanShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 130.0, rect.height / 93.0)
        let ox = rect.minX + (rect.width - 130.0 * scale) / 2.0
        let oy = rect.minY + (rect.height - 93.0 * scale) / 2.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }
        var p = Path()
        p.move(to: pt(81, 25))
        p.addLine(to: pt(43, 92.5))
        p.addLine(to: pt(27, 92.5))
        p.addLine(to: pt(0, 46))
        p.addLine(to: pt(27, 0))
        p.addLine(to: pt(42.5, 0))
        p.addLine(to: pt(16, 46))
        p.addLine(to: pt(34.5, 79.5))
        p.addLine(to: pt(65.5, 25))
        p.addLine(to: pt(81, 25))
        p.closeSubpath()
        return p
    }
}

/// Right interlocking white ribbon path:
/// M50 14 L57.5 0 H102.5 L129.5 46 L102.5 92.5 H87.5 L72.5 67 L80 54 L95 79.5 L114 46 L95 14 H50 Z
public struct ResitdcWhiteShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 130.0, rect.height / 93.0)
        let ox = rect.minX + (rect.width - 130.0 * scale) / 2.0
        let oy = rect.minY + (rect.height - 93.0 * scale) / 2.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }
        var p = Path()
        p.move(to: pt(50, 14))
        p.addLine(to: pt(57.5, 0))
        p.addLine(to: pt(102.5, 0))
        p.addLine(to: pt(129.5, 46))
        p.addLine(to: pt(102.5, 92.5))
        p.addLine(to: pt(87.5, 92.5))
        p.addLine(to: pt(72.5, 67))
        p.addLine(to: pt(80, 54))
        p.addLine(to: pt(95, 79.5))
        p.addLine(to: pt(114, 46))
        p.addLine(to: pt(95, 14))
        p.addLine(to: pt(50, 14))
        p.closeSubpath()
        return p
    }
}

/// Clean frameless crisp vector logo preserving the exact 130:93 SVG aspect ratio.
public struct ResitdcLogoMark: View {
    public var height: CGFloat
    public var glow: Bool

    public init(height: CGFloat = 24, glow: Bool = false) {
        self.height = height
        self.glow = glow
    }

    public var body: some View {
        let width = height * (130.0 / 93.0)
        ZStack {
            ResitdcCyanShape()
                .fill(Color(hex: "19F8FF"))
                .shadow(color: glow ? Color(hex: "19F8FF").opacity(0.65) : .clear, radius: glow ? 10 : 0)
            ResitdcWhiteShape()
                .fill(Color.white)
                .shadow(color: glow ? Color.white.opacity(0.4) : .clear, radius: glow ? 6 : 0)
        }
        .frame(width: width, height: height)
    }
}
