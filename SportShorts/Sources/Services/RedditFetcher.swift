import Foundation

/// Fetches recent posts from a subreddit, extracts video assets, and
/// converts them to VideoItem entries the feed can render.
///
/// Follows the doc's Phase 1 scope:
/// - `hot.json?limit=50` per subreddit
/// - extract v.redd.it (HLS), YouTube (native player), streamable (external),
///   twitter/x (external)
/// - lazy resolution: no per-post network at fetch time; resolvers run at play
/// - no comment mining in v1
enum RedditFetcher {

    /// Fetch every subreddit in `subs`, classify, dedupe, return VideoItems.
    /// `redditEnabled` mirrors the catalog kill switch (`subreddits.json.enabled`).
    /// `credentials.isConfigured` gates the whole path — no valid OAuth
    /// credentials means no Reddit traffic.
    static func fetch(subreddits subs: [SubredditSource],
                      catalog: Catalog,
                      redditEnabled: Bool,
                      credentials: RedditCredentials,
                      allowSpoilers: Bool,
                      customBlocklist: [String],
                      englishOnly: Bool) async -> [VideoItem] {
        guard redditEnabled, credentials.isConfigured, !subs.isEmpty else { return [] }
        let sportsById = Dictionary(uniqueKeysWithValues: catalog.sports.map { ($0.id, $0) })

        var merged: [VideoItem] = []
        await withTaskGroup(of: [VideoItem].self) { group in
            for sub in subs {
                group.addTask {
                    await fetchOne(
                        sub: sub,
                        catalog: catalog,
                        sportsById: sportsById,
                        credentials: credentials,
                        allowSpoilers: allowSpoilers,
                        customBlocklist: customBlocklist,
                        englishOnly: englishOnly
                    )
                }
            }
            for await items in group { merged.append(contentsOf: items) }
        }
        return merged
    }

    private static func fetchOne(sub: SubredditSource,
                                 catalog: Catalog,
                                 sportsById: [String: Sport],
                                 credentials: RedditCredentials,
                                 allowSpoilers: Bool,
                                 customBlocklist: [String],
                                 englishOnly: Bool) async -> [VideoItem] {
        // hot sort surfaces breaking highlights fastest — per the doc.
        // Path only (no www./oauth.reddit.com prefix); RedditGateway routes
        // it to oauth.reddit.com with the bearer token attached.
        do {
            let root = try await RedditGateway.shared.fetch(path: "/r/\(sub.name)/hot?limit=50", credentials: credentials)
            guard let data = root["data"] as? [String: Any],
                  let children = data["children"] as? [[String: Any]] else { return [] }

            var out: [VideoItem] = []
            for child in children {
                guard let post = child["data"] as? [String: Any] else { continue }
                guard let item = itemFromPost(post, sub: sub, catalog: catalog, sportsById: sportsById,
                                              allowSpoilers: allowSpoilers,
                                              customBlocklist: customBlocklist,
                                              englishOnly: englishOnly) else { continue }
                out.append(item)
            }
            return out
        } catch {
            return []
        }
    }

    // MARK: - Post → VideoItem

