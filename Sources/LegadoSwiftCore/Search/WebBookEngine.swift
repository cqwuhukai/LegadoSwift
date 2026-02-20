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
                    tocUrl = URLResolver.resolve(tocUrl, baseUrl: bookUrl)
                } else {
                    // It's a rule — evaluate it against the book info page
                    tocUrl = infoRule.getString(tocUrlTemplate) ?? bookUrl
                    tocUrl = URLResolver.resolve(tocUrl, baseUrl: bookUrl)
                }
            } else {
                tocUrl = bookUrl
            }
        }
        
        #if DEBUG
        print("[WebBook] Fetching TOC: \(tocUrl)")
        #endif
        let html = try await NetworkClient.fetchString(url: tocUrl, headers: headers)
        #if DEBUG
        print("[WebBook] TOC response: \(html.count) chars")
        #endif

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

        // === Replicate Android BookChapterList.analyzeChapterList ===
        let nextUrlList = [tocUrl]  // Track visited URLs
        
        // Parse first page: returns (chapters, nextUrls)
        let firstResult = analyzeChapterListPage(
            book: book, source: source,
            baseUrl: tocUrl, redirectUrl: tocUrl,
            body: html, tocRule: tocRule, listRule: listRule,
            getNextUrl: true
        )
        var chapters = firstResult.chapters

        // Handle nextTocUrl pagination
        switch firstResult.nextUrls.count {
        case 0:
            // No pagination — single page TOC
            break

        case 1:
            // Sequential pagination (like Android's single-nextUrl branch)
            var visitedUrls = Set<String>(nextUrlList)
            var nextUrl = firstResult.nextUrls[0]

            while !nextUrl.isEmpty && !visitedUrls.contains(nextUrl) {
                visitedUrls.insert(nextUrl)
                print("[WebBook] Fetching TOC page: \(nextUrl) (page \(visitedUrls.count))")

                do {
                    let nextHtml = try await NetworkClient.fetchString(url: nextUrl, headers: headers)
                    let pageResult = analyzeChapterListPage(
                        book: book, source: source,
                        baseUrl: nextUrl, redirectUrl: nextUrl,
                        body: nextHtml, tocRule: tocRule, listRule: listRule,
                        getNextUrl: true
                    )
                    chapters.append(contentsOf: pageResult.chapters)
                    nextUrl = pageResult.nextUrls.first ?? ""
                } catch {
                    print("[WebBook] ⚠️ Failed to fetch TOC page \(nextUrl): \(error.localizedDescription)")
                    break
                }
            }
            #if DEBUG
            print("[WebBook] TOC pagination: \(visitedUrls.count) pages total")
            #endif

        default:
            // Multiple next URLs → concurrent fetch (like Android's multi-nextUrl branch)
            print("[WebBook] Concurrent TOC fetch: \(firstResult.nextUrls.count) additional pages")
            try await withThrowingTaskGroup(of: [BookChapter].self) { group in
                for pageUrl in firstResult.nextUrls {
                    group.addTask {
                        let pageHtml = try await NetworkClient.fetchString(url: pageUrl, headers: headers)
                        return self.analyzeChapterListPage(
                            book: book, source: source,
                            baseUrl: pageUrl, redirectUrl: pageUrl,
                            body: pageHtml, tocRule: tocRule, listRule: listRule,
                            getNextUrl: false
                        ).chapters
                    }
                }
                for try await pageChapters in group {
                    chapters.append(contentsOf: pageChapters)
                }
            }
        }

        if chapters.isEmpty {
            print("[WebBook] HTML snippet: \(String(html.prefix(300)))")
            throw LegadoError.parseError("未找到章节列表")
        }

        // Reverse handling (Android: if !reverse, reverse; then reverse again if !getReverseToc)
        // Simplified: the chapters are collected in page order
        if reverse {
            chapters.reverse()
        }

        // Deduplicate by chapterUrl (like Android's LinkedHashSet)
        var seenUrls = Set<String>()
        chapters = chapters.filter { ch in
            let url = ch.chapterUrl ?? ""
            if url.isEmpty { return true }
            return seenUrls.insert(url).inserted
        }

        // Re-index all chapters
        for i in chapters.indices {
            chapters[i] = BookChapter(
                bookId: chapters[i].bookId,
                index: i,
                title: chapters[i].title,
                chapterUrl: chapters[i].chapterUrl
            )
        }

        #if DEBUG
        print("[WebBook] Parsed \(chapters.count) chapters total")
        #endif

        // Cache the TOC
        saveTocCache(bookId: book.id, chapters: chapters)

        return chapters
    }

    /// Analyze a single TOC page — replicates Android's inner analyzeChapterList function.
    /// Returns chapters found on this page + list of next page URLs.
    private func analyzeChapterListPage(
        book: Book,
        source: BookSource,
        baseUrl: String,
        redirectUrl: String,
        body: String,
        tocRule: TocRule,
        listRule: String,
        getNextUrl: Bool
    ) -> (chapters: [BookChapter], nextUrls: [String]) {
        let context = AnalyzeContext(book: book, source: source)
        let analyzeRule = AnalyzeRule(content: body, context: context)
        analyzeRule.setBaseUrl(baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)

        // Get chapter elements
        let elements = analyzeRule.getElements(listRule)
        #if DEBUG
        print("[WebBook] Found \(elements.count) chapter elements")
        #endif

        // Get next page URLs (BEFORE iterating elements — critical for correct behavior)
        var nextUrls: [String] = []
        if getNextUrl {
            let nextTocRule = tocRule.nextTocUrl
            if let nextTocRule = nextTocRule, !nextTocRule.isEmpty {
                // Use isUrl: true to resolve relative URLs to absolute!
                if let urls = analyzeRule.getStringList(nextTocRule, isUrl: true) {
                    for item in urls {
                        if item != redirectUrl && !item.isEmpty {
                            nextUrls.append(item)
                        }
                    }
                }
                #if DEBUG
                print("[WebBook] nextTocUrls: \(nextUrls)")
                #endif
            }
        }

        // Parse chapter elements
        let ruleChapterName = analyzeRule.splitSourceRule(tocRule.chapterName ?? "")
        let ruleChapterUrl = analyzeRule.splitSourceRule(tocRule.chapterUrl ?? "")

        var chapters: [BookChapter] = []
        for (index, element) in elements.enumerated() {
            analyzeRule.setContent(element)

            guard let title = analyzeRule.getString(ruleChapterName),
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            // Use isUrl: true to resolve chapter URLs
            let chapterUrl = analyzeRule.getString(ruleChapterUrl, isUrl: true) ?? baseUrl

            let chapter = BookChapter(
                bookId: book.id,
                index: index,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                chapterUrl: chapterUrl.isEmpty ? baseUrl : chapterUrl
            )
            chapters.append(chapter)
        }

        return (chapters, nextUrls)
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
            #if DEBUG
            print("[WebBook] Using cached content for chapter \(chapter.index)")
            #endif
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

        #if DEBUG
        print("[WebBook] Fetching content: \(chapterUrl)")
        #endif

        let headers = NetworkClient.parseHeaders(from: source.header)
        let html = try await NetworkClient.fetchString(url: chapterUrl, headers: headers)
        #if DEBUG
        print("[WebBook] Content response: \(html.count) chars")
        #endif

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

        #if DEBUG
        print("[WebBook] Content parsed: \(cleanContent.count) chars")
        #endif

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

}
