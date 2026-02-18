import SwiftUI

// MARK: - Color Hex Init

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - App Theme

public enum AppTheme {
    // Backgrounds
    public static let bgPrimary = Color(hex: "0D1117")
    public static let bgSecondary = Color(hex: "161B22")
    public static let bgTertiary = Color(hex: "21262D")
    public static let bgElevated = Color(hex: "2D333B")

    // Text
    public static let textPrimary = Color(hex: "E6EDF3")
    public static let textSecondary = Color(hex: "8B949E")
    public static let textTertiary = Color(hex: "6E7681")

    // Accents
    public static let accent = Color(hex: "58A6FF")
    public static let accentGreen = Color(hex: "3FB950")
    public static let accentOrange = Color(hex: "D29922")
    public static let accentRed = Color(hex: "F85149")
    public static let accentPurple = Color(hex: "BC8CFF")

    // Borders
    public static let border = Color(hex: "30363D")

    // Card gradient for book covers
    public static func cardGradient(for string: String) -> LinearGradient {
        let hash = abs(string.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 7) % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: hue1, saturation: 0.5, brightness: 0.50),
                Color(hue: hue2, saturation: 0.6, brightness: 0.30),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Sidebar gradient
    public static let sidebarGradient = LinearGradient(
        colors: [Color(hex: "0F1923"), Color(hex: "0D1117")],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Reading Theme

public enum ReadingTheme: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case sepia
    case eyeProtection
    case paper
    case night

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .light: return "明亮"
        case .dark: return "暗黑"
        case .sepia: return "羊皮纸"
        case .eyeProtection: return "护眼"
        case .paper: return "纸张"
        case .night: return "夜间"
        }
    }

    public var bgColor: Color {
        switch self {
        case .light: return Color(hex: "FFFFFF")
        case .dark: return Color(hex: "1A1A2E")
        case .sepia: return Color(hex: "F4ECD8")
        case .eyeProtection: return Color(hex: "C7EDCC")
        case .paper: return Color(hex: "F5F5F0")
        case .night: return Color(hex: "0D0D0D")
        }
    }

    public var textColor: Color {
        switch self {
        case .light: return Color(hex: "1A1A1A")
        case .dark: return Color(hex: "D4D4D4")
        case .sepia: return Color(hex: "5B4636")
        case .eyeProtection: return Color(hex: "2D4A2D")
        case .paper: return Color(hex: "333333")
        case .night: return Color(hex: "AAAAAA")
        }
    }

    public var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        case .sepia: return "book.fill"
        case .eyeProtection: return "leaf.fill"
        case .paper: return "doc.text.fill"
        case .night: return "moon.fill"
        }
    }
    
    // Secondary text color for less important text
    public var secondaryTextColor: Color {
        textColor.opacity(0.6)
    }
}