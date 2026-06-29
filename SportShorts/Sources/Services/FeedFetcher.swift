import Foundation

enum FeedFetcher {

    /// Fetch + merge highlight videos for the user's followed competitions in their country.
    static func fetch(queries: [(sport: Sport, competition: Competition, channel: Channel)]) async throws -> [VideoItem] {
        guard !queries.isEmpty else { return [] }

        var merged: [VideoItem] = []
        await withTaskGroup(of: [VideoItem].self) { group in
            for q in queries {
                group.addTask { (try? await fetchOne(sport: q.sport, competition: q.competition, channel: q.channel)) ?? [] }
            }
            for await items in group { merged.append(contentsOf: items) }
        }

        var seen = Set<String>()
        let deduped = merged.filter { seen.insert($0.id).inserted }
        let filtered = deduped.filter { HighlightsFilter.isMatchHighlight(title: $0.title) }
        return filtered.sorted { $0.publishedAt > $1.publishedAt }
    }

    private static func fetchOne(sport: Sport, competition: Competition, channel: Channel) async throws -> [VideoItem] {
        var req = URLRequest(url: channel.feedURL)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        return try RSSParser.parse(data, sport: sport, competition: competition, channel: channel)
    }
}
