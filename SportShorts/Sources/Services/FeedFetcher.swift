import Foundation

enum FeedFetcher {

    /// Fetch every active channel's recent videos (RSS ∪ /videos page scrape),
    /// classify each, drop non-highlights, drop anything older than 7 days,
    /// dedupe. Returns the FULL classified set — the sport/competition filter
    /// is applied later in the view layer so the same fetched list powers
    /// both Highlights (filtered) and Browse (all sports).
    static func fetch(channels: [YouTubeChannel],
                      subreddits: [SubredditSource] = [],
                      redditEnabled: Bool = false,
                      catalog: Catalog,
                      allowSpoilers: Bool = false,
                      customBlocklist: [String] = [],
                      englishOnly: Bool = true) async throws -> [VideoItem] {
        // Even without YouTube channels we might still want the Reddit source
        // to contribute, so allow either side to be empty.
        let hasWork = !channels.isEmpty || (redditEnabled && !subreddits.isEmpty)
        guard hasWork else { return [] }

        let sportsById = Dictionary(uniqueKeysWithValues: catalog.sports.map { ($0.id, $0) })

        // YouTube channels — existing path.
        async let youtubeItems: [VideoItem] = {
            guard !channels.isEmpty else { return [] }
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
            return merged
        }()

        // Reddit subreddits — new path via RedditFetcher.
        async let redditItems: [VideoItem] = RedditFetcher.fetch(
            subreddits: subreddits,
            catalog: catalog,
            redditEnabled: redditEnabled,
            allowSpoilers: allowSpoilers,
            customBlocklist: customBlocklist,
            englishOnly: englishOnly
        )

        let allItems = await (youtubeItems + redditItems)

        // Dedupe rules 1+2 from the design doc: exact media identity + same
        // canonical URL. Fuzzy title dedup is deferred to a later iteration.
        var byId = [String: VideoItem]()
        var byCanonical = [String: VideoItem]()
        for item in allItems {
            // Rule: same VideoItem.id (should be rare — but harmless to check).
            if let existing = byId[item.id] {
                byId[item.id] = preferPrimary(existing, item)
                continue
            }
            // Rule: same canonical playable identity (YouTube video id, HLS URL, mp4 URL).
            let canon = canonicalKey(for: item.source)
            if let existing = byCanonical[canon] {
                let winner = preferPrimary(existing, item)
                byCanonical[canon] = winner
                byId[winner.id] = winner
                continue
            }
            byCanonical[canon] = item
            byId[item.id] = item
        }
        let deduped = Array(byId.values)

        // 7-day recency window.
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: Date()) ?? Date(timeIntervalSinceNow: -7 * 86_400)
        let recent = deduped.filter { $0.publishedAt >= cutoff }
        return recent.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Doc §6: broadcaster YouTube > any YouTube > v.redd.it > streamable > everything else.
    private static func preferPrimary(_ a: VideoItem, _ b: VideoItem) -> VideoItem {
        return preferenceScore(a) >= preferenceScore(b) ? a : b
    }

    private static func preferenceScore(_ item: VideoItem) -> Int {
        switch item.origin {
        case .youtubeChannel: return 100
        case .subreddit:
            switch item.source {
            case .youtube:    return 80    // Reddit-surfaced YouTube — still YouTube, less than a broadcaster
            case .hlsStream:  return 60    // v.redd.it native — respectable
            case .mp4Stream:  return 40    // imgur / raw mp4
            case .external:   return 20    // streamable / X / other — needs Safari
            }
        }
    }

    private static func canonicalKey(for source: PlayableSource) -> String {
        switch source {
        case .youtube(let id):        return "yt:\(id)"
        case .hlsStream(let url):     return "hls:\(url.absoluteString)"
        case .mp4Stream(let url):     return "mp4:\(url.absoluteString)"
        case .external(let url):      return "ext:\(url.absoluteString)"
        }
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
                competitionLabel: match.competition?.label,
                source: .youtube(videoId: entry.id),
                origin: .youtubeChannel(id: channel.channelId)
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
