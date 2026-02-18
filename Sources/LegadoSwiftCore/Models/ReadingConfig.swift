import SwiftUI

// MARK: - Font Family

public enum FontFamily: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case song = "Song"       // 宋体
    case kai = "Kai"         // 楷体
    case hei = "Hei"         // 黑体
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system: return "系统"
        case .serif: return "衬线"
        case .song: return "宋体"
        case .kai: return "楷体"
        case .hei: return "黑体"
        }
    }
    
    // 实际使用的字体名称
    public var fontName: String {
        switch self {
        case .system: return ".AppleSystemUIFont"
        case .serif: return "Times New Roman"
        case .song: return "Songti SC"
        case .kai: return "Kaiti SC"
        case .hei: return "Heiti SC"
        }
    }
    
    public var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .song: return .serif
        case .kai: return .serif
        case .hei: return .default
        }
    }
}

// MARK: - Reading Config

@Observable
public class ReadingConfig {
    public var fontSize: Double = 18
    public var lineSpacing: Double = 8
    public var paragraphSpacing: Double = 12
    public var fontFamily: FontFamily = .serif
    public var fontName: String = "System"
    public var theme: ReadingTheme = .dark
    public var margins: Double = 40
    public var contentWidth: Double = 720  // 内容区域最大宽度
    
    // 高级设置
    public var letterSpacing: Double = 0.5  // 字间距
    public var firstLineIndent: Bool = true // 首行缩进

    private static let configURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoSwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reading_config.json")
    }()

    public init() {
        load()
    }

    public func save() {
        let data: [String: Any] = [
            "fontSize": fontSize,
            "lineSpacing": lineSpacing,
            "paragraphSpacing": paragraphSpacing,
            "fontFamily": fontFamily.rawValue,
            "fontName": fontName,
            "theme": theme.rawValue,
            "margins": margins,
            "contentWidth": contentWidth,
            "letterSpacing": letterSpacing,
            "firstLineIndent": firstLineIndent,
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            try? jsonData.write(to: Self.configURL)
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        fontSize = dict["fontSize"] as? Double ?? 18
        lineSpacing = dict["lineSpacing"] as? Double ?? 8
        paragraphSpacing = dict["paragraphSpacing"] as? Double ?? 12
        if let familyStr = dict["fontFamily"] as? String {
            fontFamily = FontFamily(rawValue: familyStr) ?? .serif
        }
        fontName = dict["fontName"] as? String ?? "System"
        margins = dict["margins"] as? Double ?? 40
        contentWidth = dict["contentWidth"] as? Double ?? 720
        letterSpacing = dict["letterSpacing"] as? Double ?? 0.5
        firstLineIndent = dict["firstLineIndent"] as? Bool ?? true
        if let themeStr = dict["theme"] as? String {
            theme = ReadingTheme(rawValue: themeStr) ?? .dark
        }
    }
}