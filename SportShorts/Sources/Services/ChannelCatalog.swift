import Foundation

/// Loads the channel catalog from (in priority order):
/// 1. Remote: raw.githubusercontent.com/sb86-dev/sportshorts/main/channels.json
/// 2. Local on-disk cache (Library/Caches/SportShorts/channels.json), if remote fetch fails or for fast first paint
/// 3. Bundled fallback shipped with the app
enum ChannelCatalog {

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/sb86-dev/sportshorts/main/channels.json")!

    static let cacheTTL: TimeInterval = 60 * 60 * 24    // 24h

    static func load(forceRefresh: Bool = false) async -> ChannelCatalogPayload {
        // Try cache-first paint for snappy launch — but only if the cached
        // payload is non-empty. An empty cache (e.g. from an earlier build
        // that shipped before channels.json was populated) must not satisfy
        // the cache check, otherwise we'd serve nothing until TTL expires.
        if !forceRefresh,
           let cached = loadFromCache(),
           !isEmpty(cached),
           let mtime = cacheMtime(),
           Date().timeIntervalSince(mtime) < cacheTTL {
            return cached
        }

        // Try remote.
        if let remote = await fetchRemote() {
            saveToCache(remote)
            return remote
        }

        // Stale-but-non-empty cache better than nothing.
        if let cached = loadFromCache(), !isEmpty(cached) {
            return cached
        }

        // Bundle fallback.
        return loadFromBundle() ?? [:]
    }

    /// A catalog is "empty" if every country's channel list is empty.
    private static func isEmpty(_ payload: ChannelCatalogPayload) -> Bool {
        payload.values.allSatisfy { $0.isEmpty }
    }

    private static func fetchRemote() async -> ChannelCatalogPayload? {
        do {
            var req = URLRequest(url: remoteURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ChannelCatalogPayload.self, from: data)
            return decoded
        } catch {
            return nil
        }
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SportShorts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("channels.json")
    }

    private static func loadFromCache() -> ChannelCatalogPayload? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(ChannelCatalogPayload.self, from: data)
    }

    private static func cacheMtime() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        return attrs?[.modificationDate] as? Date
    }

    private static func saveToCache(_ payload: ChannelCatalogPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func loadFromBundle() -> ChannelCatalogPayload? {
        guard let url = Bundle.main.url(forResource: "bundled_channels", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(ChannelCatalogPayload.self, from: data)
    }
}
