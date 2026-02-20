import Foundation

@Observable
public class BookSourceManager {
    public var sources: [BookSource] = []
    public var searchText: String = ""
    public var selectedGroup: String?

    private static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegadoSwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("book_sources.json")
    }()

    public init() {
        loadSources()
    }

    // MARK: - Import

    @discardableResult
    public func importFromJSON(_ jsonString: String) throws -> Int {
        guard let data = jsonString.data(using: .utf8) else {
            throw LegadoError.invalidJSON
        }
        return try importFromData(data)
    }

    public func importFromURL(_ urlString: String) async throws -> Int {
        guard let url = URL(string: urlString) else {
            throw LegadoError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try importFromData(data)
    }

    public func importFromFile(_ fileURL: URL) throws -> Int {
        let data = try Data(contentsOf: fileURL)
        return try importFromData(data)
    }

    private func importFromData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        var newSources: [BookSource] = []

        // Try decoding as array first
        if let arr = try? decoder.decode([BookSource].self, from: data) {
            newSources = arr
        } else if let single = try? decoder.decode(BookSource.self, from: data) {
            newSources = [single]
        } else {
            // Fallback: try to parse as JSON array and decode each element individually
            // This prevents one malformed source from crashing the entire import
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var successCount = 0
                var failCount = 0
                for item in jsonArray {
                    do {
                        let itemData = try JSONSerialization.data(withJSONObject: item)
                        let source = try decoder.decode(BookSource.self, from: itemData)
                        newSources.append(source)
                        successCount += 1
                    } catch {
                        failCount += 1
                        let name = item["bookSourceName"] as? String ?? "unknown"
                        print("[Import] ⚠️ Failed to decode source '\(name)': \(error.localizedDescription)")
                    }
                }
                if newSources.isEmpty {
                    throw LegadoError.decodeFailed
                }
                print("[Import] 📖 Decoded \(successCount) sources, \(failCount) failed")
            } else if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Single object that failed standard decoding — try re-serializing
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonObj)
                    let source = try decoder.decode(BookSource.self, from: itemData)
                    newSources = [source]
                } catch {
                    throw LegadoError.decodeFailed
                }
            } else {
                throw LegadoError.decodeFailed
            }
        }

        // Filter out sources with empty bookSourceUrl (invalid data)
        newSources = newSources.filter { !$0.bookSourceUrl.isEmpty }

        guard !newSources.isEmpty else {
            throw LegadoError.decodeFailed
        }

        for source in newSources {
            if let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
                sources[idx] = source
            } else {
                sources.append(source)
            }
        }

        saveSources()
        return newSources.count
    }

    // MARK: - Management

    public func removeSource(_ source: BookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        saveSources()
    }

    public func removeSources(_ ids: Set<String>) {
        sources.removeAll { ids.contains($0.bookSourceUrl) }
        saveSources()
    }

    public func toggleSource(_ source: BookSource) {
        if let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
            sources[idx].enabled.toggle()
            saveSources()
        }
    }

    public var enabledSources: [BookSource] {
        sources.filter { $0.enabled }
    }

    public var groups: [String] {
        let allGroups = sources.flatMap { $0.groups }
        return Array(Set(allGroups)).sorted()
    }

    public var filteredSources: [BookSource] {
        var result = sources
        if let group = selectedGroup {
            result = result.filter { $0.groups.contains(group) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.bookSourceName.localizedCaseInsensitiveContains(searchText)
                    || $0.bookSourceUrl.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.customOrder < $1.customOrder }
    }

    // MARK: - Export

    public func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sources) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Persistence

    public func saveSources() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(sources) else { return }
        try? data.write(to: Self.saveURL)
    }

    public func loadSources() {
        guard let data = try? Data(contentsOf: Self.saveURL),
              let loaded = try? JSONDecoder().decode([BookSource].self, from: data)
        else { return }
        sources = loaded
    }
}

// MARK: - Errors

public enum LegadoError: LocalizedError {
    case invalidJSON
    case invalidURL
    case decodeFailed
    case fileNotFound
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "无效的 JSON 格式"
        case .invalidURL: return "无效的 URL"
        case .decodeFailed: return "解析书源数据失败"
        case .fileNotFound: return "文件未找到"
        case .parseError(let msg): return "解析错误: \(msg)"
        }
    }
}
