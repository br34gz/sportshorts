import Foundation

enum FeedFetcher {

    /// Fetch RSS for every channel in `channels`, parse to raw videos, then
    /// pass each through:
    ///   1. HighlightsFilter — drop anything that isn't a real match highlight
    ///   2. SportClassifier — assign a sport (+ optional competition)
    ///   3. Keep only sports the user follows
    /// Final list is sorted by recency.
    static func fetch(channels: [YouTubeChannel],
                      followedSports: Set<String>,
                      catalog: Catalog) async throws -> [VideoItem] {
        guard !channels.isEmpty else { return [] }

        // Index sports for quick label lookup post-classification.
        let sportsById = Dictionary(uniqueKeysWithValues: catalog.sports.map { ($0.id, $0) })

        var merged: [VideoItem] = []
        await withTaskGroup(of: [VideoItem].self) { group in
            for channel in channels {
                group.addTask {
                    (try? await fetchOne(channel: channel, catalog: catalog, sportsById: sportsById)) ?? []
                }
            }
            for await items in group { merged.append(contentsOf: items) }
        }

        var seen = Set<String>()
        let deduped = merged.filter { seen.insert($0.id).inserted }
        let inSport = deduped.filter { followedSports.contains($0.sportId) }
        return inSport.sorted { $0.publishedAt > $1.publishedAt }
    }

    private static func fetchOne(channel: YouTubeChannel,
                                 catalog: Catalog,
                                 sportsById: [String: Sport]) async throws -> [YouTubeVideo] {
        var req = URLRequest(url: channel.feedURL)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        let raw = try RSSParser.parse(data, channel: channel)

        return raw.compactMap { entry -> YouTubeVideo? in
            guard HighlightsFilter.isMatchHighlight(title: entry.title) else { return nil }
            guard let match = SportClassifier.classify(title: entry.title, channel: channel, catalog: catalog),
                  let sport = sportsById[match.sport.id] else { return nil }
            return YouTubeVideo(
                id: entry.id,
                title: entry.title,
                channelTitle: entry.channelTitle,
                channelId: channel.channelId,
                publishedAt: entry.publishedAt,
                thumbnailURL: entry.thumbnailURL,
                sportId: sport.id,
                sportLabel: sport.label,
                sportIcon: sport.icon,
                competitionId: match.competition?.id,
                competitionLabel: match.competition?.label
            )
        }
    }
}

/// Shorthand — the `VideoItem` type is the same shape, but using a typealias
/// here keeps the fetcher's per-stage transformations easy to read.
typealias YouTubeVideo = VideoItem
