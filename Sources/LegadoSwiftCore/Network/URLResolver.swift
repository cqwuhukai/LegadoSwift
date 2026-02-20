import Foundation

/// Shared utility for resolving relative URLs to absolute URLs.
/// Replicates Android's NetworkUtils.getAbsoluteURL logic.
enum URLResolver {

    /// Resolve a relative URL to an absolute URL using a base URL.
    static func resolve(_ url: String, baseUrl: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return baseUrl }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        if trimmed.hasPrefix("/") {
            if let base = URL(string: baseUrl), let scheme = base.scheme, let host = base.host {
                let port = base.port.map { ":\($0)" } ?? ""
                return "\(scheme)://\(host)\(port)\(trimmed)"
            }
            return baseUrl + trimmed
        }
        // Relative path — resolve against base directory
        if let base = URL(string: baseUrl) {
            let baseDir = base.deletingLastPathComponent()
            return baseDir.appendingPathComponent(trimmed).absoluteString
        }
        return baseUrl + "/" + trimmed
    }
}