    private static func itemFromPost(_ post: [String: Any],
                                     sub: SubredditSource,
                                     catalog: Catalog,
                                     sportsById: [String: Sport],
                                     allowSpoilers: Bool,
                                     customBlocklist: [String],
                                     englishOnly: Bool) -> VideoItem? {
        // Bail on stickied / self / removed posts.
        if (post["stickied"] as? Bool) == true { return nil }
        if (post["is_self"] as? Bool) == true { return nil }
        if (post["removed_by_category"] as? String) != nil { return nil }

        // Score gate.
        let score = (post["score"] as? Int) ?? 0
        if let floor = sub.minScore, score < floor { return nil }

        // Flair gate.
        if let allow = sub.flairAllowlist, !allow.isEmpty {
            let flair = (post["link_flair_text"] as? String) ?? ""
            let ok = allow.contains { flair.localizedCaseInsensitiveContains($0) }
            if !ok { return nil }
        }

        // Extract the primary playable asset. If nothing extractable, skip.
        guard let (playable, thumbnailURL) = extractAsset(post) else { return nil }

        let title = (post["title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }

        // Apply the standard title filter — treat Reddit titles as spoiler-bearing
        // per the doc's guidance by forcing allowSpoilers=false regardless of the
        // user's toggle. (Nuance the doc suggests: the eye toggle should still work,
        // so honour the user's choice.)
        guard HighlightsFilter.isMatchHighlight(
            title: title,
            allowSpoilers: allowSpoilers,
            customBlocklist: customBlocklist,
            englishOnly: englishOnly,
            relaxedForReddit: true
        ) else { return nil }

        let publishedAt = Date(timeIntervalSince1970: (post["created_utc"] as? Double) ?? 0)
        let permalinkPath = (post["permalink"] as? String) ?? ""
        let permalink = URL(string: "https://www.reddit.com" + permalinkPath)

        // Classify sport — use sub.sportHints as a strong prior; fall back to keyword classifier.
        let stubChannel = YouTubeChannel(channelId: "reddit-\(sub.id)", name: sub.displayName, sportHints: sub.sportHints)
        guard let match = SportClassifier.classify(title: title, channel: stubChannel, catalog: catalog),
              let sport = sportsById[match.sport.id] else { return nil }

        let postId = (post["id"] as? String) ?? UUID().uuidString

        return VideoItem(
            id: "reddit_\(postId)",
            title: title,
            channelTitle: sub.displayName,
            channelId: "reddit-\(sub.id)",
            publishedAt: publishedAt,
            thumbnailURL: thumbnailURL,
            sportId: sport.id,
            sportLabel: sport.label,
            sportIcon: sport.icon,
            competitionId: match.competition?.id,
            competitionLabel: match.competition?.label,
            source: playable,
            origin: .subreddit(name: sub.name),
            redditScore: score,
            permalink: permalink
        )
    }

    /// Extract the primary playable asset from a Reddit post. Returns nil if
    /// nothing plays back cleanly.
    ///
    /// Order per the doc:
    /// 1. secure_media.reddit_video (v.redd.it native)
    /// 2. crosspost_parent_list[0] — recurse once for crossposts
    /// 3. url_overridden_by_dest — external hosts
    static func extractAsset(_ post: [String: Any]) -> (PlayableSource, URL?)? {
        // Thumbnail — Reddit has a `thumbnail` field but it's often "self" / "default".
        // Prefer `preview.images[0].source.url` (HTML-entity-encoded, needs decode).
        let thumb: URL? = {
            if let preview = post["preview"] as? [String: Any],
               let images = preview["images"] as? [[String: Any]],
               let first = images.first,
               let source = first["source"] as? [String: Any],
               let urlStr = source["url"] as? String {
                let cleaned = urlStr.replacingOccurrences(of: "&amp;", with: "&")
                return URL(string: cleaned)
            }
            if let t = post["thumbnail"] as? String,
               t.hasPrefix("http") {
                return URL(string: t)
            }
            return nil
        }()

        // 1. Native v.redd.it via secure_media.reddit_video
        if let media = post["secure_media"] as? [String: Any],
           let rv = media["reddit_video"] as? [String: Any],
           let hlsStr = rv["hls_url"] as? String,
           let hls = URL(string: hlsStr) {
            return (.hlsStream(url: hls), thumb)
        }
        if let media = post["media"] as? [String: Any],
           let rv = media["reddit_video"] as? [String: Any],
           let hlsStr = rv["hls_url"] as? String,
           let hls = URL(string: hlsStr) {
            return (.hlsStream(url: hls), thumb)
        }

        // 2. Crosspost — recurse once
        if let crossposts = post["crosspost_parent_list"] as? [[String: Any]],
           let parent = crossposts.first {
            if let asset = extractAsset(parent) { return asset }
        }

        // 3. External URL
        let urlStr = (post["url_overridden_by_dest"] as? String) ?? (post["url"] as? String) ?? ""
        guard let url = URL(string: urlStr) else { return nil }
        let host = url.host?.lowercased() ?? ""

        if host.contains("youtube.com") || host.contains("youtu.be") {
            if let vid = youtubeVideoId(from: url) {
                return (.youtube(videoId: vid), thumb)
            }
            return (.external(url: url), thumb)
        }
        if host.contains("streamable.com") {
            // Streamable resolution happens at play time in a later iteration;
            // for v1 open externally so the user can still watch.
            return (.external(url: url), thumb)
        }
        if host == "v.redd.it" {
            // Fallback path if secure_media wasn't populated — v.redd.it URLs
            // are typically HLS-served at `<base>/HLSPlaylist.m3u8`.
            let hlsFallback = url.appendingPathComponent("HLSPlaylist.m3u8")
            return (.hlsStream(url: hlsFallback), thumb)
        }
        if host.contains("x.com") || host.contains("twitter.com") {
            return (.external(url: url), thumb)
        }
        if host.contains("i.imgur.com") && urlStr.hasSuffix(".gifv") {
            // Imgur .gifv → .mp4
            let mp4 = urlStr.replacingOccurrences(of: ".gifv", with: ".mp4")
            if let m = URL(string: mp4) { return (.mp4Stream(url: m), thumb) }
        }

        // Nothing recognisable → skip.
        return nil
    }

    private static func youtubeVideoId(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("youtu.be") {
            let p = url.path
            let id = String(p.dropFirst()) // remove leading /
            return id.isEmpty ? nil : id
        }
        if host.contains("youtube.com") {
            if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let v = comp.queryItems?.first(where: { $0.name == "v" })?.value {
                    return v
                }
                // /shorts/<id> or /embed/<id>
                let parts = comp.path.split(separator: "/").map(String.init)
                if parts.count >= 2, (parts[0] == "shorts" || parts[0] == "embed") {
                    return parts[1]
                }
            }
        }
        return nil
    }
}
