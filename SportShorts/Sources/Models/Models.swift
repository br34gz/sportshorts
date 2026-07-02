import Foundation

// MARK: - Country

struct Country: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }

    static let supported: [Country] = [
        Country(code: "AU", name: "Australia", flag: "🇦🇺"),
        Country(code: "UK", name: "United Kingdom", flag: "🇬🇧"),
        Country(code: "US", name: "United States", flag: "🇺🇸"),
        Country(code: "IE", name: "Ireland", flag: "🇮🇪"),
        Country(code: "NZ", name: "New Zealand", flag: "🇳🇿"),
        Country(code: "ZA", name: "South Africa", flag: "🇿🇦"),
    ]
}

// MARK: - YouTubeChannel

/// A YouTube channel that posts sports content. Channels are pooled by country
/// (broadcasters/free-to-air operators serving that country) and globally
/// (league/sport-official channels not tied to a region). The user's selected
/// sports filter the feed *after* fetching all channels — channels themselves
/// are sport-agnostic at the catalog level.
struct YouTubeChannel: Identifiable, Hashable, Codable {
    let channelId: String
    let name: String
    /// YouTube @handle without the @. e.g. "BBCSport" → displayed as "@BBCSport".
    let handle: String?
    let note: String?
    /// Optional sport-id list — used as a prior by SportClassifier when titles
    /// are ambiguous. e.g. "Sky Sports Football" → ["soccer"]; "BBC Sport" → [].
    let sportHints: [String]
    /// True only for channels the user added via Settings.
    let userAdded: Bool

    var id: String { channelId }

    var feedURL: URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)")!
    }

    /// "@handle" if we have one, otherwise nil.
    var displayHandle: String? {
        guard let h = handle, !h.isEmpty else { return nil }
        return h.hasPrefix("@") ? h : "@\(h)"
    }

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case name, handle, note
        case sportHints = "sport_hints"
        case userAdded = "user_added"
    }

    init(channelId: String, name: String, handle: String? = nil, note: String? = nil, sportHints: [String] = [], userAdded: Bool = false) {
        self.channelId = channelId
        self.name = name
        self.handle = handle
        self.note = note
        self.sportHints = sportHints
        self.userAdded = userAdded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.channelId = try c.decode(String.self, forKey: .channelId)
        self.name = try c.decode(String.self, forKey: .name)
        self.handle = try c.decodeIfPresent(String.self, forKey: .handle)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.sportHints = (try? c.decode([String].self, forKey: .sportHints)) ?? []
        self.userAdded = (try? c.decode(Bool.self, forKey: .userAdded)) ?? false
    }
}

// MARK: - Sport (with classifier keywords + competitions for stats lookup)

struct Sport: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let icon: String
    /// Keywords used by SportClassifier to assign a video title to this sport
    /// when no channel sport-hint resolves it. Lowercase substrings.
    let keywords: [String]
    /// Competition metadata — used to detect specific competitions in titles
    /// (for MatchStatsService lookup) and to label videos in the feed.
    let competitions: [CompetitionMeta]
}

struct CompetitionMeta: Identifiable, Hashable, Codable {
    let id: String           // "epl", "ucl", "nba"
    let label: String        // "Premier League"
    let group: String?       // e.g. "England", "Spain", "Europe" (soccer only)
    let keywords: [String]   // ["premier league", "epl"]

    init(id: String, label: String, group: String? = nil, keywords: [String]) {
        self.id = id; self.label = label; self.group = group; self.keywords = keywords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.label = try c.decode(String.self, forKey: .label)
        self.group = try c.decodeIfPresent(String.self, forKey: .group)
        self.keywords = (try? c.decode([String].self, forKey: .keywords)) ?? []
    }

    enum CodingKeys: String, CodingKey { case id, label, group, keywords }
}

// MARK: - Catalog (channels.json shape)

struct Catalog: Codable {
    let countries: [String: [YouTubeChannel]]
    let globalChannels: [YouTubeChannel]
    let sports: [Sport]

    enum CodingKeys: String, CodingKey {
        case countries
        case globalChannels = "global_channels"
        case sports
    }

    static let empty = Catalog(countries: [:], globalChannels: [], sports: [])
}

// MARK: - Video

// MARK: - Subreddit source (Reddit as a channel type)

