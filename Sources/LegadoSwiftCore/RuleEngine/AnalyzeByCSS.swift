import Foundation
import SwiftSoup

/// Port of Android's AnalyzeByJSoup.kt
/// Uses SwiftSoup for CSS selector-based HTML parsing with custom Legado syntax:
/// - `@CSS:selector@attr` — CSS selector mode
/// - `tag.name`, `class.name`, `id.name` — element lookups
/// - `@` chaining — navigate through nested elements
/// - `[index]` filtering — select specific elements by index
/// - lastRule: `text`, `textNodes`, `ownText`, `html`, `all`, or attribute name
public class AnalyzeByCSS {

    private var element: Element

    public init(content: Any) {
        if let el = content as? Element {
            self.element = el
        } else {
            let html = "\(content)"
            do {
                if html.trimmingCharacters(in: .whitespaces).hasPrefix("<?xml") {
                    self.element = try SwiftSoup.parse(html, "", Parser.xmlParser())
                } else {
                    self.element = try SwiftSoup.parse(html)
                }
            } catch {
                self.element = try! SwiftSoup.parse(html)
            }
        }
    }

    // MARK: - Get Elements

    /// Get elements matching a rule string
    public func getElements(_ rule: String) -> Elements {
        return getElements(element, rule: rule)
    }

    private func getElements(_ temp: Element?, rule: String) -> Elements {
        guard let temp = temp, !rule.isEmpty else { return Elements() }

        let elements = Elements()
        let sourceRule = CSSSourceRule(rule)
        let ruleAnalyzer = RuleAnalyzer(sourceRule.elementsRule)
        let ruleStrS = ruleAnalyzer.splitRule("&&", "||", "%%")

        var elementsList: [Elements] = []

        if sourceRule.isCss {
            for ruleStr in ruleStrS {
                do {
                    let tempS = try temp.select(ruleStr)
                    elementsList.append(tempS)
                    if tempS.size() > 0 && ruleAnalyzer.elementsType == "||" {
                        break
                    }
                } catch {
                    // CSS selector failed, skip
                }
            }
        } else {
            for ruleStr in ruleStrS {
                let rsRule = RuleAnalyzer(ruleStr)
                rsRule.trim()
                let rs = rsRule.splitRule("@")

                let el: Elements
                if rs.count > 1 {
                    var currentElements = Elements()
                    currentElements.add(temp)
                    for rl in rs {
                        let es = Elements()
                        for et in currentElements {
                            let subElements = getElements(et, rule: rl)
                            for subEl in subElements {
                                es.add(subEl)
                            }
                        }
                        currentElements = es
                    }
                    el = currentElements
                } else {
                    el = getElementsSingle(temp, rule: ruleStr)
                }

                elementsList.append(el)
                if el.size() > 0 && ruleAnalyzer.elementsType == "||" {
                    break
                }
            }
        }

        if !elementsList.isEmpty {
            if ruleAnalyzer.elementsType == "%%" {
                let maxCount = elementsList.first?.size() ?? 0
                for i in 0..<maxCount {
                    for es in elementsList {
                        if i < es.size() {
                            elements.add(es.array()[i])
                        }
                    }
                }
            } else {
                for es in elementsList {
                    for el in es {
                        elements.add(el)
                    }
                }
            }
        }
        return elements
    }

    // MARK: - Get String

    /// Get merged string from rule
    public func getString(_ ruleStr: String) -> String? {
        if ruleStr.isEmpty { return nil }
        let list = getStringList(ruleStr)
        if list.isEmpty { return nil }
        if list.count == 1 { return list.first }
        return list.joined(separator: "\n")
    }

    /// Get first string from rule
    func getString0(_ ruleStr: String) -> String {
        let list = getStringList(ruleStr)
        return list.isEmpty ? "" : list[0]
    }

    // MARK: - Get String List

