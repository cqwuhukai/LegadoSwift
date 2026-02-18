import Foundation
import SwiftSoup

/// Context object for rule analysis — holds book, source, and variable state
public class AnalyzeContext {
    var book: Book?
    var source: BookSource?
    private var variableMap: [String: String] = [:]

    public init(book: Book? = nil, source: BookSource? = nil) {
        self.book = book
        self.source = source
    }

    public func put(_ key: String, _ value: String) {
        variableMap[key] = value
    }

    public func get(_ key: String) -> String? {
        // Check custom variables first
        if let val = variableMap[key] { return val }
        // Check book properties
        if let book = book {
            switch key {
            case "name", "bookName": return book.name
            case "author", "bookAuthor": return book.author
            case "bookUrl": return book.bookUrl
            case "intro": return book.intro
            default: break
            }
        }
        // Check source properties
        if let source = source {
            switch key {
            case "sourceUrl", "bookSourceUrl": return source.bookSourceUrl
            case "sourceName", "bookSourceName": return source.bookSourceName
            default: break
            }
        }
        return nil
    }
}

/// Rule parsing mode
public enum RuleMode: String {
    case `default` // CSS/JSoup selector
    case xpath     // XPath
    case jsonPath  // JSONPath
    case js        // JavaScript
    case regex     // Regular expression

    /// Auto-detect mode from rule string
    public static func detect(from rule: String) -> RuleMode {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@XPath:") || trimmed.lowercased().hasPrefix("@xpath:") {
            return .xpath
        }
        if trimmed.hasPrefix("@Json:") || trimmed.lowercased().hasPrefix("@json:") {
            return .jsonPath
        }
        if trimmed.hasPrefix("@CSS:") || trimmed.lowercased().hasPrefix("@css:") {
            return .default
        }
        if trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") {
            return .jsonPath
        }
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("/") {
            return .xpath
        }
        return .default
    }
}

/// Rule combination type
public enum RuleCombinationType: String {
    case and = "&&"
    case or = "||"
    case combine = "%%"
}

/// Port of Android's AnalyzeRule.kt
/// Central rule dispatch — detects mode, maintains context, handles put/get variables,
/// regex replacement, and dispatches to CSS/JSONPath analyzers.
public class AnalyzeRule {
    private var content: Any
    private var analyzeContext: AnalyzeContext
    private var isJSON: Bool = false

    private var analyzeByCSS: AnalyzeByCSS?
    private var analyzeByJSONPath: AnalyzeByJSONPath?
    private var jsEngine: JSEngine?

    // JS pattern: <js>...</js> or @js:...
    private static let jsPatternStr = #"<js>([\s\S]*?)</js>|@js:([\s\S]*?)$"#

    // put pattern: @put:\{...}
    private static let putPatternStr = #"@put:\{([^}]+)\}"#

    // eval pattern: @get:\{[^}]+\} or \{\{.+?\}\}
    private static let evalPatternStr = #"@get:\{[^}]+\}|\{\{[\s\S]+?\}\}"#

    // regex pattern: \$\d{1,2}
    private static let regexPatternStr = #"\$\d{1,2}"#

    public init(content: Any, context: AnalyzeContext = AnalyzeContext()) {
        self.content = content
        self.analyzeContext = context
        detectContentType()
    }

