import Foundation

/// Port of Android's AnalyzeByJSonPath.kt
/// Pure Swift JSONPath evaluator — handles common JSONPath expressions like:
/// $.data.list[*].title, $.books[0].name, $..author
/// Supports && / || / %% combinators via RuleAnalyzer
/// Supports embedded rules like {$.path}
public class AnalyzeByJSONPath {

    private var context: Any

    public init(content: Any) {
        if let str = content as? String {
            if let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                self.context = json
            } else {
                self.context = str
            }
        } else {
            self.context = content
        }
    }

    // MARK: - getString

    public func getString(_ rule: String) -> String? {
        if rule.isEmpty { return nil }

        let ruleAnalyzer = RuleAnalyzer(rule, code: true)
        let rules = ruleAnalyzer.splitRule("&&", "||")

        if rules.count == 1 {
            // Check for embedded rules {$.xxx}
            let analyzer = RuleAnalyzer(rule, code: true)
            analyzer.reSetPos()
            let result = analyzer.innerRule("{$.") { getString("$." + $0) }

            if result.isEmpty {
                // Direct JSONPath evaluation
                let obj = readPath(rule, from: context)
                if let arr = obj as? [Any] {
                    return arr.map { "\($0)" }.joined(separator: "\n")
                } else if let val = obj {
                    let s = "\(val)"
                    return s == "<null>" ? nil : s
                }
                return nil
            }
            return result
        } else {
            var textList: [String] = []
            for rl in rules {
                if let temp = getString(rl), !temp.isEmpty {
                    textList.append(temp)
                    if ruleAnalyzer.elementsType == "||" { break }
                }
            }
            return textList.joined(separator: "\n")
        }
    }

    // MARK: - getStringList

    public func getStringList(_ rule: String) -> [String] {
        var result: [String] = []
        if rule.isEmpty { return result }

        let ruleAnalyzer = RuleAnalyzer(rule, code: true)
        let rules = ruleAnalyzer.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            let analyzer = RuleAnalyzer(rule, code: true)
            analyzer.reSetPos()
            let st = analyzer.innerRule("{$.") { getString("$." + $0) }

            if st.isEmpty {
                let obj = readPath(rule, from: context)
                if let arr = obj as? [Any] {
                    for o in arr {
                        result.append("\(o)")
                    }
                } else if let val = obj {
                    let s = "\(val)"
                    if s != "<null>" {
                        result.append(s)
                    }
                }
            } else {
                result.append(st)
            }
            return result
        } else {
            var results: [[String]] = []
            for rl in rules {
                let temp = getStringList(rl)
                if !temp.isEmpty {
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
                                result.append(temp[i])
                            }
                        }
                    }
                } else {
                    for temp in results {
                        result.append(contentsOf: temp)
                    }
                }
            }
            return result
        }
    }

    // MARK: - getList (returns list of Any for element iteration)

    public func getList(_ rule: String) -> [Any]? {
        var result: [Any] = []
        if rule.isEmpty { return result }

        let ruleAnalyzer = RuleAnalyzer(rule, code: true)
        let rules = ruleAnalyzer.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            if let obj = readPath(rules[0], from: context) as? [Any] {
                return obj
            }
            return nil
        } else {
            var results: [[Any]] = []
            for rl in rules {
                if let temp = getList(rl), !temp.isEmpty {
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
                                result.append(temp[i])
                            }
                        }
                    }
                } else {
                    for temp in results {
                        result.append(contentsOf: temp)
                    }
                }
            }
            return result
        }
    }

    // MARK: - JSONPath Evaluator

    /// Evaluate a JSONPath expression against a JSON object
    /// Supports: $.key, $[0], $.key1.key2, $[*], $.key[0].subkey, $..key (recursive descent)
    private func readPath(_ path: String, from obj: Any) -> Any? {
        var p = path.trimmingCharacters(in: .whitespaces)

        // Remove leading $ or $. prefix
        if p.hasPrefix("$.") {
            p = String(p.dropFirst(2))
        } else if p.hasPrefix("$[") {
            p = String(p.dropFirst(1))
        } else if p == "$" {
            return obj
        }

        // Handle recursive descent $..key
        if p.hasPrefix(".") {
            let key = String(p.dropFirst())
            return recursiveSearch(key: key, in: obj)
        }

        return evaluatePath(p, from: obj)
    }

    private func evaluatePath(_ path: String, from obj: Any) -> Any? {
        if path.isEmpty { return obj }

        let tokens = tokenizePath(path)
        var current: Any = obj

        for token in tokens {
            if let next = resolveToken(token, from: current) {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    private enum PathToken {
        case key(String)
        case index(Int)
        case wildcard
        case slice(start: Int?, end: Int?, step: Int?)
        case filter(String)
    }

    private func tokenizePath(_ path: String) -> [PathToken] {
        var tokens: [PathToken] = []
        let chars = Array(path)
        var i = 0

        while i < chars.count {
            if chars[i] == "[" {
                // Find matching ]
                var depth = 1
                var j = i + 1
                while j < chars.count && depth > 0 {
                    if chars[j] == "[" { depth += 1 }
                    else if chars[j] == "]" { depth -= 1 }
                    j += 1
                }
                let content = String(chars[(i+1)..<(j-1)])
                i = j

                if content == "*" {
                    tokens.append(.wildcard)
                } else if content.contains(":") {
                    // Slice notation
                    let parts = content.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    let start = parts.count > 0 && !parts[0].isEmpty ? Int(parts[0]) : nil
                    let end = parts.count > 1 && !parts[1].isEmpty ? Int(parts[1]) : nil
                    let step = parts.count > 2 && !parts[2].isEmpty ? Int(parts[2]) : nil
                    tokens.append(.slice(start: start, end: end, step: step))
                } else if let idx = Int(content) {
                    tokens.append(.index(idx))
                } else if content.hasPrefix("?(") {
                    tokens.append(.filter(content))
                } else {
                    // Quoted key or plain key
                    let key = content.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    tokens.append(.key(key))
                }
            } else if chars[i] == "." {
                i += 1
                // Collect key name
                var key = ""
                while i < chars.count && chars[i] != "." && chars[i] != "[" {
                    key.append(chars[i])
                    i += 1
                }
                if !key.isEmpty {
                    if key == "*" {
                        tokens.append(.wildcard)
                    } else {
                        tokens.append(.key(key))
                    }
                }
            } else {
                // Collect key name
                var key = ""
                while i < chars.count && chars[i] != "." && chars[i] != "[" {
                    key.append(chars[i])
                    i += 1
                }
                if !key.isEmpty {
                    if key == "*" {
                        tokens.append(.wildcard)
                    } else {
                        tokens.append(.key(key))
                    }
                }
            }
        }
        return tokens
    }

    private func resolveToken(_ token: PathToken, from obj: Any) -> Any? {
        switch token {
        case .key(let key):
            if let dict = obj as? [String: Any] {
                return dict[key]
            }
            if let arr = obj as? [Any] {
                let res = arr.compactMap { ($0 as? [String: Any])?[key] }
                return res.isEmpty ? nil : res
            }
            return nil

        case .index(let idx):
            if let arr = obj as? [Any] {
                let resolvedIdx = idx < 0 ? arr.count + idx : idx
                guard resolvedIdx >= 0 && resolvedIdx < arr.count else { return nil }
                return arr[resolvedIdx]
            }
            return nil

        case .wildcard:
            if let arr = obj as? [Any] {
                return arr
            }
            if let dict = obj as? [String: Any] {
                return Array(dict.values)
            }
            return nil

        case .slice(let startOpt, let endOpt, let stepOpt):
            guard let arr = obj as? [Any] else { return nil }
            let len = arr.count
            var start = startOpt ?? 0
            var end = endOpt ?? len
            let step = stepOpt ?? 1
            if start < 0 { start += len }
            if end < 0 { end += len }
            start = max(0, min(start, len))
            end = max(0, min(end, len))
            var result: [Any] = []
            if step > 0 {
                var i = start
                while i < end {
                    result.append(arr[i])
                    i += step
                }
            }
            return result

        case .filter:
            // Basic filter support — return all elements for now
            if let arr = obj as? [Any] {
                return arr
            }
            return nil
        }
    }

    private func recursiveSearch(key: String, in obj: Any) -> Any? {
        var results: [Any] = []
        recursiveSearchHelper(key: key, obj: obj, results: &results)
        return results.isEmpty ? nil : (results.count == 1 ? results[0] : results)
    }

    private func recursiveSearchHelper(key: String, obj: Any, results: inout [Any]) {
        if let dict = obj as? [String: Any] {
            if let val = dict[key] {
                if let arr = val as? [Any] {
                    results.append(contentsOf: arr)
                } else {
                    results.append(val)
                }
            }
            for (_, v) in dict {
                recursiveSearchHelper(key: key, obj: v, results: &results)
            }
        } else if let arr = obj as? [Any] {
            for item in arr {
                recursiveSearchHelper(key: key, obj: item, results: &results)
            }
        }
    }
}
