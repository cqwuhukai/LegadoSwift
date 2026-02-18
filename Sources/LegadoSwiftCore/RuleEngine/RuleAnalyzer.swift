import Foundation

/// Port of Android's RuleAnalyzer.kt
/// Generic rule splitting handler — splits rules by combinators (&&, ||, %%)
/// while respecting balanced brackets/parentheses and quotes.
public class RuleAnalyzer {
    private var queue: String
    private var chars: [Character]
    private var pos: Int = 0
    private var start: Int = 0
    private var startX: Int = 0

    private var rule: [String] = []
    private var step: Int = 0
    public var elementsType: String = ""

    private let isCode: Bool

    public init(_ data: String, code: Bool = false) {
        self.queue = data
        self.chars = Array(data)
        self.isCode = code
    }

    /// Trim leading '@' or whitespace characters
    public func trim() {
        guard pos < chars.count else { return }
        if chars[pos] == "@" || chars[pos] < "!" {
            pos += 1
            while pos < chars.count && (chars[pos] == "@" || chars[pos] < "!") {
                pos += 1
            }
            start = pos
            startX = pos
        }
    }

    /// Reset position to 0 for reuse
    public func reSetPos() {
        pos = 0
        startX = 0
    }

    // MARK: - consumeTo / consumeToAny

    /// Advance pos to next occurrence of seq. Returns true if found.
    private func consumeTo(_ seq: String) -> Bool {
        start = pos
        if let range = queue.range(of: seq, range: queue.index(queue.startIndex, offsetBy: pos)..<queue.endIndex) {
            pos = queue.distance(from: queue.startIndex, to: range.lowerBound)
            return true
        }
        return false
    }

    /// Advance pos to next occurrence of any seq. Sets `step` to matched length. Returns true if found.
    private func consumeToAny(_ seqs: [String]) -> Bool {
        var p = pos
        while p < chars.count {
            for s in seqs {
                let sChars = Array(s)
                if p + sChars.count <= chars.count {
                    var match = true
                    for j in 0..<sChars.count {
                        if chars[p + j] != sChars[j] {
                            match = false
                            break
                        }
                    }
                    if match {
                        step = sChars.count
                        self.pos = p
                        return true
                    }
                }
            }
            p += 1
        }
        return false
    }

    /// Find first position of any of the given characters from current pos. Returns -1 if not found.
    private func findToAny(_ targets: [Character]) -> Int {
        var p = pos
        while p < chars.count {
            for t in targets {
                if chars[p] == t { return p }
            }
            p += 1
        }
        return -1
    }

    // MARK: - Balanced group extraction

    /// Pull a balanced group for code (respects quotes with escape characters, and [] nesting)
    private func chompCodeBalanced(open: Character, close: Character) -> Bool {
        var p = pos
        var depth = 0
        var otherDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        repeat {
            if p >= chars.count { break }
            let c = chars[p]
            p += 1
            if c != "\\" {
                if c == "'" && !inDoubleQuote { inSingleQuote = !inSingleQuote }
                else if c == "\"" && !inSingleQuote { inDoubleQuote = !inDoubleQuote }

                if inSingleQuote || inDoubleQuote { continue }

                if c == "[" { depth += 1 }
                else if c == "]" { depth -= 1 }
                else if depth == 0 {
                    if c == open { otherDepth += 1 }
                    else if c == close { otherDepth -= 1 }
                }
            } else {
                p += 1 // skip escaped char
            }
        } while depth > 0 || otherDepth > 0

        if depth > 0 || otherDepth > 0 { return false }
        self.pos = p
        return true
    }

    /// Pull a balanced group for rules (respects quotes, no escape-in-quotes)
    private func chompRuleBalanced(open: Character, close: Character) -> Bool {
        var p = pos
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        repeat {
            if p >= chars.count { break }
            let c = chars[p]
            p += 1
            if c == "'" && !inDoubleQuote { inSingleQuote = !inSingleQuote }
            else if c == "\"" && !inSingleQuote { inDoubleQuote = !inDoubleQuote }

            if inSingleQuote || inDoubleQuote { continue }
            if c == "\\" {
                p += 1
                continue
            }

            if c == open { depth += 1 }
            else if c == close { depth -= 1 }
        } while depth > 0

        if depth > 0 { return false }
        self.pos = p
        return true
    }

    private func chompBalanced(open: Character, close: Character) -> Bool {
        if isCode {
            return chompCodeBalanced(open: open, close: close)
        } else {
            return chompRuleBalanced(open: open, close: close)
        }
    }

