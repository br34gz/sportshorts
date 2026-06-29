import Foundation

// MARK: - Country

struct Country: Identifiable, Hashable, Codable {
    let code: String        // ISO-2 like "AU", "UK"
    let name: String        // "Australia"
    let flag: String        // emoji flag

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

// MARK: - Sport / Competition / Channel

struct ChannelEntry: Identifiable, Hashable, Codable {
    let sport: String           // e.g. "Rugby League"
    let competition: String     // e.g. "NRL"
    let channelId: String       // "UCxxxxxxxxxxxxxxxxxxxx"
    let handle: String?         // "@NRL"
    let note: String?
    /// Optional override: pull videos from this YouTube playlist instead of the channel's
    /// latest-15 feed. Useful when a channel posts many small clips and the actual match
    /// highlights live in a specific playlist (e.g. SBS Sport's FIFA World Cup playlist).
    let playlistId: String?

    var id: String { (playlistId ?? "") + ":" + channelId }

    /// The RSS URL we should hit for this entry's videos.
    var feedURL: URL {
        if let pid = playlistId {
            return URL(string: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(pid)")!
        }
        return URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)")!
    }

    enum CodingKeys: String, CodingKey {
        case sport, competition, handle, note
        case channelId = "channel_id"
        case playlistId = "playlist_id"
    }
}

// MARK: - Catalog

/// The shape of `channels.json` at the repo root.
typealias ChannelCatalogPayload = [String: [ChannelEntry]]

// MARK: - Video

struct VideoItem: Identifiable, Hashable {
    let id: String                          // YouTube video ID
    let title: String
    let channelTitle: String
    let channelId: String
    let publishedAt: Date
    let thumbnailURL: URL?
    let competition: String                 // joined from ChannelEntry
    let sport: String

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
    var embedURL: URL {
        URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1&rel=0&modestbranding=1")!
    }
}
