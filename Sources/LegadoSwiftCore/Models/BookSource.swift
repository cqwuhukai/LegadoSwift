import Foundation

// MARK: - BookSource (兼容 legado JSON 格式)

public struct BookSource: Codable, Identifiable, Hashable {
    public var bookSourceUrl: String = ""
    public var bookSourceName: String = ""
    public var bookSourceGroup: String?
    public var bookSourceType: Int = 0
    public var bookUrlPattern: String?
    public var customOrder: Int = 0
    public var enabled: Bool = true
    public var enabledExplore: Bool = true
    public var enabledCookieJar: Bool = false
    public var header: String?
    public var loginUrl: String?
    public var loginCheckJs: String?
    public var bookSourceComment: String?
    public var lastUpdateTime: Int64 = 0
    public var respondTime: Int64 = 180000
    public var weight: Int = 0
    public var exploreUrl: String?
    public var searchUrl: String?
    public var ruleSearch: SearchRule?
    public var ruleExplore: ExploreRule?
    public var ruleBookInfo: BookInfoRule?
    public var ruleToc: TocRule?
    public var ruleContent: ContentRule?
    
    public init() {}

    // Custom decoder to handle flexible JSON types (String vs Int, unknown keys, etc.)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        
        bookSourceUrl = (try? container.decodeFlexibleString(forKey: "bookSourceUrl")) ?? ""
        bookSourceName = (try? container.decodeFlexibleString(forKey: "bookSourceName")) ?? ""
        bookSourceGroup = try? container.decodeFlexibleString(forKey: "bookSourceGroup")
        bookSourceType = (try? container.decodeFlexibleInt(forKey: "bookSourceType")) ?? 0
        bookUrlPattern = try? container.decodeFlexibleString(forKey: "bookUrlPattern")
        customOrder = (try? container.decodeFlexibleInt(forKey: "customOrder")) ?? 0
        enabled = (try? container.decodeFlexibleBool(forKey: "enabled")) ?? true
        enabledExplore = (try? container.decodeFlexibleBool(forKey: "enabledExplore")) ?? true
        enabledCookieJar = (try? container.decodeFlexibleBool(forKey: "enabledCookieJar")) ?? false
        header = try? container.decodeFlexibleString(forKey: "header")
        loginUrl = try? container.decodeFlexibleString(forKey: "loginUrl")
        loginCheckJs = try? container.decodeFlexibleString(forKey: "loginCheckJs")
        bookSourceComment = try? container.decodeFlexibleString(forKey: "bookSourceComment")
        lastUpdateTime = (try? container.decodeFlexibleInt64(forKey: "lastUpdateTime")) ?? 0
        respondTime = (try? container.decodeFlexibleInt64(forKey: "respondTime")) ?? 180000
        weight = (try? container.decodeFlexibleInt(forKey: "weight")) ?? 0
        exploreUrl = try? container.decodeFlexibleString(forKey: "exploreUrl")
        searchUrl = try? container.decodeFlexibleString(forKey: "searchUrl")
        
        ruleSearch = try? container.decode(SearchRule.self, forKey: FlexibleCodingKey(stringValue: "ruleSearch"))
        ruleExplore = try? container.decode(ExploreRule.self, forKey: FlexibleCodingKey(stringValue: "ruleExplore"))
        ruleBookInfo = try? container.decode(BookInfoRule.self, forKey: FlexibleCodingKey(stringValue: "ruleBookInfo"))
        ruleToc = try? container.decode(TocRule.self, forKey: FlexibleCodingKey(stringValue: "ruleToc"))
        ruleContent = try? container.decode(ContentRule.self, forKey: FlexibleCodingKey(stringValue: "ruleContent"))
    }

    public var id: String { bookSourceUrl }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bookSourceUrl)
    }

    public static func == (lhs: BookSource, rhs: BookSource) -> Bool {
        lhs.bookSourceUrl == rhs.bookSourceUrl
    }

    public var sourceTypeDescription: String {
        switch bookSourceType {
        case 0: return "文本"
        case 1: return "音频"
        case 2: return "图片"
        case 3: return "文件"
        default: return "未知"
        }
    }

    public var groups: [String] {
        bookSourceGroup?
            .components(separatedBy: CharacterSet(charactersIn: ",;，；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
    }
}

// MARK: - FlexibleCodingKey

/// Allows decoding with arbitrary string keys, ignoring unknown fields
struct FlexibleCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Flexible Decoding Extensions

extension KeyedDecodingContainer where K == FlexibleCodingKey {
    
    func decodeFlexibleString(forKey keyName: String) throws -> String? {
        let key = FlexibleCodingKey(stringValue: keyName)
        guard contains(key) else { return nil }
        // Try String first
        if let val = try? decode(String.self, forKey: key) { return val }
        // Try Int
        if let val = try? decode(Int.self, forKey: key) { return String(val) }
        // Try Int64
        if let val = try? decode(Int64.self, forKey: key) { return String(val) }
        // Try Double
        if let val = try? decode(Double.self, forKey: key) { return String(val) }
        // Try Bool
        if let val = try? decode(Bool.self, forKey: key) { return String(val) }
        return nil
    }
    
    func decodeFlexibleInt(forKey keyName: String) throws -> Int? {
        let key = FlexibleCodingKey(stringValue: keyName)
        guard contains(key) else { return nil }
        if let val = try? decode(Int.self, forKey: key) { return val }
        if let val = try? decode(String.self, forKey: key) { return Int(val) }
        if let val = try? decode(Double.self, forKey: key) { return Int(val) }
        if let val = try? decode(Bool.self, forKey: key) { return val ? 1 : 0 }
        return nil
    }
    
    func decodeFlexibleInt64(forKey keyName: String) throws -> Int64? {
        let key = FlexibleCodingKey(stringValue: keyName)
        guard contains(key) else { return nil }
        if let val = try? decode(Int64.self, forKey: key) { return val }
        if let val = try? decode(Int.self, forKey: key) { return Int64(val) }
        if let val = try? decode(String.self, forKey: key) { return Int64(val) }
        if let val = try? decode(Double.self, forKey: key) { return Int64(val) }
        return nil
    }
    
    func decodeFlexibleBool(forKey keyName: String) throws -> Bool? {
        let key = FlexibleCodingKey(stringValue: keyName)
        guard contains(key) else { return nil }
        if let val = try? decode(Bool.self, forKey: key) { return val }
        if let val = try? decode(Int.self, forKey: key) { return val != 0 }
        if let val = try? decode(String.self, forKey: key) {
            return val == "true" || val == "1"
        }
        return nil
    }
}

// MARK: - SearchRule

public struct SearchRule: Codable, Hashable {
    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?
    
    public init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        checkKeyWord = try? container.decodeFlexibleString(forKey: "checkKeyWord")
        bookList = try? container.decodeFlexibleString(forKey: "bookList")
        name = try? container.decodeFlexibleString(forKey: "name")
        author = try? container.decodeFlexibleString(forKey: "author")
        intro = try? container.decodeFlexibleString(forKey: "intro")
        kind = try? container.decodeFlexibleString(forKey: "kind")
        lastChapter = try? container.decodeFlexibleString(forKey: "lastChapter")
        updateTime = try? container.decodeFlexibleString(forKey: "updateTime")
        bookUrl = try? container.decodeFlexibleString(forKey: "bookUrl")
        coverUrl = try? container.decodeFlexibleString(forKey: "coverUrl")
        wordCount = try? container.decodeFlexibleString(forKey: "wordCount")
    }
}

