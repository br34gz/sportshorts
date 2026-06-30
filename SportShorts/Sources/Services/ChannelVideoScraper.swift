import Foundation

/// Scrapes a channel's /videos page to supplement the RSS feed. YouTube's RSS
/// is hard-capped at the 15 most recent uploads — high-volume channels (SBS,
/// FIFA, etc.) push genuine highlight videos out of that window within hours.
/// The /videos page returns ~30 entries with the same shape, parsed out of
/// the `ytInitialData` JSON block.
///
/// FeedFetcher unions the scraper's entries with the RSS entries by videoId,
/// so if scraping fails the RSS still flows.
enum ChannelVideoScraper {

    static func scrape(channelId: String, channelName: String) async -> [RSSParser.Entry] {
        let url = URL(string: "https://www.youtube.com/channel/\(channelId)/videos")!
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 12

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return parse(html: html, channelName: channelName)
    }

    // MARK: - Parsing

    private static func parse(html: String, channelName: String) -> [RSSParser.Entry] {
        guard let jsonStr = extractInitialData(html) else { return [] }
        guard let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let tabs = (((root["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]]) else { return [] }

        for tab in tabs {
            guard let renderer = tab["tabRenderer"] as? [String: Any] else { continue }
            // Match by title OR by tabIdentifier — the videos tab is the one we want.
            let title = (renderer["title"] as? String) ?? ""
            let isVideos = title.lowercased() == "videos"
            if !isVideos { continue }
            let items = ((renderer["content"] as? [String: Any])?["richGridRenderer"] as? [String: Any])?["contents"] as? [[String: Any]] ?? []
            return items.compactMap { parseLockupItem($0, channelName: channelName) }
        }
        return []
    }

    private static func parseLockupItem(_ item: [String: Any], channelName: String) -> RSSParser.Entry? {
        let content = (item["richItemRenderer"] as? [String: Any])?["content"] as? [String: Any]
        let lockup = content?["lockupViewModel"] as? [String: Any]
        guard let lockup, let videoId = lockup["contentId"] as? String, videoId.count == 11 else {
            return nil
        }
        let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        let title = (metadata?["title"] as? [String: Any])?["content"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        var publishedAgo: String?
        if let rows = (((metadata?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]]) {
            outer: for row in rows {
                let parts = row["metadataParts"] as? [[String: Any]] ?? []
                for p in parts {
                    if let t = (p["text"] as? [String: Any])?["content"] as? String,
                       t.contains("ago") {
                        publishedAgo = t
                        break outer
                    }
                }
            }
        }

        return RSSParser.Entry(
            id: videoId,
            title: title,
            channelTitle: channelName,
            publishedAt: parseRelativeDate(publishedAgo),
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
        )
    }

    /// Extract the JSON object that follows `var ytInitialData = ` and ends at
    /// the matching `};</script>` — we can't use a lazy regex here because the
    /// object spans hundreds of kilobytes; instead, find the start, then walk
    /// forwards counting braces until balanced.
    private static func extractInitialData(_ html: String) -> String? {
        guard let startRange = html.range(of: "var ytInitialData = ") else { return nil }
        let after = html.index(startRange.upperBound, offsetBy: 0)
        let chars = html[after...]

        var depth = 0
        var inString = false
        var escaped = false
        var endIndex: String.Index?
        for i in chars.indices {
            let c = chars[i]
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if inString { continue }
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = html.index(after: i)
                    break
                }
            }
        }
        guard let end = endIndex else { return nil }
        return String(html[after..<end])
    }

    /// "1 hour ago", "6 hours ago", "2 days ago", "1 week ago", etc.
    private static func parseRelativeDate(_ s: String?) -> Date {
        guard let s, !s.isEmpty else { return Date() }
        let parts = s.lowercased().split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return Date() }
        let value = Int(parts[0]) ?? 1
        let unit = parts[1]
        let cal = Calendar(identifier: .gregorian)
        let component: Calendar.Component?
        switch true {
        case unit.contains("second"):  component = .second
        case unit.contains("minute"):  component = .minute
        case unit.contains("hour"):    component = .hour
        case unit.contains("day"):     component = .day
        case unit.contains("week"):    component = .weekOfYear
        case unit.contains("month"):   component = .month
        case unit.contains("year"):    component = .year
        default:                       component = nil
        }
        guard let component else { return Date() }
        return cal.date(byAdding: component, value: -value, to: Date()) ?? Date()
    }
}
