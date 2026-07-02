import Foundation

enum FeedFetcher {

    /// Fetch every active channel's recent videos (RSS ∪ /videos page scrape),
    /// classify each, drop non-highlights, drop anything older than 7 days,
    /// dedupe. Returns the FULL classified set — the sport/competition filter
    /// is applied later in the view layer so the same fetched list powers
    /// both Highlights (filtered) and Browse (all sports).
    static func fetch(channels: [YouTubeChannel],
                      catalog: Catalog,
                      allowSpoilers: Bool = false,
                      customBlocklist: [String] = [],
                      englishOnly: Bool = true) async throws -> [VideoItem] {
        guard !channels.isEmpty else { return [] }

        let sportsById = Dictionary(uniqueKeysWithValues: catalog.sports.map { ($0.id, $0) })

        var merged: [VideoItem] = []
        await withTaskGroup(of: [VideoItem].self) { group in
            for channel in channels {
                group.addTask {
                    await fetchOne(
                        channel: channel,
                        catalog: catalog,
                        sportsById: sportsById,
                        allowSpoilers: allowSpoilers,
                        customBlocklist: customBlocklist,
                        englishOnly: englishOnly
                    )
                }
            }
            for await items in group { merged.append(contentsOf: items) }
        }

        var seen = Set<String>()
        let deduped = merged.filter { seen.insert($0.id).inserted }

        // 7-day recency window — the daily list shouldn't show ancient
        // highlights even if a channel's RSS/scrape still has them.
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: Date()) ?? Date(timeIntervalSinceNow: -7 * 86_400)
        let recent = deduped.filter { $0.publishedAt >= cutoff }

        return recent.sorted { $0.publishedAt > $1.publishedAt }
    }

    private static func fetchOne(channel: YouTubeChannel,
                                 catalog: Catalog,
                                 sportsById: [String: Sport],
                                 allowSpoilers: Bool,
                                 customBlocklist: [String],
                                 englishOnly: Bool) async -> [VideoItem] {
        // RSS + scrape in parallel, then merge by videoId.
        async let rss = fetchRSS(channel: channel)
        async let scraped = ChannelVideoScraper.scrape(channelId: channel.channelId, channelName: channel.name)
        let rssEntries = (try? await rss) ?? []
        let scrapedEntries = await scraped

        var byId: [String: RSSParser.Entry] = [:]
        for e in rssEntries { byId[e.id] = e }
        // Scraped wins on collision EXCEPT when scraped would clobber a
        // known view count with -1 — keep the RSS-sourced views in that case
        // so the premiere filter has the better signal.
        for e in scrapedEntries {
            if let existing = byId[e.id], existing.views >= 0, e.views < 0 {
                // Preserve RSS views, take scraped title/publishedAt if they're set.
                byId[e.id] = RSSParser.Entry(
                    id: e.id,
                    title: e.title.isEmpty ? existing.title : e.title,
                    channelTitle: e.channelTitle.isEmpty ? existing.channelTitle : e.channelTitle,
                    publishedAt: e.publishedAt > existing.publishedAt ? e.publishedAt : existing.publishedAt,
                    thumbnailURL: e.thumbnailURL ?? existing.thumbnailURL,
                    views: existing.views
                )
            } else {
                byId[e.id] = e
            }
        }

        return byId.values.compactMap { entry -> VideoItem? in
            // Drop premiere stubs / upcoming videos — views==0 is the giveaway.
            // -1 means "unknown" (scraper without a parsed view count) → keep.
            if entry.views == 0 { return nil }
            guard HighlightsFilter.isMatchHighlight(
                title: entry.title,
                allowSpoilers: allowSpoilers,
                customBlocklist: customBlocklist,
                englishOnly: englishOnly
            ) else { return nil }
            guard let match = SportClassifier.classify(title: entry.title, channel: channel, catalog: catalog),
                  let sport = sportsById[match.sport.id] else { return nil }
            return VideoItem(
                id: entry.id,
                title: entry.title,
                channelTitle: entry.channelTitle.isEmpty ? channel.name : entry.channelTitle,
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

    private static func fetchRSS(channel: YouTubeChannel) async throws -> [RSSParser.Entry] {
        var req = URLRequest(url: channel.feedURL)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        return try RSSParser.parse(data, channel: channel)
    }
}
