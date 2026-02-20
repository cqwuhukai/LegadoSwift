import Foundation

@Observable
public class BookManager {
    var books: [Book] = []
    var currentBook: Book?
    var chapters: [BookChapter] = []
    var currentChapterIndex: Int = 0
    var currentContent: String = ""
    var isReading: Bool = false
    var toastMessage: String?

    // Online book loading state
    var isLoading: Bool = false
    var loadingMessage: String?

    // Bookmarks
    var bookmarks: [Bookmark] = []

    // Reference to book source manager (set externally)
    public var sourceManager: BookSourceManager?

    private static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoSwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("books.json")
    }()
    
    private static let bookmarksURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoSwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bookmarks.json")
    }()

    public init() {
        loadBooks()
        loadBookmarks()
    }

    // MARK: - Add Local Book

    func addLocalBook(url: URL) throws {
        let bookType = Book.BookFileType.from(path: url.path)
        guard bookType != .unknown else {
            throw LegadoError.parseError("不支持的文件格式: \(url.pathExtension)")
        }

        // Copy to app support directory
        let booksDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoSwift/Books", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let destURL = booksDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: url, to: destURL)

        var book = Book()
        book.name = (url.lastPathComponent as NSString).deletingPathExtension
        book.filePath = destURL.path
        book.bookType = bookType

        // Parse to get chapter count
        let parsedChapters: [BookChapter]
        switch bookType {
        case .txt:
            parsedChapters = TxtReader.parseChapters(filePath: destURL.path, bookId: book.id)
        case .epub:
            let result = EpubReader.parse(filePath: destURL.path, bookId: book.id)
            book.name = result.title.isEmpty ? book.name : result.title
            book.author = result.author
            parsedChapters = result.chapters
        case .online, .unknown:
            parsedChapters = []
        }

        book.totalChapters = parsedChapters.count

        // Remove existing book with same name
        books.removeAll { $0.name == book.name && $0.filePath == book.filePath }
        books.insert(book, at: 0)
        saveBooks()
    }

    // MARK: - Add Search Book to Shelf

    func addSearchBook(_ searchBook: SearchBook) -> Bool {
        // Check if already in shelf
        if isBookInShelf(searchBook.bookUrl) {
            showToast("《\(searchBook.name)》已在书架中")
            return false
        }

        let book = Book.fromSearchBook(searchBook)
        books.insert(book, at: 0)
        saveBooks()
        showToast("《\(searchBook.name)》已加入书架")
        return true
    }

    /// Check if a book URL is already in the bookshelf
    func isBookInShelf(_ bookUrl: String) -> Bool {
        books.contains { $0.bookUrl == bookUrl }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    // MARK: - Open Book

    func openBook(_ book: Book) {
        currentBook = book
        currentChapterIndex = book.currentChapterIndex

        if book.isOnlineBook {
            // Load online book asynchronously
            chapters = []
            currentContent = ""
            isReading = true
            isLoading = true
            loadingMessage = "正在获取目录..."

            Task { @MainActor in
                await loadOnlineBook(book)
            }
            return
        }

        switch book.bookType {
        case .txt:
            chapters = TxtReader.parseChapters(filePath: book.filePath, bookId: book.id)
        case .epub:
            let result = EpubReader.parse(filePath: book.filePath, bookId: book.id)
            chapters = result.chapters
        case .online, .unknown:
            chapters = []
        }

        if !chapters.isEmpty {
            let safeIndex = min(currentChapterIndex, chapters.count - 1)
            loadChapter(safeIndex)
        }
        isReading = true
    }

    // MARK: - Online Book Loading

    @MainActor
    private func loadOnlineBook(_ book: Book) async {
        guard let source = findBookSource(for: book) else {
            isLoading = false
            loadingMessage = nil
            currentContent = "找不到书源「\(book.originName)」，请确认书源已导入。"
            return
        }

        do {
            // Fetch chapter list
            let fetchedChapters = try await WebBookEngine.shared.fetchChapterList(book: book, source: source)
            chapters = fetchedChapters

            // Update book's total chapter count
            if let idx = books.firstIndex(where: { $0.id == book.id }) {
                books[idx].totalChapters = fetchedChapters.count
                currentBook = books[idx]
                saveBooks()
            }

            if !chapters.isEmpty {
                let safeIndex = min(currentChapterIndex, chapters.count - 1)
                // Load the first/saved chapter content
                await loadOnlineChapter(safeIndex, source: source)
            } else {
                currentContent = "目录为空"
                isLoading = false
                loadingMessage = nil
            }
        } catch {
            isLoading = false
            loadingMessage = nil
            currentContent = "获取目录失败: \(error.localizedDescription)"
            #if DEBUG
            print("[WebBook] TOC error: \(error)")
            #endif
        }
    }

    @MainActor
    private func loadOnlineChapter(_ index: Int, source: BookSource? = nil) async {
        guard index >= 0, index < chapters.count else { return }
        currentChapterIndex = index
        let chapter = chapters[index]

        guard let book = currentBook else { return }

        isLoading = true
        loadingMessage = "正在加载: \(chapter.title)"

        let bookSource: BookSource?
        if let source = source {
            bookSource = source
        } else {
            bookSource = findBookSource(for: book)
        }

        guard let src = bookSource else {
            currentContent = "找不到书源"
            isLoading = false
            loadingMessage = nil
            return
        }

        do {
            let content = try await WebBookEngine.shared.fetchChapterContent(
                book: book, chapter: chapter, source: src
            )
            currentContent = content

            // Save progress
            if let idx = books.firstIndex(where: { $0.id == book.id }) {
                books[idx].currentChapterIndex = index
                books[idx].lastReadTime = Date()
                currentBook = books[idx]
                saveBooks()
            }

            // Prefetch next 10 chapters in background
            prefetchChapters(from: index + 1, count: 10, book: book, source: src)
        } catch {
            currentContent = "加载失败: \(error.localizedDescription)\n\n请检查网络连接或更换书源重试。"
            #if DEBUG
            print("[WebBook] Content error: \(error)")
            #endif
        }

        isLoading = false
        loadingMessage = nil
    }

    // MARK: - Prefetch

    /// Prefetch upcoming chapters in the background for smoother reading
    private func prefetchChapters(from startIndex: Int, count: Int, book: Book, source: BookSource) {
        let endIndex = min(startIndex + count, chapters.count)
        guard startIndex < endIndex else { return }

        let chaptersToFetch = Array(chapters[startIndex..<endIndex])
        #if DEBUG
        print("[WebBook] Prefetching chapters \(startIndex)..\(endIndex - 1)")
        #endif

        Task.detached(priority: .background) {
            for chapter in chaptersToFetch {
                // Skip if already cached
                if WebBookEngine.shared.loadCachedContent(
                    bookId: book.id, chapterIndex: chapter.index
                ) != nil {
                    continue
                }

                do {
                    _ = try await WebBookEngine.shared.fetchChapterContent(
                        book: book, chapter: chapter, source: source
                    )
                    #if DEBUG
                    print("[WebBook] Prefetched: \(chapter.title)")
                    #endif
                } catch {
                    // Silent failure for prefetch — don't interrupt reading
                    #if DEBUG
                    print("[WebBook] Prefetch failed: \(chapter.title)")
                    #endif
                }

                // Small delay between requests to avoid hammering the server
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    // MARK: - Find Book Source

    private func findBookSource(for book: Book) -> BookSource? {
        guard let sourceUrl = book.bookSourceUrl else { return nil }
        return sourceManager?.sources.first { $0.bookSourceUrl == sourceUrl }
    }

    // MARK: - Chapter Navigation

    func loadChapter(_ index: Int) {
        guard index >= 0, index < chapters.count else { return }

        guard let book = currentBook else { return }

        // Online book: load asynchronously
        if book.isOnlineBook {
            Task { @MainActor in
                await loadOnlineChapter(index)
            }
            return
        }

        currentChapterIndex = index
        let chapter = chapters[index]

        switch book.bookType {
        case .txt:
            currentContent = TxtReader.getChapterContent(
                filePath: book.filePath, chapter: chapter
            )
        case .epub:
            currentContent = EpubReader.getChapterContent(
                filePath: book.filePath, chapter: chapter
            )
        case .online, .unknown:
            currentContent = ""
        }

        // Save progress
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx].currentChapterIndex = index
            books[idx].lastReadTime = Date()
            currentBook = books[idx]
            saveBooks()
        }
    }

    func nextChapter() -> Bool {
        guard currentChapterIndex < chapters.count - 1 else { return false }
        loadChapter(currentChapterIndex + 1)
        return true
    }

    func previousChapter() -> Bool {
        guard currentChapterIndex > 0 else { return false }
        loadChapter(currentChapterIndex - 1)
        return true
    }

    // MARK: - Management

    func removeBook(_ book: Book) {
        books.removeAll { $0.id == book.id }
        if currentBook?.id == book.id {
            currentBook = nil
            isReading = false
            chapters = []
            currentContent = ""
        }
        // Delete file only for local books
        if !book.isOnlineBook && !book.filePath.isEmpty {
            try? FileManager.default.removeItem(atPath: book.filePath)
        }
        // Clear cache for online books
        if book.isOnlineBook {
            WebBookEngine.shared.clearCache(bookId: book.id)
        }
        saveBooks()
    }

    func closeBook() {
        isReading = false
        isLoading = false
        loadingMessage = nil
    }

    // MARK: - Persistence

    func saveBooks() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(books) else { return }
        try? data.write(to: Self.saveURL)
    }

    func loadBooks() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.saveURL),
              let loaded = try? decoder.decode([Book].self, from: data)
        else { return }
        books = loaded
    }
    
    // MARK: - Bookmarks
    
    /// 添加书签
    func addBookmark(chapterIndex: Int, chapterTitle: String, scrollOffset: Double = 0, previewText: String = "", note: String? = nil) {
        guard let book = currentBook else { return }
        
        // 检查是否已存在相同位置的书签
        let exists = bookmarks.contains { bookmark in
            bookmark.bookId == book.id &&
            bookmark.chapterIndex == chapterIndex &&
            abs(bookmark.scrollOffset - scrollOffset) < 50
        }
        
        if exists {
            showToast("此处已有书签")
            return
        }
        
        let bookmark = Bookmark(
            bookId: book.id,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            scrollOffset: scrollOffset,
            previewText: previewText,
            note: note
        )
        bookmarks.insert(bookmark, at: 0)
        saveBookmarks()
        showToast("书签已添加")
    }
    
    /// 删除书签
    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
        showToast("书签已删除")
    }
    
    /// 获取当前书籍的书签列表
    func bookmarksForCurrentBook() -> [Bookmark] {
        guard let book = currentBook else { return [] }
        return bookmarksForBook(book)
    }
    
    /// 获取指定书籍的书签列表
    func bookmarksForBook(_ book: Book) -> [Bookmark] {
        return bookmarks.filter { $0.bookId == book.id }
    }
    
    /// 导出书籍笔记为 Markdown 格式
    func exportNotesToMarkdown(for book: Book) -> String {
        let bookBookmarks = bookmarksForBook(book)
        guard !bookBookmarks.isEmpty else { return "" }
        
        var md = "# \(book.name)\n\n"
        md += "> 作者: \(book.author)\n\n"
        md += "---\n\n"
        
        // 按章节分组
        let grouped = Dictionary(grouping: bookBookmarks) { $0.chapterIndex }
        let sortedChapters = grouped.keys.sorted()
        
        for chapterIndex in sortedChapters {
            guard let chapterNotes = grouped[chapterIndex],
                  let firstNote = chapterNotes.first else { continue }
            
            md += "## 第 \(chapterIndex + 1) 章: \(firstNote.chapterTitle)\n\n"
            
            for note in chapterNotes.sorted(by: { $0.createTime < $1.createTime }) {
                if !note.previewText.isEmpty {
                    md += "**原文**: \(note.previewText)\n\n"
                }
                if let noteText = note.note, !noteText.isEmpty {
                    md += "**笔记**: \(noteText)\n\n"
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                md += "*\(formatter.string(from: note.createTime))*\n\n"
                md += "---\n\n"
            }
        }
        
        return md
    }
    
    /// 跳转到书签
    func jumpToBookmark(_ bookmark: Bookmark) {
        guard let book = currentBook else { return }
        
        // 如果是当前书籍，直接跳转
        if book.id == bookmark.bookId {
            loadChapter(bookmark.chapterIndex)
            // 滚动位置会在 ReaderView 中处理
        } else {
            // 如果是其他书籍，先打开该书
            if let targetBook = books.first(where: { $0.id == bookmark.bookId }) {
                openBook(targetBook)
                // 需要等待加载完成后再跳转章节
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.loadChapter(bookmark.chapterIndex)
                }
            }
        }
    }
    
    /// 保存书签到文件
    func saveBookmarks() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bookmarks) else { return }
        try? data.write(to: Self.bookmarksURL)
    }
    
    /// 从文件加载书签
    func loadBookmarks() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.bookmarksURL),
              let loaded = try? decoder.decode([Bookmark].self, from: data)
        else { return }
        bookmarks = loaded
    }
}