    private func detectContentType() {
        if let str = content as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        } else if content is [String: Any] || content is [Any] {
            isJSON = true
        }
    }

    /// Set/replace the content to analyze
    public func setContent(_ content: Any, baseUrl: String? = nil) {
        self.content = content
        self.analyzeByCSS = nil
        self.analyzeByJSONPath = nil
        detectContentType()
    }

    // MARK: - Analyzer Accessors

    private func getAnalyzeByCSS() -> AnalyzeByCSS {
        if analyzeByCSS == nil {
            analyzeByCSS = AnalyzeByCSS(content: content)
        }
        return analyzeByCSS!
    }

    private func getAnalyzeByJSONPath() -> AnalyzeByJSONPath {
        if analyzeByJSONPath == nil {
            analyzeByJSONPath = AnalyzeByJSONPath(content: content)
        }
        return analyzeByJSONPath!
    }

    private func getJSEngine() -> JSEngine {
        if jsEngine == nil {
            jsEngine = JSEngine()
        }
        return jsEngine!
    }

    // MARK: - Public API

    /// Get list of elements matching rule (for iterating, e.g. book list)
    public func getElements(_ ruleStr: String?) -> [Any] {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return [] }

        let sourceRules = splitSourceRule(ruleStr)
        var result: Any = content

        for sourceRule in sourceRules {
            putVariables(sourceRule.putMap)

            switch sourceRule.mode {
            case .jsonPath:
                let analyzer = AnalyzeByJSONPath(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                if let list = analyzer.getList(madeRule) {
                    if sourceRules.count == 1 {
                        return list
                    }
                    result = list
                }
            case .default:
                let analyzer = AnalyzeByCSS(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                let elements = analyzer.getElements(madeRule)
                let arr = elements.array()
                if sourceRules.count == 1 {
                    return arr
                }
                result = arr
            case .xpath:
                // XPath not implemented — fall back to CSS
                let analyzer = AnalyzeByCSS(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                let elements = analyzer.getElements(madeRule)
                return elements.array()
            case .js:
                let engine = getJSEngine()
                engine.setBinding("result", value: result)
                if let jsResult = engine.evaluate(sourceRule.rule, with: result, context: analyzeContext) {
                    result = jsResult
                }
            case .regex:
                // Regex can't produce elements — skip
                break
            }
        }

        if let arr = result as? [Any] {
            return arr
        }
        return []
    }

    /// Get single string from rule
    public func getString(_ ruleStr: String?) -> String? {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return nil }
        let ruleList = splitSourceRuleCached(ruleStr)
        return getString(ruleList)
    }

    /// Get single string from pre-parsed rule list
    public func getString(_ ruleList: [SourceRule]) -> String? {
        var result: Any = content

        for sourceRule in ruleList {
            putVariables(sourceRule.putMap)

            if sourceRule.rule.isEmpty && sourceRule.replaceRegex.isEmpty {
                continue
            }

            var resultStr: String?

            switch sourceRule.mode {
            case .jsonPath:
                let analyzer = AnalyzeByJSONPath(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                resultStr = analyzer.getString(madeRule)

            case .default:
                let analyzer = AnalyzeByCSS(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                resultStr = analyzer.getString(madeRule)

            case .xpath:
                // XPath not implemented — fall back to CSS
                let analyzer = AnalyzeByCSS(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                resultStr = analyzer.getString(madeRule)

            case .js:
                let engine = getJSEngine()
                engine.setBinding("result", value: result)
                if let jsResult = engine.evaluate(sourceRule.rule, with: result, context: analyzeContext) {
                    resultStr = "\(jsResult)"
                }

            case .regex:
                // For regex mode, the rule is treated as a pattern to apply
                let madeRule = makeUpRule(sourceRule, result: result)
                if !madeRule.isEmpty {
                    resultStr = madeRule
                } else {
                    resultStr = "\(result)"
                }
            }

            if let str = resultStr {
                let replaced = replaceRegex(str, rule: sourceRule)
                result = replaced
            }
        }

        let finalStr = "\(result)"
        return finalStr.isEmpty ? nil : finalStr
    }

    /// Get list of strings from rule
    public func getStringList(_ ruleStr: String?) -> [String]? {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return nil }

        let ruleList = splitSourceRuleCached(ruleStr)
        return getStringList(ruleList)
    }

    public func getStringList(_ ruleList: [SourceRule]) -> [String]? {
        var result: Any = content
        var resultList: [String]? = nil

        for sourceRule in ruleList {
            putVariables(sourceRule.putMap)

            switch sourceRule.mode {
            case .jsonPath:
                let analyzer = AnalyzeByJSONPath(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                let list = analyzer.getStringList(madeRule)
                resultList = list.isEmpty ? nil : list

            case .default:
                let analyzer = AnalyzeByCSS(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                let list = analyzer.getStringList(madeRule)
                resultList = list.isEmpty ? nil : list

            case .xpath:
                let analyzer = AnalyzeByCSS(content: result)
                let madeRule = makeUpRule(sourceRule, result: result)
                let list = analyzer.getStringList(madeRule)
                resultList = list.isEmpty ? nil : list

            case .js:
                let engine = getJSEngine()
                engine.setBinding("result", value: result)
                if let jsResult = engine.evaluate(sourceRule.rule, with: result, context: analyzeContext) {
                    if let arr = jsResult as? [Any] {
                        resultList = arr.map { "\($0)" }
                    } else {
                        resultList = ["\(jsResult)"]
                    }
                    result = jsResult
                }

            case .regex:
                let madeRule = makeUpRule(sourceRule, result: result)
                if !madeRule.isEmpty {
                    resultList = [madeRule]
                }
            }

            // Apply regex replacement
            if let list = resultList, !sourceRule.replaceRegex.isEmpty {
                resultList = list.map { replaceRegex($0, rule: sourceRule) }
            }

            if let list = resultList, !list.isEmpty {
                result = list
            }
        }

        return resultList
    }

    // MARK: - Variable System

    public func put(_ key: String, _ value: String) {
        analyzeContext.put(key, value)
    }

    public func get(_ key: String) -> String {
        return analyzeContext.get(key) ?? ""
    }

    private func putVariables(_ putMap: [String: String]) {
        for (key, value) in putMap {
            if let resolved = getString(value) {
                put(key, resolved)
            } else {
                put(key, value)
            }
        }
    }

    // MARK: - Rule Parsing

    /// Cache for parsed rules
    private var ruleCache: [String: [SourceRule]] = [:]

    private func splitSourceRuleCached(_ ruleStr: String) -> [SourceRule] {
        if let cached = ruleCache[ruleStr] {
            return cached
        }
        let rules = splitSourceRule(ruleStr)
        ruleCache[ruleStr] = rules
        return rules
    }

    /// Parse a rule string into a list of SourceRules, splitting by JS blocks
    public func splitSourceRule(_ ruleStr: String, allInOne: Bool = false) -> [SourceRule] {
        if ruleStr.isEmpty { return [] }

        var ruleList: [SourceRule] = []
        var mMode: RuleMode = .default
        var start = 0

        // Check for regex mode
        if allInOne && ruleStr.hasPrefix(":") {
            mMode = .regex
            start = 1
        }

        // Split by <js>...</js> and @js: blocks
        let jsPattern = try? NSRegularExpression(pattern: Self.jsPatternStr, options: [.dotMatchesLineSeparators])
        let nsStr = ruleStr as NSString
        let matches = jsPattern?.matches(in: ruleStr, range: NSRange(location: 0, length: nsStr.length)) ?? []

        for match in matches {
            if match.range.location > start {
                let tmp = nsStr.substring(with: NSRange(location: start, length: match.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !tmp.isEmpty {
                    ruleList.append(SourceRule(tmp, mode: mMode, isJSON: isJSON, context: analyzeContext))
                }
            }
            // Group 1 is <js>content</js>, Group 2 is @js:content
            let jsContent: String
            if match.range(at: 1).location != NSNotFound {
                jsContent = nsStr.substring(with: match.range(at: 1))
            } else {
                jsContent = nsStr.substring(with: match.range(at: 2))
            }
            ruleList.append(SourceRule(jsContent, mode: .js, isJSON: isJSON, context: analyzeContext))
            start = match.range.location + match.range.length
        }

        if nsStr.length > start {
            let tmp = nsStr.substring(from: start).trimmingCharacters(in: .whitespaces)
            if !tmp.isEmpty {
                ruleList.append(SourceRule(tmp, mode: mMode, isJSON: isJSON, context: analyzeContext))
            }
        }

        return ruleList
    }

    // MARK: - Regex Replacement

    /// Apply ##regex##replacement to a result string
    private func replaceRegex(_ result: String, rule: SourceRule) -> String {
        if rule.replaceRegex.isEmpty { return result }

        let pattern = rule.replaceRegex
        let replacement = rule.replacement

        if rule.replaceFirst {
            // ##match##replace### — get first match and replace
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsStr = result as NSString
                if let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: nsStr.length)) {
                    let matched = nsStr.substring(with: match.range)
                    let matchedNS = matched as NSString
                    return matchedNS.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression, range: NSRange(location: 0, length: matchedNS.length))
                }
                return ""
            }
            return replacement
        } else {
            // ##match##replace — replace all
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsStr = result as NSString
                return regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: nsStr.length), withTemplate: replacement)
            }
            return result.replacingOccurrences(of: pattern, with: replacement)
        }
    }

    // MARK: - Make Up Rule (resolve @get and {{}} expressions)

    private func makeUpRule(_ sourceRule: SourceRule, result: Any) -> String {
        var rule = sourceRule.rule

        // Resolve @get:{key} patterns
        if let regex = try? NSRegularExpression(pattern: #"@get:\{([^}]+)\}"#) {
            let nsStr = rule as NSString
            let matches = regex.matches(in: rule, range: NSRange(location: 0, length: nsStr.length)).reversed()
            for match in matches {
                let key = nsStr.substring(with: match.range(at: 1))
                let value = get(key)
                rule = (rule as NSString).replacingCharacters(in: match.range, with: value)
            }
        }

        // Resolve {{expression}} patterns
        if let regex = try? NSRegularExpression(pattern: #"\{\{([\s\S]+?)\}\}"#) {
            let nsStr = rule as NSString
            let matches = regex.matches(in: rule, range: NSRange(location: 0, length: nsStr.length)).reversed()
            for match in matches {
                let expr = nsStr.substring(with: match.range(at: 1))
                // Check if it's a rule or JS expression
                if isRule(expr) {
                    if let value = getString(expr) {
                        rule = (rule as NSString).replacingCharacters(in: match.range, with: value)
                    }
                } else {
                    let engine = getJSEngine()
                    engine.setBinding("result", value: result)
                    if let jsResult = engine.evaluate(expr, with: result, context: analyzeContext) {
                        rule = (rule as NSString).replacingCharacters(in: match.range, with: "\(jsResult)")
                    }
                }
            }
        }

        return rule
    }

    /// Check if a string looks like a rule vs JS expression
    private func isRule(_ str: String) -> Bool {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") ||
               trimmed.hasPrefix("@CSS:") || trimmed.hasPrefix("@XPath:") ||
               trimmed.hasPrefix("@Json:") || trimmed.hasPrefix("//") ||
               (trimmed.contains("@") && !trimmed.contains("("))
    }
}

