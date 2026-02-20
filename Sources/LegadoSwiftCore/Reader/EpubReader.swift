import Foundation

struct EpubParseResult {
    var title: String = ""
    var author: String = ""
    var chapters: [BookChapter] = []
}

enum EpubReader {

    // MARK: - Parse EPUB

    static func parse(filePath: String, bookId: String) -> EpubParseResult {
        var result = EpubParseResult()

        let fileURL = URL(fileURLWithPath: filePath)
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            return result
        }
        


        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado_epub_\(bookId)")

        // Clean up old extraction
        try? FileManager.default.removeItem(at: tempDir)

        // Unzip EPUB
        guard unzipEpub(at: fileURL, to: tempDir) else {
            return result
        }

        // Parse container.xml to find OPF path
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            if let opfPath = findOPFFile(in: tempDir) {
                return parseOPF(opfRelPath: opfPath, tempDir: tempDir, bookId: bookId)
            }
            return result
        }
        
        guard let containerXML = readFileContent(at: containerPath) else {
            return result
        }
        
        guard let opfRelPath = extractAttribute(from: containerXML, tag: "rootfile", attribute: "full-path") else {
            return result
        }
        
        return parseOPF(opfRelPath: opfRelPath, tempDir: tempDir, bookId: bookId)
    }
    
    // MARK: - OPF Parsing
    
    private static func parseOPF(opfRelPath: String, tempDir: URL, bookId: String) -> EpubParseResult {
        var result = EpubParseResult()
        

        
        let opfURL = tempDir.appendingPathComponent(opfRelPath)
        let opfDir = opfURL.deletingLastPathComponent()
        
        guard let opfXML = readFileContent(at: opfURL) else {
            return result
        }
        
        // Strip XML namespace prefixes to simplify parsing
        // e.g. <opf:item> → <item>, <opf:manifest> → <manifest>
        let cleanedOPF = stripNamespacePrefixes(opfXML)

        // Extract metadata
        result.title = extractContent(from: cleanedOPF, tag: "dc:title")
            ?? extractContent(from: cleanedOPF, tag: "title") ?? ""
        result.author = extractContent(from: cleanedOPF, tag: "dc:creator")
            ?? extractContent(from: cleanedOPF, tag: "creator") ?? ""
        


        // Extract spine and manifest from cleaned OPF
        let spineIds = extractSpineItems(from: cleanedOPF)
        let manifest = extractManifestItems(from: cleanedOPF)
        


        // Build chapters from spine
        for (idx, spineId) in spineIds.enumerated() {
            guard let href = manifest[spineId] else { continue }
            
            let decodedHref = href.removingPercentEncoding ?? href
            let chapterFile = opfDir.appendingPathComponent(decodedHref).standardizedFileURL.path

            guard FileManager.default.fileExists(atPath: chapterFile) else { continue }

            let chapterTitle = extractChapterTitle(filePath: chapterFile) ?? "第 \(idx + 1) 章"

            result.chapters.append(BookChapter(
                bookId: bookId,
                index: idx,
                title: chapterTitle,
                contentFile: chapterFile
            ))
        }
        
        // Fallback: NCX
        if result.chapters.isEmpty {
            result.chapters = parseChaptersFromNCX(opfXML: cleanedOPF, opfDir: opfDir, bookId: bookId)
        }
        
        // Fallback: all HTML files
        if result.chapters.isEmpty {
            result.chapters = parseChaptersFromManifest(manifest: manifest, opfDir: opfDir, bookId: bookId)
        }


        return result
    }
    
    // MARK: - Strip XML Namespace Prefixes
    
    /// Converts `<opf:item ...>` to `<item ...>`, `<opf:manifest>` to `<manifest>`, etc.
    /// This makes regex-based parsing work regardless of namespace usage.
    private static func stripNamespacePrefixes(_ xml: String) -> String {
        // Remove namespace prefixes from tags: <opf:tag → <tag, </opf:tag → </tag
        if let regex = try? NSRegularExpression(pattern: #"<(/?)[\w]+:"#) {
            return regex.stringByReplacingMatches(
                in: xml,
                range: NSRange(xml.startIndex..., in: xml),
                withTemplate: "<$1"
            )
        }
        return xml
    }
    
    // MARK: - Find OPF
    
    private static func findOPFFile(in dir: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension.lowercased() == "opf" {
                return url.path.replacingOccurrences(of: dir.path + "/", with: "")
            }
        }
        return nil
    }
    
    // MARK: - NCX Fallback
    
    private static func parseChaptersFromNCX(opfXML: String, opfDir: URL, bookId: String) -> [BookChapter] {
        var chapters: [BookChapter] = []
        
        let ncxPatterns = [
            #"<item[^>]*media-type="application/x-dtbncx\+xml"[^>]*href="([^"]+)""#,
            #"<item[^>]*href="([^"]+)"[^>]*media-type="application/x-dtbncx\+xml""#,
            #"<item[^>]*href="([^"]+\.ncx)""#
        ]
        
        var ncxHref: String?
        for pat in ncxPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let match = regex.firstMatch(in: opfXML, range: NSRange(opfXML.startIndex..., in: opfXML)),
               let range = Range(match.range(at: 1), in: opfXML) {
                ncxHref = String(opfXML[range])
                break
            }
        }
        
        guard let href = ncxHref else { return chapters }
        
        let ncxURL = opfDir.appendingPathComponent(href.removingPercentEncoding ?? href)
        guard let ncxXML = readFileContent(at: ncxURL) else { return chapters }
        
        // Strip namespace prefixes from NCX too
        let cleanNCX = stripNamespacePrefixes(ncxXML)
        
        let textPattern = #"<text>\s*([^<]*?)\s*</text>"#
        let srcPattern = #"<content\s+src="([^"]+)""#
        
        guard let textRegex = try? NSRegularExpression(pattern: textPattern, options: .caseInsensitive),
              let srcRegex = try? NSRegularExpression(pattern: srcPattern, options: .caseInsensitive)
        else { return chapters }
        
        let textMatches = textRegex.matches(in: cleanNCX, range: NSRange(cleanNCX.startIndex..., in: cleanNCX))
        let srcMatches = srcRegex.matches(in: cleanNCX, range: NSRange(cleanNCX.startIndex..., in: cleanNCX))
        
        let count = min(textMatches.count, srcMatches.count)
        var seenFiles = Set<String>()
        var idx = 0
        
        for i in 0..<count {
            guard let titleRange = Range(textMatches[i].range(at: 1), in: cleanNCX),
                  let srcRange = Range(srcMatches[i].range(at: 1), in: cleanNCX) else { continue }
            
            let title = String(cleanNCX[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let src = String(cleanNCX[srcRange]).components(separatedBy: "#").first ?? ""
            
            let chapterFile = opfDir.appendingPathComponent(
                src.removingPercentEncoding ?? src
            ).standardizedFileURL.path
            
            guard FileManager.default.fileExists(atPath: chapterFile),
                  !seenFiles.contains(chapterFile) else { continue }
            seenFiles.insert(chapterFile)
            
            chapters.append(BookChapter(
                bookId: bookId,
                index: idx,
                title: title.isEmpty ? "第 \(idx + 1) 章" : title,
                contentFile: chapterFile
            ))
            idx += 1
        }
        
        return chapters
    }
    
    // MARK: - Manifest Fallback
    
    private static func parseChaptersFromManifest(manifest: [String: String], opfDir: URL, bookId: String) -> [BookChapter] {
        var chapters: [BookChapter] = []
        
        let htmlExts = Set(["html", "xhtml", "htm"])
        let htmlFiles = manifest.values.filter { href in
            htmlExts.contains((href as NSString).pathExtension.lowercased())
        }.sorted()
        
        for (idx, href) in htmlFiles.enumerated() {
            let chapterFile = opfDir.appendingPathComponent(
                href.removingPercentEncoding ?? href
            ).standardizedFileURL.path
            
            guard FileManager.default.fileExists(atPath: chapterFile) else { continue }
            
            let title = extractChapterTitle(filePath: chapterFile) ?? "第 \(idx + 1) 章"
            chapters.append(BookChapter(
                bookId: bookId,
                index: idx,
                title: title,
                contentFile: chapterFile
            ))
        }
        
        return chapters
    }

    // MARK: - Get Chapter Content

    static func getChapterContent(filePath: String, chapter: BookChapter) -> String {
        guard let contentFile = chapter.contentFile,
              let html = readFileContent(at: URL(fileURLWithPath: contentFile)) else {
            return ""
        }
        return stripHTML(html)
    }

    // MARK: - File Reading
    
    private static func readFileContent(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let data = FileManager.default.contents(atPath: url.path) {
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? String(data: data, encoding: .isoLatin1)
        }
        return nil
    }

    // MARK: - Unzip

    private static func unzipEpub(at source: URL, to destination: URL) -> Bool {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        
        // Method 1: /usr/bin/unzip (most reliable for EPUB)
        if runProcess("/usr/bin/unzip", args: ["-o", "-q", source.path, "-d", destination.path]) {
            if verifyExtraction(destination) {
                return true
            }
        }
        
        // Method 2: /usr/bin/ditto  
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if runProcess("/usr/bin/ditto", args: ["-xk", source.path, destination.path]) {
            if verifyExtraction(destination) {
                return true
            }
        }
        
        return false
    }
    
    private static func runProcess(_ path: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private static func verifyExtraction(_ dir: URL) -> Bool {
        // Check META-INF/container.xml exists OR any .opf file exists
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("META-INF/container.xml").path) {
            return true
        }
        // Maybe ditto created a subdirectory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for item in contents {
                let subPath = dir.appendingPathComponent(item)
                if FileManager.default.fileExists(atPath: subPath.appendingPathComponent("META-INF/container.xml").path) {
                    // Move contents up
                    if let subFiles = try? FileManager.default.contentsOfDirectory(atPath: subPath.path) {
                        for f in subFiles {
                            try? FileManager.default.moveItem(
                                at: subPath.appendingPathComponent(f),
                                to: dir.appendingPathComponent(f)
                            )
                        }
                    }
                    return true
                }
            }
        }
        // Check for OPF file
        return findOPFFile(in: dir) != nil
    }

    // MARK: - XML Helpers

    private static func extractAttribute(from xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\(attribute)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else { return nil }
        return String(xml[range])
    }

    private static func extractContent(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>\\s*([\\s\\S]*?)\\s*</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else { return nil }
        var content = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip nested tags
        if let stripRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            content = stripRegex.stringByReplacingMatches(
                in: content, range: NSRange(content.startIndex..., in: content), withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content.isEmpty ? nil : content
    }

    private static func extractSpineItems(from opf: String) -> [String] {
        var items: [String] = []
        let pattern = #"<itemref[^>]*idref="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return items }
        let matches = regex.matches(in: opf, range: NSRange(opf.startIndex..., in: opf))
        for match in matches {
            if let range = Range(match.range(at: 1), in: opf) {
                items.append(String(opf[range]))
            }
        }
        return items
    }

    private static func extractManifestItems(from opf: String) -> [String: String] {
        var manifest: [String: String] = [:]
        // Match <item ...> and extract id + href from attributes
        let itemPattern = #"<item\s+([^>]*)/?>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive),
              let idRegex = try? NSRegularExpression(pattern: #"\bid="([^"]+)""#),
              let hrefRegex = try? NSRegularExpression(pattern: #"\bhref="([^"]+)""#)
        else { return manifest }
        
        let matches = itemRegex.matches(in: opf, range: NSRange(opf.startIndex..., in: opf))
        for match in matches {
            guard let attrRange = Range(match.range(at: 1), in: opf) else { continue }
            let attrs = String(opf[attrRange])
            
            guard let idMatch = idRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                  let idRange = Range(idMatch.range(at: 1), in: attrs),
                  let hrefMatch = hrefRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: attrs)
            else { continue }
            
            manifest[String(attrs[idRange])] = String(attrs[hrefRange])
        }
        
        return manifest
    }

    private static func extractChapterTitle(filePath: String) -> String? {
        guard let html = readFileContent(at: URL(fileURLWithPath: filePath)) else { return nil }
        
        if let title = extractContent(from: html, tag: "title"),
           !title.isEmpty, title.lowercased() != "untitled" {
            return title
        }
        for tag in ["h1", "h2", "h3"] {
            if let title = extractContent(from: html, tag: tag), !title.isEmpty {
                return String(title.prefix(60))
            }
        }
        return nil
    }

    // MARK: - HTML Stripping

    static func stripHTML(_ html: String) -> String {
        var text = html
        let blockPatterns = [#"<style[^>]*>[\s\S]*?</style>"#, #"<script[^>]*>[\s\S]*?</script>"#]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }
        let nlPatterns = [#"<br\s*/?>"#, #"</p>"#, #"</div>"#, #"</h[1-6]>"#]
        for pattern in nlPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
            }
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
        
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n\n")
    }
}
