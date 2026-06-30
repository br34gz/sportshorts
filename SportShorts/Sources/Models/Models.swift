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
    let id: String          // "epl", "ucl", "nba"
    let label: String       // "Premier League"
    let keywords: [String]  // ["premier league", "epl"]
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

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
}
