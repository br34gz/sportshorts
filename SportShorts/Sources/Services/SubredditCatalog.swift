import Foundation

/// Fetches subreddits.json from the repo (24h cache, bundled fallback).
/// Symmetric to ChannelCatalog — same lifecycle so contributors can add
/// a subreddit via a one-line PR without a rebuild.
enum SubredditCatalogService {

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/br34gz/sportshorts/main/subreddits.json")!
    static let cacheTTL: TimeInterval = 60 * 60 * 24

    static func load(forceRefresh: Bool = false) async -> SubredditCatalog {
        if !forceRefresh,
           let cached = loadFromCache(),
           let mtime = cacheMtime(),
           Date().timeIntervalSince(mtime) < cacheTTL {
            return cached
        }
        if let remote = await fetchRemote() {
            saveToCache(remote)
            return remote
        }
        if let cached = loadFromCache() { return cached }
        return loadFromBundle() ?? .empty
    }

    private static func fetchRemote() async -> SubredditCatalog? {
        do {
            var req = URLRequest(url: remoteURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SubredditCatalog.self, from: data)
        } catch {
            return nil
        }
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SportShorts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("subreddits.json")
    }

    private static func loadFromCache() -> SubredditCatalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(SubredditCatalog.self, from: data)
    }

    private static func cacheMtime() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        return attrs?[.modificationDate] as? Date
    }

    private static func saveToCache(_ catalog: SubredditCatalog) {
        if let data = try? JSONEncoder().encode(catalog) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func loadFromBundle() -> SubredditCatalog? {
        guard let url = Bundle.main.url(forResource: "bundled_subreddits", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SubredditCatalog.self, from: data)
    }
}
