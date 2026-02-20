import Foundation

// MARK: - Book Search Engine

@Observable
class BookSearchEngine {
    var results: [SearchBook] = []
    var isSearching = false
    var searchProgress: String = ""
    var searchErrors: [String] = []

    // MARK: - Search

    func search(keyword: String, sources: [BookSource]) async {
        guard !keyword.isEmpty, !sources.isEmpty else { return }

        await MainActor.run {
            isSearching = true
            results = []
            searchErrors = []
            searchProgress = "准备搜索..."
        }

        // Search enabled sources concurrently
        let enabledSources = sources.filter { $0.enabled && $0.searchUrl != nil }

        if enabledSources.isEmpty {
            await MainActor.run {
                isSearching = false
                searchProgress = "没有可用的书源"
                searchErrors.append("没有已启用且配置了搜索URL的书源")
            }
            return
        }

        await MainActor.run {
            searchProgress = "正在搜索 \(enabledSources.count) 个书源..."
        }

        await withTaskGroup(of: (String, [SearchBook], String?).self) { group in
            for source in enabledSources.prefix(20) { // Limit concurrent sources
                group.addTask {
                    do {
                        let books = try await self.searchInSource(keyword: keyword, source: source)
                        return (source.bookSourceName, books, nil)
                    } catch {
                        return (source.bookSourceName, [], "[\(source.bookSourceName)] \(error.localizedDescription)")
                    }
                }
            }

            for await (sourceName, sourceResults, error) in group {
                await MainActor.run {
                    if let error = error {
                        self.searchErrors.append(error)
                    }

                    // Merge results, avoiding duplicates by bookUrl
                    let existingUrls = Set(self.results.map { $0.bookUrl })
                    let newResults = sourceResults.filter { !existingUrls.contains($0.bookUrl) }
                    self.results.append(contentsOf: newResults)
                    self.searchProgress = "已找到 \(self.results.count) 本书..."

                    if !sourceResults.isEmpty {
                        #if DEBUG
                        print("[Search] \(sourceName): found \(sourceResults.count) books")
                        #endif
                    }
                }
            }
        }

        await MainActor.run {
            isSearching = false
            // Sort results by relevance to keyword
            let kw = keyword.lowercased()
            results.sort { a, b in
                let aScore = relevanceScore(name: a.name, author: a.author, keyword: kw)
                let bScore = relevanceScore(name: b.name, author: b.author, keyword: kw)
                return aScore > bScore
            }
            if results.isEmpty {
                if searchErrors.isEmpty {
                    searchProgress = "未找到结果"
                } else {
                    searchProgress = "未找到结果 (有 \(searchErrors.count) 个书源出错)"
                }
            } else {
                searchProgress = "共 \(results.count) 本书"
            }
        }
    }

    /// Calculate relevance score for sorting search results
    private func relevanceScore(name: String, author: String, keyword: String) -> Int {
        let lowerName = name.lowercased()
        let lowerAuthor = author.lowercased()
        if lowerName == keyword { return 100 }  // Exact match
        if lowerName.hasPrefix(keyword) { return 80 }  // Starts with
        if lowerName.contains(keyword) { return 60 }  // Name contains
        if lowerAuthor.contains(keyword) { return 40 }  // Author contains
        return 0
    }

    // MARK: - Search in Single Source

    private func searchInSource(keyword: String, source: BookSource) async throws -> [SearchBook] {
        guard let searchUrlTemplate = source.searchUrl else { return [] }

        // Build search URL and optional POST body
        let (searchUrl, postBody) = buildSearchRequest(
            template: searchUrlTemplate,
            keyword: keyword,
            baseUrl: source.bookSourceUrl,
            page: 1
        )
        guard !searchUrl.isEmpty, let _ = URL(string: searchUrl) else {
            #if DEBUG
            print("[Search] \(source.bookSourceName): invalid URL: \(searchUrl)")
            #endif
            throw LegadoError.invalidURL
        }

        #if DEBUG
        print("[Search] \(source.bookSourceName): \(searchUrl)")
        if let body = postBody {
            print("[Search] POST body: \(body)")
        }
        #endif

        let headers = NetworkClient.parseHeaders(from: source.header)

        let html: String
        if let body = postBody {
            // POST request
            html = try await NetworkClient.fetchStringPOST(url: searchUrl, body: body, headers: headers)
        } else {
            // GET request
            html = try await NetworkClient.fetchString(url: searchUrl, headers: headers)
        }

        #if DEBUG
        print("[Search] \(source.bookSourceName): received \(html.count) chars")
        #endif

        // Parse results based on search rules
        var books = parseSearchResults(html: html, source: source, baseUrl: searchUrl)

        // Filter by keyword relevance (replicating Android's filter callback)
        // Books must have name or author containing the keyword
        let lowercaseKeyword = keyword.lowercased()
        books = books.filter { book in
            book.name.lowercased().contains(lowercaseKeyword) ||
            book.author.lowercased().contains(lowercaseKeyword)
        }

        return books
    }

