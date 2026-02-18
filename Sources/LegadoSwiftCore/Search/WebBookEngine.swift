import Foundation

/// Engine for fetching online book chapter lists and content.
/// Replicates Android Legado's BookChapterList + BookContent logic.
public class WebBookEngine {

    public static let shared = WebBookEngine()
    private init() {}

    // MARK: - Cache Directory

    private func cacheDir(for bookId: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoSwift/Cache/\(bookId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func chapterCacheFile(bookId: String, chapterIndex: Int) -> URL {
        cacheDir(for: bookId).appendingPathComponent("\(chapterIndex).txt")
    }

    private func tocCacheFile(bookId: String) -> URL {
        cacheDir(for: bookId).appendingPathComponent("toc.json")
    }

    // MARK: - Fetch Chapter List (TOC)

    /// Fetch the table of contents for an online book.
    /// Replicates Android's BookChapterList.analyzeChapterList logic.
    public func fetchChapterList(book: Book, source: BookSource) async throws -> [BookChapter] {
        // Check TOC cache first
        if let cached = loadCachedToc(bookId: book.id) {
            print("[WebBook] 📖 Using cached TOC for \(book.name) (\(cached.count) chapters)")
            return cached
        }

        guard let tocRule = source.ruleToc else {
            throw LegadoError.parseError("书源没有目录规则")
        }

        let headers = NetworkClient.parseHeaders(from: source.header)
        let bookUrl = book.bookUrl ?? source.bookSourceUrl

        // Determine the TOC URL
        // Priority: book.tocUrl > ruleBookInfo.tocUrl template > bookUrl
        var tocUrl = book.tocUrl ?? ""
        
        if tocUrl.isEmpty {
            // Check if ruleBookInfo has a tocUrl template
            if let tocUrlTemplate = source.ruleBookInfo?.tocUrl, !tocUrlTemplate.isEmpty {
                // Need to fetch book info page first to get actual tocUrl
                print("[WebBook] 📚 Fetching book info page to resolve tocUrl: \(bookUrl)")
                let bookInfoHtml = try await NetworkClient.fetchString(url: bookUrl, headers: headers)
                
                let context = AnalyzeContext(book: book, source: source)
                let infoRule = AnalyzeRule(content: bookInfoHtml, context: context)
                
                // Check if tocUrl template uses {{baseUrl}} pattern
                if tocUrlTemplate.contains("{{") {
                    tocUrl = tocUrlTemplate
                        .replacingOccurrences(of: "{{baseUrl}}", with: bookUrl.hasSuffix("/") ? bookUrl : bookUrl + "/")
                        .replacingOccurrences(of: "{{URL}}", with: bookUrl)
                    // Resolve relative URL
                    tocUrl = resolveUrl(tocUrl, baseUrl: bookUrl)
                } else {
                    // It's a rule — evaluate it against the book info page
                    tocUrl = infoRule.getString(tocUrlTemplate) ?? bookUrl
                    tocUrl = resolveUrl(tocUrl, baseUrl: bookUrl)
                }
            } else {
                tocUrl = bookUrl
            }
        }
        
        print("[WebBook] 📚 Fetching TOC: \(tocUrl)")
        let html = try await NetworkClient.fetchString(url: tocUrl, headers: headers)
        print("[WebBook] 📄 TOC response: \(html.count) chars")

        // Parse chapter list rule
        var listRule = tocRule.chapterList ?? ""
        var reverse = false
        if listRule.hasPrefix("-") {
            reverse = true
            listRule = String(listRule.dropFirst())
        }
        if listRule.hasPrefix("+") {
            listRule = String(listRule.dropFirst())
        }

        guard !listRule.isEmpty else {
            throw LegadoError.parseError("目录列表规则为空")
        }

        let context = AnalyzeContext(book: book, source: source)
        let analyzeRule = AnalyzeRule(content: html, context: context)

        // Pre-split rules for chapter name/url
        let ruleChapterName = analyzeRule.splitSourceRule(tocRule.chapterName ?? "")
        let ruleChapterUrl = analyzeRule.splitSourceRule(tocRule.chapterUrl ?? "")

        // Get chapter elements
        let elements = analyzeRule.getElements(listRule)
        print("[WebBook] 📊 Found \(elements.count) chapter elements")

        if elements.isEmpty {
            // Log a snippet of the HTML for debugging
            print("[WebBook] ⚠️ HTML snippet: \(String(html.prefix(500)))")
            throw LegadoError.parseError("未找到章节列表")
        }

        // Parse each element using setContent on shared analyzeRule
        var chapters: [BookChapter] = []
        for (index, element) in elements.enumerated() {
            analyzeRule.setContent(element)

            // Extract chapter name
            guard let title = analyzeRule.getString(ruleChapterName),
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            // Extract chapter URL
            let rawUrl = analyzeRule.getString(ruleChapterUrl) ?? ""
            let chapterUrl = resolveUrl(rawUrl, baseUrl: tocUrl)

            let chapter = BookChapter(
                bookId: book.id,
                index: index,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                chapterUrl: chapterUrl.isEmpty ? tocUrl : chapterUrl
            )
            chapters.append(chapter)
        }

        // Handle reverse
        if reverse {
            chapters.reverse()
        }

        // Re-index
        for i in chapters.indices {
            chapters[i] = BookChapter(
                bookId: chapters[i].bookId,
                index: i,
                title: chapters[i].title,
                chapterUrl: chapters[i].chapterUrl
            )
        }

        print("[WebBook] ✅ Parsed \(chapters.count) chapters")

        // Cache the TOC
        saveTocCache(bookId: book.id, chapters: chapters)

        return chapters
    }

    // MARK: - Fetch Chapter Content

    /// Fetch the content of a specific chapter.
    /// Replicates Android's BookContent.analyzeContent logic.
    public func fetchChapterContent(
        book: Book,
        chapter: BookChapter,
        source: BookSource
    ) async throws -> String {
        // Check cache first
        if let cached = loadCachedContent(bookId: book.id, chapterIndex: chapter.index) {
            print("[WebBook] 📖 Using cached content for chapter \(chapter.index): \(chapter.title)")
            return cached
        }

        guard let contentRule = source.ruleContent else {
            throw LegadoError.parseError("书源没有正文规则")
        }

        guard let contentRuleStr = contentRule.content, !contentRuleStr.isEmpty else {
            // If no content rule, return the chapter URL as content (some sources work this way)
            return chapter.chapterUrl ?? ""
        }

        let chapterUrl = chapter.chapterUrl ?? book.bookUrl ?? ""
        guard !chapterUrl.isEmpty else {
            throw LegadoError.parseError("章节URL为空")
        }

        print("[WebBook] 📖 Fetching content: \(chapterUrl)")

        let headers = NetworkClient.parseHeaders(from: source.header)
        let html = try await NetworkClient.fetchString(url: chapterUrl, headers: headers)
        print("[WebBook] 📄 Content response: \(html.count) chars")

        let context = AnalyzeContext(book: book, source: source)
        let analyzeRule = AnalyzeRule(content: html, context: context)

        // Extract content using content rule
        guard let content = analyzeRule.getString(contentRuleStr) else {
            throw LegadoError.parseError("正文解析结果为空")
        }

        // Clean up the content
        var cleanContent = content
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        // Strip remaining HTML tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let nsStr = cleanContent as NSString
            cleanContent = tagRegex.stringByReplacingMatches(
                in: cleanContent,
                range: NSRange(location: 0, length: nsStr.length),
                withTemplate: ""
            )
        }

        // Clean up extra whitespace and lines
        let lines = cleanContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        cleanContent = lines.joined(separator: "\n")

        print("[WebBook] ✅ Content parsed: \(cleanContent.count) chars")

        // Cache the content
        saveCachedContent(bookId: book.id, chapterIndex: chapter.index, content: cleanContent)

        return cleanContent
    }

    // MARK: - Cache Operations

    func loadCachedContent(bookId: String, chapterIndex: Int) -> String? {
        let file = chapterCacheFile(bookId: bookId, chapterIndex: chapterIndex)
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func saveCachedContent(bookId: String, chapterIndex: Int, content: String) {
        let file = chapterCacheFile(bookId: bookId, chapterIndex: chapterIndex)
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    func loadCachedToc(bookId: String) -> [BookChapter]? {
        let file = tocCacheFile(bookId: bookId)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([BookChapter].self, from: data)
    }

    func saveTocCache(bookId: String, chapters: [BookChapter]) {
        let file = tocCacheFile(bookId: bookId)
        if let data = try? JSONEncoder().encode(chapters) {
            try? data.write(to: file)
        }
    }

    /// Clear all cache for a book
    public func clearCache(bookId: String) {
        let dir = cacheDir(for: bookId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - URL Resolution

    private func resolveUrl(_ url: String, baseUrl: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return baseUrl }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        if trimmed.hasPrefix("/") {
            if let base = URL(string: baseUrl), let scheme = base.scheme, let host = base.host {
                return "\(scheme)://\(host)\(trimmed)"
            }
            return baseUrl + trimmed
        }
        // Relative URL — resolve against base
        if let base = URL(string: baseUrl) {
            let baseDir = base.deletingLastPathComponent()
            return baseDir.appendingPathComponent(trimmed).absoluteString
        }
        return baseUrl + "/" + trimmed
    }
}