// MARK: - ExploreRule

public struct ExploreRule: Codable, Hashable {
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?
    
    public init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        bookList = try? container.decodeFlexibleString(forKey: "bookList")
        name = try? container.decodeFlexibleString(forKey: "name")
        author = try? container.decodeFlexibleString(forKey: "author")
        intro = try? container.decodeFlexibleString(forKey: "intro")
        kind = try? container.decodeFlexibleString(forKey: "kind")
        lastChapter = try? container.decodeFlexibleString(forKey: "lastChapter")
        updateTime = try? container.decodeFlexibleString(forKey: "updateTime")
        bookUrl = try? container.decodeFlexibleString(forKey: "bookUrl")
        coverUrl = try? container.decodeFlexibleString(forKey: "coverUrl")
        wordCount = try? container.decodeFlexibleString(forKey: "wordCount")
    }
}

// MARK: - BookInfoRule

public struct BookInfoRule: Codable, Hashable {
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?
    public var canReName: String?
    
    public init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        name = try? container.decodeFlexibleString(forKey: "name")
        author = try? container.decodeFlexibleString(forKey: "author")
        intro = try? container.decodeFlexibleString(forKey: "intro")
        kind = try? container.decodeFlexibleString(forKey: "kind")
        lastChapter = try? container.decodeFlexibleString(forKey: "lastChapter")
        coverUrl = try? container.decodeFlexibleString(forKey: "coverUrl")
        tocUrl = try? container.decodeFlexibleString(forKey: "tocUrl")
        wordCount = try? container.decodeFlexibleString(forKey: "wordCount")
        canReName = try? container.decodeFlexibleString(forKey: "canReName")
    }
}

// MARK: - TocRule

public struct TocRule: Codable, Hashable {
    public var preUpdateJs: String?
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var formatJs: String?
    public var isVolume: String?
    public var nextTocUrl: String?
    
    public init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        preUpdateJs = try? container.decodeFlexibleString(forKey: "preUpdateJs")
        chapterList = try? container.decodeFlexibleString(forKey: "chapterList")
        chapterName = try? container.decodeFlexibleString(forKey: "chapterName")
        chapterUrl = try? container.decodeFlexibleString(forKey: "chapterUrl")
        formatJs = try? container.decodeFlexibleString(forKey: "formatJs")
        isVolume = try? container.decodeFlexibleString(forKey: "isVolume")
        nextTocUrl = try? container.decodeFlexibleString(forKey: "nextTocUrl")
    }
}

// MARK: - ContentRule

public struct ContentRule: Codable, Hashable {
    public var content: String?
    public var title: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
    public var imageStyle: String?
    
    public init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        content = try? container.decodeFlexibleString(forKey: "content")
        title = try? container.decodeFlexibleString(forKey: "title")
        nextContentUrl = try? container.decodeFlexibleString(forKey: "nextContentUrl")
        webJs = try? container.decodeFlexibleString(forKey: "webJs")
        sourceRegex = try? container.decodeFlexibleString(forKey: "sourceRegex")
        replaceRegex = try? container.decodeFlexibleString(forKey: "replaceRegex")
        imageStyle = try? container.decodeFlexibleString(forKey: "imageStyle")
    }
}
