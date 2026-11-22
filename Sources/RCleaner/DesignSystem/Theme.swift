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
                secondary: Color(hex: "00F5D4"),
                accent: Color(hex: "22D3EE"),
                backgroundTop: Color(hex: "0A1D2E"),
                backgroundMid: Color(hex: "102B44"),
                backgroundBottom: Color(hex: "06111C")
            )
        case .devAISweeper:
            return ModulePalette(
                primary: Color(hex: "10B981"),
                secondary: Color(hex: "84CC16"),
                accent: Color(hex: "A3E635"),
                backgroundTop: Color(hex: "081F1A"),
                backgroundMid: Color(hex: "0D3128"),
                backgroundBottom: Color(hex: "05120F")
            )
        case .portKiller:
            return ModulePalette(
                primary: Color(hex: "F59E0B"),
                secondary: Color(hex: "F97316"),
                accent: Color(hex: "FBBF24"),
                backgroundTop: Color(hex: "221509"),
                backgroundMid: Color(hex: "331F0D"),
                backgroundBottom: Color(hex: "130C05")
            )
        case .cryoFreezer:
            return ModulePalette(
                primary: Color(hex: "38BDF8"),
                secondary: Color(hex: "3B82F6"),
                accent: Color(hex: "7DD3FC"),
                backgroundTop: Color(hex: "07182B"),
                backgroundMid: Color(hex: "0D2847"),
                backgroundBottom: Color(hex: "040E1A")
            )
        case .emailCleanup:
            return ModulePalette(
                primary: Color(hex: "EC4899"),
                secondary: Color(hex: "F43F5E"),
                accent: Color(hex: "F472B6"),
                backgroundTop: Color(hex: "24112E"),
                backgroundMid: Color(hex: "371742"),
                backgroundBottom: Color(hex: "14091B")
            )
        case .myTools:
            return ModulePalette(
                primary: Color(hex: "8B5CF6"),
                secondary: Color(hex: "6366F1"),
                accent: Color(hex: "C084FC"),
                backgroundTop: Color(hex: "17122E"),
                backgroundMid: Color(hex: "231B44"),
                backgroundBottom: Color(hex: "0D0A1B")
            )
        case .myActivity:
            return ModulePalette(
                primary: Color(hex: "FB7185"),
                secondary: Color(hex: "F97316"),
                accent: Color(hex: "FF8A65"),
                backgroundTop: Color(hex: "251219"),
                backgroundMid: Color(hex: "381A24"),
                backgroundBottom: Color(hex: "150A0E")
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