    // MARK: - URL Template (Replicating Android AnalyzeUrl logic)

    /// Parse a search URL template, replacing key/page placeholders and extracting POST body.
    /// Android format: `url,{"method":"POST","body":"keyword={{key}}"}`
    /// Returns (url, postBody?) tuple.
    private func buildSearchRequest(
        template: String,
        keyword: String,
        baseUrl: String,
        page: Int
    ) -> (String, String?) {
        var urlPart = template
        var postBody: String?

        // Handle multiline templates (first line is the URL)
        if urlPart.contains("\n") {
            urlPart = urlPart.components(separatedBy: "\n").first ?? urlPart
        }

        // Replace key/page placeholders BEFORE splitting URL from JSON options
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        urlPart = urlPart.replacingOccurrences(of: "{{key}}", with: encodedKeyword)
        urlPart = urlPart.replacingOccurrences(of: "{{KEY}}", with: encodedKeyword)
        urlPart = urlPart.replacingOccurrences(of: "{{page}}", with: "\(page)")
        urlPart = urlPart.replacingOccurrences(of: "{{PAGE}}", with: "\(page)")

        // Handle Android page pattern: <page1,pageN>
        if let regex = try? NSRegularExpression(pattern: #"<(.+?)>"#) {
            let nsStr = urlPart as NSString
            if let match = regex.firstMatch(in: urlPart, range: NSRange(location: 0, length: nsStr.length)) {
                let pages = nsStr.substring(with: match.range(at: 1)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let replacement = page <= pages.count ? pages[page - 1] : (pages.last ?? "")
                urlPart = nsStr.replacingCharacters(in: match.range, with: replacement)
            }
        }

        // Handle Java URLEncoder pattern
        urlPart = urlPart.replacingOccurrences(
            of: "{{java.net.URLEncoder.encode(key,\"UTF-8\")}}",
            with: encodedKeyword
        )

        // Replace searchKey/searchPage (legacy format used by some sources)
        urlPart = urlPart.replacingOccurrences(of: "searchKey", with: encodedKeyword)
        urlPart = urlPart.replacingOccurrences(of: "searchPage", with: "\(page)")

        // Split URL from JSON option: url,{"method":"POST","body":"..."}
        // Use the Android paramPattern approach: split at first `,{` 
        if let commaJsonRange = urlPart.range(of: ",", options: [], range: urlPart.startIndex..<urlPart.endIndex) {
            let afterComma = urlPart[commaJsonRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if afterComma.hasPrefix("{") {
                let urlOnly = String(urlPart[..<commaJsonRange.lowerBound])
                // Parse the JSON option
                if let jsonData = afterComma.data(using: .utf8),
                   let option = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    // Check if POST
                    if let method = option["method"] as? String, method.uppercased() == "POST" {
                        if let body = option["body"] as? String {
                            // Body may also contain placeholders
                            postBody = body
                                .replacingOccurrences(of: "{{key}}", with: encodedKeyword)
                                .replacingOccurrences(of: "searchKey", with: encodedKeyword)
                        } else {
                            postBody = ""
                        }
                    }
                }
                urlPart = urlOnly
            }
        }

        // Resolve relative URL
        urlPart = urlPart.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlPart.hasPrefix("http") {
            urlPart = URLResolver.resolve(urlPart, baseUrl: baseUrl)
        }

        return (urlPart, postBody)
    }

    // MARK: - Parse Results (Rule Engine)

    /// Unified result parser replicating Android BookList.getSearchItem logic.
    /// Key differences from previous implementation:
    /// 1. Uses setContent(item) to set each element as context
    /// 2. Pre-splits rules for efficiency
    /// 3. Properly resolves URLs using search URL as base
    private func parseSearchResults(html: String, source: BookSource, baseUrl: String) -> [SearchBook] {
        guard let rules = source.ruleSearch else {
            return []
        }

        let context = AnalyzeContext(source: source)
        let analyzeRule = AnalyzeRule(content: html, context: context)

        // Get book list elements using bookList rule
        guard let bookListRule = rules.bookList, !bookListRule.isEmpty else {
            return []
        }

        // Handle reverse prefix
        var listRule = bookListRule
        var reverse = false
        if listRule.hasPrefix("-") {
            reverse = true
            listRule = String(listRule.dropFirst())
        }
        if listRule.hasPrefix("+") {
            listRule = String(listRule.dropFirst())
        }

        let elements = analyzeRule.getElements(listRule)
        #if DEBUG
        print("[Search] \(source.bookSourceName): found \(elements.count) elements")
        #endif

        if elements.isEmpty { return [] }

        // Pre-split rules (Android optimization — split once, reuse many times)
        let ruleName = analyzeRule.splitSourceRule(rules.name ?? "")
        let ruleBookUrl = analyzeRule.splitSourceRule(rules.bookUrl ?? "")
        let ruleAuthor = analyzeRule.splitSourceRule(rules.author ?? "")
        let ruleCoverUrl = analyzeRule.splitSourceRule(rules.coverUrl ?? "")
        let ruleIntro = analyzeRule.splitSourceRule(rules.intro ?? "")
        let ruleKind = analyzeRule.splitSourceRule(rules.kind ?? "")
        let ruleLastChapter = analyzeRule.splitSourceRule(rules.lastChapter ?? "")

        // Parse each element into a SearchBook
        var books: [SearchBook] = []
        for element in elements {
            // Reuse analyzeRule, set content to current element
            // This is the key fix — Android does analyzeRule.setContent(item)
            analyzeRule.setContent(element)

            // Extract name (required)
            guard let name = analyzeRule.getString(ruleName),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            // Extract bookUrl and resolve it
            let rawBookUrl = analyzeRule.getString(ruleBookUrl) ?? ""
            let fullBookUrl: String
            if rawBookUrl.isEmpty {
                fullBookUrl = baseUrl
            } else {
                fullBookUrl = URLResolver.resolve(rawBookUrl, baseUrl: baseUrl)
            }

            // Extract author
            let author = analyzeRule.getString(ruleAuthor)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Extract coverUrl
            let rawCoverUrl = analyzeRule.getString(ruleCoverUrl) ?? ""
            let fullCoverUrl: String?
            if rawCoverUrl.isEmpty {
                fullCoverUrl = nil
            } else {
                fullCoverUrl = URLResolver.resolve(rawCoverUrl, baseUrl: baseUrl)
            }

            // Extract kind (may be a list)
            var kind: String?
            if let kindList = analyzeRule.getStringList(ruleKind), !kindList.isEmpty {
                kind = kindList.joined(separator: ",")
            }
            if kind?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                kind = nil
            }

            // Extract intro
            let intro = analyzeRule.getString(ruleIntro)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract latest chapter
            let lastChapter = analyzeRule.getString(ruleLastChapter)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Clean up author: remove common prefixes like "作者：" etc.
            let cleanAuthor = cleanAuthorString(author)

            books.append(SearchBook(
                bookUrl: fullBookUrl,
                bookSourceUrl: source.bookSourceUrl,
                name: cleanName,
                author: cleanAuthor,
                coverUrl: fullCoverUrl,
                intro: intro?.isEmpty == true ? nil : intro,
                kind: kind,
                latestChapterTitle: lastChapter?.isEmpty == true ? nil : lastChapter,
                origin: source.bookSourceUrl,
                originName: source.bookSourceName
            ))
        }

        if reverse {
            books.reverse()
        }

        // Remove duplicates by bookUrl (like Android's LinkedHashSet)
        var seen = Set<String>()
        books = books.filter { seen.insert($0.bookUrl).inserted }

        #if DEBUG
        print("[Search] Parsed \(books.count) books from \(source.bookSourceName)")
        #endif
        return books
    }

    // MARK: - Author Cleanup

    private func cleanAuthorString(_ author: String) -> String {
        var result = author
        let prefixes = ["作者：", "作者:", "作    者：", "作    者:", "Author:", "author:"]
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        isSearching = false
        searchProgress = ""
    }
}