    // MARK: - splitRule

    /// Split rule string by combinators (&&, ||, %%) while respecting balanced groups.
    public func splitRule(_ splits: String...) -> [String] {
        return splitRuleFirst(splits)
    }

    private func splitRuleFirst(_ splits: [String]) -> [String] {
        if splits.count == 1 {
            elementsType = splits[0]
            if !consumeTo(elementsType) {
                rule.append(substring(from: startX))
                return rule
            } else {
                step = elementsType.count
                return splitRuleNext()
            }
        }

        if !consumeToAny(splits) {
            rule.append(substring(from: startX))
            return rule
        }

        let end = pos
        pos = start

        while true {
            let st = findToAny(["[", "("])

            if st == -1 {
                rule = [substring(from: startX, to: end)]
                elementsType = substring(from: end, to: end + step)
                pos = end + step

                while consumeTo(elementsType) {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }
                rule.append(substring(from: pos))
                return rule
            }

            if st > end {
                rule = [substring(from: startX, to: end)]
                elementsType = substring(from: end, to: end + step)
                pos = end + step

                while consumeTo(elementsType) && pos < st {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }

                if pos > st {
                    startX = start
                    return splitRuleNext()
                } else {
                    rule.append(substring(from: pos))
                    return rule
                }
            }

            pos = st
            let next: Character = chars[pos] == "[" ? "]" : ")"
            if !chompBalanced(open: chars[pos], close: next) {
                // Unbalanced — just return what we have
                rule.append(substring(from: startX))
                return rule
            }

            if end <= pos { break }
        }

        start = pos
        return splitRuleFirst(splits)
    }

    private func splitRuleNext() -> [String] {
        let end = pos
        pos = start

        while true {
            let st = findToAny(["[", "("])

            if st == -1 {
                rule.append(substring(from: startX, to: end))
                pos = end + step

                while consumeTo(elementsType) {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }
                rule.append(substring(from: pos))
                return rule
            }

            if st > end {
                rule.append(substring(from: startX, to: end))
                pos = end + step

                while consumeTo(elementsType) && pos < st {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }

                if pos > st {
                    startX = start
                    return splitRuleNext()
                } else {
                    rule.append(substring(from: pos))
                    return rule
                }
            }

            pos = st
            let next: Character = chars[pos] == "[" ? "]" : ")"
            if !chompBalanced(open: chars[pos], close: next) {
                rule.append(substring(from: startX))
                return rule
            }

            if end <= pos { break }
        }

        start = pos

        if !consumeTo(elementsType) {
            rule.append(substring(from: startX))
            return rule
        } else {
            return splitRuleNext()
        }
    }

    // MARK: - innerRule

    /// Replace embedded rules like {$.path} within a string
    public func innerRule(_ inner: String, startStep: Int = 1, endStep: Int = 1, handler: (String) -> String?) -> String {
        var result = ""

        while consumeTo(inner) {
            let posPre = pos
            if chompCodeBalanced(open: "{", close: "}") {
                let ruleContent = substring(from: posPre + startStep, to: pos - endStep)
                if let value = handler(ruleContent), !value.isEmpty {
                    result += substring(from: startX, to: posPre) + value
                    startX = pos
                    continue
                }
            }
            pos += inner.count
        }

        if startX == 0 { return "" }
        result += substring(from: startX)
        return result
    }

    /// Replace embedded rules with start/end markers
    public func innerRule(startStr: String, endStr: String, handler: (String) -> String?) -> String {
        var result = ""

        while consumeTo(startStr) {
            pos += startStr.count
            let posPre = pos
            if consumeTo(endStr) {
                let value = handler(substring(from: posPre, to: pos)) ?? ""
                result += substring(from: startX, to: posPre - startStr.count) + value
                pos += endStr.count
                startX = pos
            }
        }

        if startX == 0 { return queue }
        result += substring(from: startX)
        return result
    }

    // MARK: - Helpers

    private func substring(from: Int) -> String {
        guard from < queue.count else { return "" }
        let idx = queue.index(queue.startIndex, offsetBy: from)
        return String(queue[idx...])
    }

    private func substring(from: Int, to: Int) -> String {
        guard from < queue.count else { return "" }
        let fromIdx = queue.index(queue.startIndex, offsetBy: from)
        let toIdx = queue.index(queue.startIndex, offsetBy: min(to, queue.count))
        return String(queue[fromIdx..<toIdx])
    }
}
