import Foundation

/// Loads the sport-centric channel catalog from (in priority order):
/// 1. Remote: raw.githubusercontent.com/sb86-dev/sportshorts/main/channels.json
///    (Only works if the repo is public; private repos 404 anonymous fetches.)
/// 2. Local on-disk cache (~24h TTL).
/// 3. Bundled fallback shipped with the app.
enum ChannelCatalog {

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/sb86-dev/sportshorts/main/channels.json")!
    static let cacheTTL: TimeInterval = 60 * 60 * 24

    static func load(forceRefresh: Bool = false) async -> Catalog {
        if !forceRefresh,
           let cached = loadFromCache(),
           !isEmpty(cached),
           let mtime = cacheMtime(),
           Date().timeIntervalSince(mtime) < cacheTTL {
            return cached
        }
        if let remote = await fetchRemote() {
            saveToCache(remote)
            return remote
        }
        if let cached = loadFromCache(), !isEmpty(cached) {
            return cached
        }
        return loadFromBundle() ?? Catalog(sports: [])
    }

    private static func isEmpty(_ catalog: Catalog) -> Bool {
        catalog.sports.allSatisfy { $0.competitions.isEmpty }
    }

    private static func fetchRemote() async -> Catalog? {
        do {
            var req = URLRequest(url: remoteURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Catalog.self, from: data)
        } catch {
            return nil
        }
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SportShorts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("catalog.json")
    }

    private static func loadFromCache() -> Catalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }

    private static func cacheMtime() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        return attrs?[.modificationDate] as? Date
    }

    private static func saveToCache(_ catalog: Catalog) {
        if let data = try? JSONEncoder().encode(catalog) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func loadFromBundle() -> Catalog? {
        guard let url = Bundle.main.url(forResource: "bundled_channels", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }
}
