import Foundation
import JavaScriptCore

/// JavaScript engine using macOS native JavaScriptCore
/// Used for evaluating {{expression}} and <js>...</js> blocks in Legado rules
public class JSEngine {
    private var context: JSContext

    public init() {
        self.context = JSContext()!
        setupDefaultBindings()
    }

    private func setupDefaultBindings() {
        // Add console.log support
        let consoleLog: @convention(block) (String) -> Void = { message in
            print("[JS] \(message)")
        }
        context.setObject(consoleLog, forKeyedSubscript: "log" as NSString)

        // Add Java.type mock (for Android compatibility)
        context.evaluateScript("""
            var java = { type: function(name) { return {}; } };
            var Java = java;
            var console = { log: log };
        """)
    }

    /// Set a binding in the JS context
    public func setBinding(_ name: String, value: Any?) {
        if let value = value {
            context.setObject(value, forKeyedSubscript: name as NSString)
        } else {
            context.setObject(JSValue(nullIn: context), forKeyedSubscript: name as NSString)
        }
    }

    /// Evaluate JavaScript code
    public func evaluate(_ script: String, with result: Any? = nil, context analyzeContext: AnalyzeContext? = nil) -> Any? {
        // Set common bindings
        if let result = result {
            setBinding("result", value: result)
        }
        if let src = analyzeContext?.source {
            setBinding("baseUrl", value: src.bookSourceUrl)
        }
        if let book = analyzeContext?.book {
            setBinding("bookName", value: book.name)
            setBinding("bookAuthor", value: book.author)
        }

        // Evaluate
        let jsResult = context.evaluateScript(script)

        // Check for exceptions
        if let exception = context.exception {
            print("[JS Error] \(exception)")
            context.exception = nil
            return nil
        }

        // Convert result
        if let jsResult = jsResult {
            if jsResult.isNull || jsResult.isUndefined {
                return nil
            }
            if jsResult.isString {
                return jsResult.toString()
            }
            if jsResult.isNumber {
                return jsResult.toNumber()
            }
            if jsResult.isBoolean {
                return jsResult.toBool()
            }
            if jsResult.isArray {
                return jsResult.toArray()
            }
            if jsResult.isObject {
                return jsResult.toDictionary()
            }
            return jsResult.toString()
        }
        return nil
    }
}
