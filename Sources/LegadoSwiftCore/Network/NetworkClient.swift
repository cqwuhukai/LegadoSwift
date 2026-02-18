import Foundation

// MARK: - Network Client

enum NetworkClient {

    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // MARK: - Fetch

    static func fetch(
        url: String,
        headers: [String: String]? = nil,
        timeout: TimeInterval = 15
    ) async throws -> (data: Data, response: URLResponse) {
        guard let requestURL = URL(string: url) else {
            throw LegadoError.invalidURL
        }

        var request = URLRequest(url: requestURL, timeoutInterval: timeout)
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        // Apply custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return try await URLSession.shared.data(for: request)
    }

    // MARK: - Fetch String

    static func fetchString(
        url: String,
        headers: [String: String]? = nil,
        encoding: String.Encoding = .utf8
    ) async throws -> String {
        let (data, _) = try await fetch(url: url, headers: headers)
        guard let text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .ascii) else {
            throw LegadoError.parseError("无法解码响应内容")
        }
        return text
    }

    // MARK: - Fetch String (POST)

    static func fetchStringPOST(
        url: String,
        body: String,
        headers: [String: String]? = nil,
        encoding: String.Encoding = .utf8
    ) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw LegadoError.invalidURL
        }

        var request = URLRequest(url: requestURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        // Determine content type
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        if trimmedBody.hasPrefix("{") || trimmedBody.hasPrefix("[") {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        // Apply custom headers (after defaults so they can override)
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .ascii) else {
            throw LegadoError.parseError("无法解码响应内容")
        }
        return text
    }

    // MARK: - Parse Headers from BookSource

    static func parseHeaders(from headerString: String?) -> [String: String]? {
        guard let headerString = headerString, !headerString.isEmpty else { return nil }

        // Try JSON format: {"User-Agent": "...", "Cookie": "..."}
        if let data = headerString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return dict
        }

        // Try line-by-line format: "Key: Value\nKey2: Value2"
        var headers: [String: String] = [:]
        for line in headerString.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ": ")
            if parts.count >= 2 {
                headers[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts.dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespaces)
            }
        }
        return headers.isEmpty ? nil : headers
    }
}