    /// Get all strings matching rule
    public func getStringList(_ ruleStr: String) -> [String] {
        var textS: [String] = []
        if ruleStr.isEmpty { return textS }

        let sourceRule = CSSSourceRule(ruleStr)

        if sourceRule.elementsRule.isEmpty {
            if let data = try? element.text() {
                textS.append(data)
            }
        } else {
            let ruleAnalyzer = RuleAnalyzer(sourceRule.elementsRule)
            let ruleStrS = ruleAnalyzer.splitRule("&&", "||", "%%")

            var results: [[String]] = []
            for ruleStrX in ruleStrS {
                let temp: [String]?
                if sourceRule.isCss {
                    // CSS mode: selector@attribute
                    if let lastIndex = ruleStrX.lastIndex(of: "@") {
                        let selector = String(ruleStrX[ruleStrX.startIndex..<lastIndex])
                        let attr = String(ruleStrX[ruleStrX.index(after: lastIndex)...])
                        do {
                            let elements = try element.select(selector)
                            temp = getResultLast(elements, lastRule: attr)
                        } catch {
                            temp = nil
                        }
                    } else {
                        temp = nil
                    }
                } else {
                    temp = getResultList(ruleStrX)
                }

                if let temp = temp, !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzer.elementsType == "||" { break }
                }
            }

            if !results.isEmpty {
                if ruleAnalyzer.elementsType == "%%" {
                    let maxCount = results[0].count
                    for i in 0..<maxCount {
                        for temp in results {
                            if i < temp.count {
                                textS.append(temp[i])
                            }
                        }
                    }
                } else {
                    for temp in results {
                        textS.append(contentsOf: temp)
                    }
                }
            }
        }
        return textS
    }

    // MARK: - Internal Helpers

    /// Get content list by navigating through @ rules
    private func getResultList(_ ruleStr: String) -> [String]? {
        if ruleStr.isEmpty { return nil }

        var elements = Elements()
        elements.add(element)

        let rule = RuleAnalyzer(ruleStr)
        rule.trim()
        let rules = rule.splitRule("@")

        let last = rules.count - 1
        for i in 0..<last {
            let es = Elements()
            for elt in elements {
                let subEls = getElementsSingle(elt, rule: rules[i])
                for subEl in subEls {
                    es.add(subEl)
                }
            }
            elements = es
        }

        guard !elements.isEmpty() else { return nil }
        return getResultLast(elements, lastRule: rules[last])
    }

    /// Extract content from elements using the last rule part
    private func getResultLast(_ elements: Elements, lastRule: String) -> [String] {
        var textS: [String] = []
        switch lastRule {
        case "text":
            for element in elements {
                if let text = try? element.text(), !text.isEmpty {
                    textS.append(text)
                }
            }
        case "textNodes":
            for element in elements {
                let textNodes = element.textNodes()
                var tn: [String] = []
                for item in textNodes {
                    let text = item.text().trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        tn.append(text)
                    }
                }
                if !tn.isEmpty {
                    textS.append(tn.joined(separator: "\n"))
                }
            }
        case "ownText":
            for element in elements {
                let text = element.ownText()
                if !text.isEmpty {
                    textS.append(text)
                }
            }
        case "html":
            do {
                try elements.select("script").remove()
                try elements.select("style").remove()
                let html = try elements.outerHtml()
                if !html.isEmpty {
                    textS.append(html)
                }
            } catch {}
        case "all":
            if let html = try? elements.outerHtml() {
                textS.append(html)
            }
        default:
            // Treat as attribute name
            for element in elements {
                if let url = try? element.attr(lastRule), !url.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !textS.contains(url) {
                        textS.append(url)
                    }
                }
            }
        }
        return textS
    }

    /// Get elements matching a single rule (no @ chaining)
    /// Supports: children, class.name, tag.name, id.name, text.name, CSS selectors
    /// Also supports index filtering: tag.div.0, [0:3], [-1], etc.
    private func getElementsSingle(_ temp: Element, rule: String) -> Elements {
        let ruleStr = rule.trimmingCharacters(in: .whitespaces)
        if ruleStr.isEmpty { return Elements() }

        // Parse index notation
        let parsed = parseIndexRule(ruleStr)
        let beforeRule = parsed.beforeRule
        let indexInfo = parsed.indexInfo

        // Get all matching elements
        var elements: Elements
        if beforeRule.isEmpty {
            elements = temp.children()
        } else {
            let parts = beforeRule.split(separator: ".", maxSplits: 1).map(String.init)
            if parts.count >= 2 {
                switch parts[0] {
                case "children":
                    elements = temp.children()
                case "class":
                    do { elements = try temp.getElementsByClass(parts[1]) } catch { elements = Elements() }
                case "tag":
                    do { elements = try temp.getElementsByTag(parts[1]) } catch { elements = Elements() }
                case "id":
                    if let el = try? temp.getElementById(parts[1]) {
                        elements = Elements()
                        elements.add(el)
                    } else {
                        elements = Elements()
                    }
                case "text":
                    do { elements = try temp.getElementsContainingOwnText(parts[1]) } catch { elements = Elements() }
                default:
                    do { elements = try temp.select(beforeRule) } catch { elements = Elements() }
                }
            } else {
                do { elements = try temp.select(beforeRule) } catch { elements = Elements() }
            }
        }

        // Apply index filtering if present
        if let info = indexInfo {
            elements = applyIndexFilter(elements: elements, info: info)
        }

        return elements
    }

    // MARK: - Index Parsing

    struct IndexInfo {
        var isExclude: Bool = false
        var indices: [IndexEntry] = []
    }

    enum IndexEntry {
        case single(Int)
        case range(start: Int?, end: Int?, step: Int)
    }

    struct ParsedRule {
        var beforeRule: String
        var indexInfo: IndexInfo?
    }

    private func parseIndexRule(_ rule: String) -> ParsedRule {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)

        // Check for [index...] notation
        if trimmed.hasSuffix("]"), let bracketStart = findMatchingBracket(trimmed) {
            let before = String(trimmed[trimmed.startIndex..<trimmed.index(trimmed.startIndex, offsetBy: bracketStart)])
            let indexStr = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: bracketStart + 1)..<trimmed.index(before: trimmed.endIndex)])

            var info = IndexInfo()

            // Check for ! (exclude)
            var content = indexStr
            if content.hasPrefix("!") {
                info.isExclude = true
                content = String(content.dropFirst())
            }

            // Parse comma-separated entries
            let parts = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts {
                if part.contains(":") {
                    // Range: start:end or start:end:step
                    let rangeParts = part.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    let start = rangeParts[0].isEmpty ? nil : Int(rangeParts[0])
                    let end = rangeParts.count > 1 ? (rangeParts[1].isEmpty ? nil : Int(rangeParts[1])) : nil
                    let step = rangeParts.count > 2 ? (Int(rangeParts[2]) ?? 1) : 1
                    info.indices.append(.range(start: start, end: end, step: step))
                } else if let idx = Int(part) {
                    info.indices.append(.single(idx))
                }
            }

            return ParsedRule(beforeRule: before, indexInfo: info.indices.isEmpty ? nil : info)
        }

        // Check for legacy notation: tag.div.0 or tag.div!0:3
        // Look for trailing .N or !N patterns
        if let match = findLegacyIndex(trimmed) {
            return match
        }

        return ParsedRule(beforeRule: trimmed, indexInfo: nil)
    }

    private func findMatchingBracket(_ str: String) -> Int? {
        guard let lastBracket = str.lastIndex(of: "[") else { return nil }
        return str.distance(from: str.startIndex, to: lastBracket)
    }

    private func findLegacyIndex(_ rule: String) -> ParsedRule? {
        // Match patterns like tag.div.0, tag.div.-1, tag.div!0:3
        let chars = Array(rule)
        var i = chars.count - 1
        var numbers: [Int] = []
        var currentNum = ""
        var isNeg = false
        // var separator: Character = "." // Unused

        while i >= 0 {
            let c = chars[i]
            if c == " " { i -= 1; continue }
            if c >= "0" && c <= "9" {
                currentNum = String(c) + currentNum
            } else if c == "-" {
                isNeg = true
            } else if c == ":" {
                if !currentNum.isEmpty {
                    numbers.append(isNeg ? -Int(currentNum)! : Int(currentNum)!)
                }
                currentNum = ""
                isNeg = false
            } else if c == "!" || c == "." {
                if !currentNum.isEmpty {
                    numbers.append(isNeg ? -Int(currentNum)! : Int(currentNum)!)

                    // separator = c // Unused
                    let before = String(chars[0..<i])
                    var info = IndexInfo()
                    info.isExclude = (c == "!")

                    // Legacy: indices are accumulated in reverse
                    let reversedNumbers = numbers.reversed()
                    for n in reversedNumbers {
                        info.indices.append(.single(n))
                    }

                    return ParsedRule(beforeRule: before, indexInfo: info)
                }
                break
            } else {
                break
            }
            i -= 1
        }
        return nil
    }

    private func applyIndexFilter(elements: Elements, info: IndexInfo) -> Elements {
        let len = elements.size()
        guard len > 0 else { return elements }

        var indexSet: [Int] = []

        for entry in info.indices {
            switch entry {
            case .single(let idx):
                let resolved = idx < 0 ? idx + len : idx
                if resolved >= 0 && resolved < len {
                    indexSet.append(resolved)
                }
            case .range(let startOpt, let endOpt, let stepVal):
                var start = startOpt ?? 0
                if start < 0 { start += len }
                var end = endOpt ?? (len - 1)
                if end < 0 { end += len }
                start = max(0, min(start, len - 1))
                end = max(0, min(end, len - 1))

                let step = stepVal > 0 ? stepVal : max(1, stepVal + len)

                if end >= start {
                    var i = start
                    while i <= end {
                        indexSet.append(i)
                        i += step
                    }
                } else {
                    var i = start
                    while i >= end {
                        indexSet.append(i)
                        i -= step
                    }
                }
            }
        }

        // Remove duplicates while preserving order
        var seen = Set<Int>()
        let uniqueIndices = indexSet.filter { seen.insert($0).inserted }

        let arr = elements.array()
        if info.isExclude {
            let result = Elements()
            let excludeSet = Set(uniqueIndices)
            for (i, el) in arr.enumerated() {
                if !excludeSet.contains(i) {
                    result.add(el)
                }
            }
            return result
        } else {
            let result = Elements()
            for idx in uniqueIndices {
                if idx >= 0 && idx < arr.count {
                    result.add(arr[idx])
                }
            }
            return result
        }
    }

    // MARK: - CSS Source Rule

    struct CSSSourceRule {
        var isCss: Bool = false
        var elementsRule: String

        init(_ ruleStr: String) {
            if ruleStr.lowercased().hasPrefix("@css:") {
                isCss = true
                elementsRule = String(ruleStr.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else {
                elementsRule = ruleStr
            }
        }
    }
}
