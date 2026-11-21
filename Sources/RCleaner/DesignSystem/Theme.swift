import SwiftUI

// MARK: - Aurora Color & Glass Theme for R-Cleaner

public struct ModulePalette {
    public let primary: Color
    public let secondary: Color
    public let accent: Color
    public let backgroundTop: Color
    public let backgroundMid: Color
    public let backgroundBottom: Color
}

public enum RCleanerTheme {
    public static func palette(for module: RCleanerModule) -> ModulePalette {
        switch module {
        case .smartCare:
            return ModulePalette(
                primary: Color(hex: "FF4FD8"),
                secondary: Color(hex: "7B61FF"),
                accent: Color(hex: "36E2F8"),
                backgroundTop: Color(hex: "1B1035"),
                backgroundMid: Color(hex: "2B144A"),
                backgroundBottom: Color(hex: "110B22")
            )
        case .cleanup:
            return ModulePalette(
                primary: Color(hex: "F44B98"),
                secondary: Color(hex: "FF7A59"),
                accent: Color(hex: "FFB56B"),
                backgroundTop: Color(hex: "260F24"),
                backgroundMid: Color(hex: "3B1432"),
                backgroundBottom: Color(hex: "160A18")
            )
        case .protection:
            return ModulePalette(
                primary: Color(hex: "2ED573"),
                secondary: Color(hex: "1BC6B4"),
                accent: Color(hex: "6BF2C2"),
                backgroundTop: Color(hex: "0C2320"),
                backgroundMid: Color(hex: "10332C"),
                backgroundBottom: Color(hex: "071413")
            )
        case .performance:
            return ModulePalette(
                primary: Color(hex: "FF6B4A"),
                secondary: Color(hex: "FF9F43"),
                accent: Color(hex: "FFD166"),
                backgroundTop: Color(hex: "29140E"),
                backgroundMid: Color(hex: "3C1C12"),
                backgroundBottom: Color(hex: "160B08")
            )
        case .applications:
            return ModulePalette(
                primary: Color(hex: "3A86FF"),
                secondary: Color(hex: "5E60CE"),
                accent: Color(hex: "64DFDF"),
                backgroundTop: Color(hex: "0E1B33"),
                backgroundMid: Color(hex: "14294A"),
                backgroundBottom: Color(hex: "09101E")
            )
        case .myClutter:
            return ModulePalette(
                primary: Color(hex: "9B5DE5"),
                secondary: Color(hex: "F15BB5"),
                accent: Color(hex: "C77DFF"),
                backgroundTop: Color(hex: "211133"),
                backgroundMid: Color(hex: "31174B"),
                backgroundBottom: Color(hex: "12091E")
            )
        case .spaceLens:
            return ModulePalette(
                primary: Color(hex: "00BBF9"),
                secondary: Color(hex: "4361EE"),
                accent: Color(hex: "72EFDD"),
                backgroundTop: Color(hex: "0A1D2E"),
                backgroundMid: Color(hex: "102B44"),
                backgroundBottom: Color(hex: "06111C")
            )
        case .cloudCleanup:
            return ModulePalette(
                primary: Color(hex: "38BDF8"),
                secondary: Color(hex: "818CF8"),
                accent: Color(hex: "BAE6FD"),
                backgroundTop: Color(hex: "0D1E30"),
                backgroundMid: Color(hex: "162E4A"),
                backgroundBottom: Color(hex: "081320")
            )
        case .emailCleanup:
            return ModulePalette(
                primary: Color(hex: "F472B6"),
                secondary: Color(hex: "A855F7"),
                accent: Color(hex: "FBCFE8"),
                backgroundTop: Color(hex: "24112E"),
                backgroundMid: Color(hex: "371742"),
                backgroundBottom: Color(hex: "14091B")
            )
        case .myTools:
            return ModulePalette(
                primary: Color(hex: "60A5FA"),
                secondary: Color(hex: "34D399"),
                accent: Color(hex: "A7F3D0"),
                backgroundTop: Color(hex: "111D2B"),
                backgroundMid: Color(hex: "172B3C"),
                backgroundBottom: Color(hex: "0A121C")
            )
        case .myActivity:
            return ModulePalette(
                primary: Color(hex: "34D399"),
                secondary: Color(hex: "38BDF8"),
                accent: Color(hex: "A7F3D0"),
                backgroundTop: Color(hex: "0E2226"),
                backgroundMid: Color(hex: "133138"),
                backgroundBottom: Color(hex: "071417")
            )
        }
    }

    public static let cardBackground = Color.white.opacity(0.085)
    public static let cardBackgroundHover = Color.white.opacity(0.13)
    public static let cardBorder = Color.white.opacity(0.16)
    public static let cardBorderHover = Color.white.opacity(0.28)
    public static let sidebarBackground = Color.black.opacity(0.26)
}

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}
