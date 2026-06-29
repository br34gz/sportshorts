import Foundation

enum FeedFetcher {

    /// Fetch + merge videos from a list of channels. Concurrent per-channel.
    static func fetch(channels: [ChannelEntry]) async throws -> [VideoItem] {
        guard !channels.isEmpty else { return [] }

        var merged: [VideoItem] = []
        await withTaskGroup(of: [VideoItem].self) { group in
            for channel in channels {
                group.addTask { (try? await fetchChannel(channel)) ?? [] }
            }
            for await items in group {
                merged.append(contentsOf: items)
            }
        }

        // Deduplicate by video ID, filter to match-highlight titles, then sort newest-first.
        var seen = Set<String>()
        let deduped = merged.filter { seen.insert($0.id).inserted }
        let filtered = deduped.filter { HighlightsFilter.isMatchHighlight(title: $0.title) }
        return filtered.sorted { $0.publishedAt > $1.publishedAt }
    }

    private static func fetchChannel(_ channel: ChannelEntry) async throws -> [VideoItem] {
        var req = URLRequest(url: channel.feedURL)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        return try RSSParser.parse(data, for: channel)
    }
}
