import Foundation

// MARK: - Book

public struct Book: Codable, Identifiable, Hashable {
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var author: String = ""
    public var filePath: String = ""
    public var coverUrl: String?
    public var intro: String?
    public var bookType: BookFileType = .txt
    public var totalChapters: Int = 0
    public var currentChapterIndex: Int = 0
    public var currentPosition: Int = 0
    public var addTime: Date = Date()
    public var lastReadTime: Date?
    public var origin: String = "local"
    public var originName: String = "本地"

    // Online book fields
    public var bookUrl: String?
    public var tocUrl: String?
    public var bookSourceUrl: String?
    public var kind: String?
    public var latestChapterTitle: String?
    public var isOnlineBook: Bool = false

    public enum BookFileType: String, Codable {
        case txt
        case epub
        case online
        case unknown

        static func from(path: String) -> BookFileType {
            let ext = (path as NSString).pathExtension.lowercased()
            switch ext {
            case "txt": return .txt
            case "epub": return .epub
            default: return .unknown
            }
        }
    }

    public init() {}
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Book, rhs: Book) -> Bool {
        lhs.id == rhs.id
    }

    var displayCover: String? {
        coverUrl
    }

    public var progressText: String {
        guard totalChapters > 0 else { return "未开始" }
        let pct = Int(Double(currentChapterIndex) / Double(totalChapters) * 100)
        return "\(pct)%"
    }

    /// Create a Book from a SearchBook result
    public static func fromSearchBook(_ searchBook: SearchBook) -> Book {
        var book = Book()
        book.name = searchBook.name
        book.author = searchBook.author
        book.coverUrl = searchBook.coverUrl
        book.intro = searchBook.intro
        book.kind = searchBook.kind
        book.latestChapterTitle = searchBook.latestChapterTitle
        book.bookUrl = searchBook.bookUrl
        book.bookSourceUrl = searchBook.bookSourceUrl
        book.origin = searchBook.origin
        book.originName = searchBook.originName
        book.bookType = .online
        book.isOnlineBook = true
        return book
    }
}

// MARK: - BookChapter

public struct BookChapter: Codable, Identifiable, Hashable {
    public var id: String { "\(bookId)_\(index)" }
    public var bookId: String
    public var index: Int
    public var title: String
    public var startOffset: Int = 0
    public var endOffset: Int = 0
    public var contentFile: String?
    public var chapterUrl: String?
    
    public init(bookId: String, index: Int, title: String, startOffset: Int = 0, endOffset: Int = 0, contentFile: String? = nil, chapterUrl: String? = nil) {
        self.bookId = bookId
        self.index = index
        self.title = title
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.contentFile = contentFile
        self.chapterUrl = chapterUrl
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: BookChapter, rhs: BookChapter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - SearchBook

public struct SearchBook: Identifiable, Hashable {
    public var id: String { bookUrl }
    public var bookUrl: String = ""
    public var bookSourceUrl: String = ""
    public var name: String = ""
    public var author: String = ""
    public var coverUrl: String?
    public var intro: String?
    public var kind: String?
    public var wordCount: String?
    public var latestChapterTitle: String?
    public var origin: String = ""
    public var originName: String = ""
    
    public init(bookUrl: String, bookSourceUrl: String, name: String, author: String, coverUrl: String?, intro: String?, kind: String?, latestChapterTitle: String?, origin: String, originName: String) {
        self.bookUrl = bookUrl
        self.bookSourceUrl = bookSourceUrl
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.intro = intro
        self.kind = kind
        self.latestChapterTitle = latestChapterTitle
        self.origin = origin
        self.originName = originName
    }
}

// MARK: - Bookmark

public struct Bookmark: Codable, Identifiable, Hashable {
    public var id: String = UUID().uuidString
    public var bookId: String
    public var chapterIndex: Int
    public var chapterTitle: String
    public var scrollOffset: Double = 0  // 滚动位置
    public var previewText: String = ""  // 预览文本
    public var createTime: Date = Date()
    public var note: String?  // 用户备注
    
    public init(bookId: String, chapterIndex: Int, chapterTitle: String, scrollOffset: Double = 0, previewText: String = "", note: String? = nil) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.scrollOffset = scrollOffset
        self.previewText = previewText
        self.note = note
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Bookmark, rhs: Bookmark) -> Bool {
        lhs.id == rhs.id
    }
}
