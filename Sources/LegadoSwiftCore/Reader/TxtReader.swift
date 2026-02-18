import Foundation

enum TxtReader {

    // Chapter title patterns (Chinese and English)
    private static let chapterPatterns: [String] = [
        #"^\s*第[零一二三四五六七八九十百千万\d]+[章节回集卷部篇].*$"#,
        #"^\s*第\s*\d+\s*[章节回集卷部篇].*$"#,
        #"^\s*[Cc]hapter\s+\d+.*$"#,
        #"^\s*[Pp]art\s+[IVXivx\d]+.*$"#,
        #"^\s*[Ss]ection\s+\d+.*$"#,
        #"^\s*卷[零一二三四五六七八九十百千万\d]+.*$"#,
        #"^\s*正文\s.*$"#,
    ]

    // MARK: - Parse Chapters

    static func parseChapters(filePath: String, bookId: String) -> [BookChapter] {
        guard let data = FileManager.default.contents(atPath: filePath) else { return [] }

        // Detect encoding
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let gbk = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            text = gbk
        } else {
            text = String(data: data, encoding: .ascii) ?? ""
        }

        guard !text.isEmpty else { return [] }

        var chapters: [BookChapter] = []
        let lines = text.components(separatedBy: .newlines)
        var currentOffset = 0
        var chapterStarts: [(title: String, offset: Int)] = []

        // Compile regex patterns
        let regexes: [NSRegularExpression] = chapterPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines)
        }

        for line in lines {
            let lineLen = line.utf8.count + 1 // +1 for newline

            for regex in regexes {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty && title.count < 100 {
                        chapterStarts.append((title: title, offset: currentOffset))
                    }
                    break
                }
            }
            currentOffset += lineLen
        }

        // If no chapters found, create a single chapter
        if chapterStarts.isEmpty {
            let totalBytes = text.utf8.count
            // Split into ~20KB chunks
            let chunkSize = 20000
            var offset = 0
            var idx = 0
            while offset < totalBytes {
                let end = min(offset + chunkSize, totalBytes)
                chapters.append(BookChapter(
                    bookId: bookId,
                    index: idx,
                    title: idx == 0 ? "开始" : "第 \(idx + 1) 段",
                    startOffset: offset,
                    endOffset: end
                ))
                offset = end
                idx += 1
            }
            return chapters
        }

        // Build chapters from detected positions
        let totalBytes = text.utf8.count
        for (i, start) in chapterStarts.enumerated() {
            let endOffset = i + 1 < chapterStarts.count
                ? chapterStarts[i + 1].offset
                : totalBytes
            chapters.append(BookChapter(
                bookId: bookId,
                index: i,
                title: start.title,
                startOffset: start.offset,
                endOffset: endOffset
            ))
        }

        // If first chapter doesn't start at 0, add preface
        if let first = chapterStarts.first, first.offset > 100 {
            chapters.insert(BookChapter(
                bookId: bookId,
                index: -1,
                title: "前言",
                startOffset: 0,
                endOffset: first.offset
            ), at: 0)
            // Re-index
            for i in chapters.indices {
                chapters[i].index = i
            }
        }

        return chapters
    }

    // MARK: - Get Chapter Content

    static func getChapterContent(filePath: String, chapter: BookChapter) -> String {
        guard let data = FileManager.default.contents(atPath: filePath) else { return "" }

        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let gbk = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            text = gbk
        } else {
            return ""
        }

        let utf8Data = text.utf8
        let start = max(0, chapter.startOffset)
        let end = min(chapter.endOffset, utf8Data.count)

        guard start < end else { return "" }

        let startIdx = utf8Data.index(utf8Data.startIndex, offsetBy: start, limitedBy: utf8Data.endIndex) ?? utf8Data.startIndex
        let endIdx = utf8Data.index(utf8Data.startIndex, offsetBy: end, limitedBy: utf8Data.endIndex) ?? utf8Data.endIndex

        return String(utf8Data[startIdx..<endIdx]) ?? ""
    }
}