/// A subreddit followed by the user as a highlights source. Behaviourally
/// equivalent to a YouTubeChannel — a named source that emits timestamped
/// video items — routed via the RedditGateway instead of RSS.
struct SubredditSource: Identifiable, Hashable, Codable {
    /// Sub name without the leading `r/` (e.g. "soccer", "NRL", "AFL").
    let name: String
    /// Optional per-sub upvote floor. Posts with `score < min_score` are dropped.
    let minScore: Int?
    /// Sport hints — same semantics as YouTubeChannel.sportHints. Empty = infer via classifier.
    let sportHints: [String]
    /// Reddit `link_flair_text` allow-list. Empty = accept any flair.
    let flairAllowlist: [String]?
    /// True only for subs the user added via Settings.
    let userAdded: Bool

    var id: String { name.lowercased() }
    var displayName: String { "r/\(name)" }

    enum CodingKeys: String, CodingKey {
        case name
        case minScore = "min_score"
        case sportHints = "sport_hints"
        case flairAllowlist = "flair_allowlist"
        case userAdded = "user_added"
    }

    init(name: String, minScore: Int? = nil, sportHints: [String] = [], flairAllowlist: [String]? = nil, userAdded: Bool = false) {
        self.name = name
        self.minScore = minScore
        self.sportHints = sportHints
        self.flairAllowlist = flairAllowlist
        self.userAdded = userAdded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.minScore = try c.decodeIfPresent(Int.self, forKey: .minScore)
        self.sportHints = (try? c.decode([String].self, forKey: .sportHints)) ?? []
        self.flairAllowlist = try c.decodeIfPresent([String].self, forKey: .flairAllowlist)
        self.userAdded = (try? c.decode(Bool.self, forKey: .userAdded)) ?? false
    }
}

/// Top-level shape of `subreddits.json`. Ships a curated seed catalog + a
/// kill switch (`enabled`) that lets us globally disable Reddit fetching
/// with one catalog push.
struct SubredditCatalog: Codable {
    let enabled: Bool
    let subreddits: [SubredditSource]

    enum CodingKeys: String, CodingKey { case enabled, subreddits }

    static let empty = SubredditCatalog(enabled: true, subreddits: [])

    init(enabled: Bool = true, subreddits: [SubredditSource] = []) {
        self.enabled = enabled
        self.subreddits = subreddits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        self.subreddits = (try? c.decode([SubredditSource].self, forKey: .subreddits)) ?? []
    }
}

// MARK: - Video item

/// The playable-source shape carried on VideoItem. Determines which player
/// the PlayerSheet routes to.
enum PlayableSource: Hashable, Codable {
    case youtube(videoId: String)
    case hlsStream(url: URL)
    case mp4Stream(url: URL)
    /// Terminal fallback — open in Safari at play time.
    case external(url: URL)
}

/// What produced this VideoItem — used by VideoCard for the source label.
enum SourceOrigin: Hashable, Codable {
    case youtubeChannel(id: String)
    case subreddit(name: String)
}

struct VideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let channelTitle: String
    let channelId: String
    let publishedAt: Date
    let thumbnailURL: URL?
    let sportId: String
    let sportLabel: String
    let sportIcon: String
    /// Competition surfaced if the classifier matched one in the title.
    let competitionId: String?
    let competitionLabel: String?

    /// Playable asset — YouTube video id, HLS/mp4 stream URL, or external
    /// fallback. Defaults to `.youtube(id: self.id)` for legacy call sites.
    var source: PlayableSource = .youtube(videoId: "")
    /// Where this item came from — YouTube channel or subreddit.
    var origin: SourceOrigin = .youtubeChannel(id: "")
    /// Reddit upvotes when origin == .subreddit — surfaced in the card label.
    var redditScore: Int?
    /// Direct link back to the source (permalink for Reddit, watch URL for YouTube).
    var permalink: URL?

    var watchURL: URL {
        if let permalink { return permalink }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }

    init(
        id: String,
        title: String,
        channelTitle: String,
        channelId: String,
        publishedAt: Date,
        thumbnailURL: URL?,
        sportId: String,
        sportLabel: String,
        sportIcon: String,
        competitionId: String?,
        competitionLabel: String?,
        source: PlayableSource? = nil,
        origin: SourceOrigin? = nil,
        redditScore: Int? = nil,
        permalink: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.channelTitle = channelTitle
        self.channelId = channelId
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.sportId = sportId
        self.sportLabel = sportLabel
        self.sportIcon = sportIcon
        self.competitionId = competitionId
        self.competitionLabel = competitionLabel
        self.source = source ?? .youtube(videoId: id)
        self.origin = origin ?? .youtubeChannel(id: channelId)
        self.redditScore = redditScore
        self.permalink = permalink
    }
}