// MARK: - SourceRule

/// Represents a parsed rule with mode, replacement, and variable directives
public class SourceRule {
    public var rule: String
    public var mode: RuleMode
    public var replaceRegex: String = ""
    public var replacement: String = ""
    public var replaceFirst: Bool = false
    public var putMap: [String: String] = [:]

    public init(_ ruleStr: String, mode: RuleMode = .default, isJSON: Bool = false, context: AnalyzeContext? = nil) {
        var currentRule = ruleStr

        // Detect mode from prefix
        if mode == .js || mode == .regex {
            self.mode = mode
        } else if ruleStr.lowercased().hasPrefix("@css:") {
            self.mode = .default
        } else if ruleStr.hasPrefix("@@") {
            self.mode = .default
            currentRule = String(ruleStr.dropFirst(2))
        } else if ruleStr.lowercased().hasPrefix("@xpath:") {
            self.mode = .xpath
            currentRule = String(ruleStr.dropFirst(7))
        } else if ruleStr.lowercased().hasPrefix("@json:") {
            self.mode = .jsonPath
            currentRule = String(ruleStr.dropFirst(6))
        } else if isJSON || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$[") {
            self.mode = .jsonPath
        } else if ruleStr.hasPrefix("/") {
            self.mode = .xpath
        } else {
            self.mode = mode
        }

        // Split @put rules
        currentRule = SourceRule.splitPutRule(currentRule, putMap: &putMap)

        // Split ##regex##replacement
        let regexParts = currentRule.components(separatedBy: "##")
        self.rule = regexParts[0]

        if regexParts.count >= 3 {
            replaceRegex = regexParts[1]
            replacement = regexParts[2]
            if regexParts.count > 3 && regexParts[3].isEmpty {
                // ##match##replace### means replaceFirst
                replaceFirst = true
            }
        } else if regexParts.count == 2 {
            replaceRegex = regexParts[1]
        }
    }

    /// Extract @put:{...} from rule and populate putMap
    private static func splitPutRule(_ ruleStr: String, putMap: inout [String: String]) -> String {
        var result = ruleStr
        if let regex = try? NSRegularExpression(pattern: #"@put:\{([^}]+)\}"#) {
            let nsStr = ruleStr as NSString
            let matches = regex.matches(in: ruleStr, range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let jsonStr = nsStr.substring(with: match.range(at: 1))
                // Parse JSON: {"key":"value"}
                if let data = "{\(jsonStr)}".data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    for (k, v) in json {
                        putMap[k] = v
                    }
                }
                result = (result as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    public func getParamSize() -> Int {
        return putMap.count
    }
}
