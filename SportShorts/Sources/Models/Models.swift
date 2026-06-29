import Foundation

// MARK: - Country

struct Country: Identifiable, Hashable, Codable {
    let code: String        // ISO-2 like "AU", "UK"
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

// MARK: - Channel

/// A single YouTube channel or playlist that posts highlights for a competition
/// in (optionally) a specific country.
struct Channel: Identifiable, Hashable, Codable {
    let channelId: String
    let playlistId: String?
    let handle: String?
    let note: String?

    var id: String { (playlistId ?? "") + ":" + channelId }

    var feedURL: URL {
        if let pid = playlistId {
            return URL(string: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(pid)")!
        }
        return URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)")!
    }

    enum CodingKeys: String, CodingKey {
        case handle, note
        case channelId = "channel_id"
        case playlistId = "playlist_id"
    }
}

// MARK: - Competition

/// One competition (Premier League, Champions League, etc) within a sport.
/// Channels are split into a `global` set (used everywhere) and per-country
/// supplements that apply only when the user has selected that country.
struct Competition: Identifiable, Hashable, Codable {
    let id: String                              // "epl", "ucl"
    let label: String                           // "Premier League"
    let globalChannels: [Channel]
    let countryChannels: [String: [Channel]]    // "AU" -> [Channel...]

    func effectiveChannels(for countryCode: String) -> [Channel] {
        var merged: [Channel] = globalChannels
        if let extras = countryChannels[countryCode] {
            for ch in extras where !merged.contains(ch) {
                merged.append(ch)
            }
        }
        return merged
    }

    enum CodingKeys: String, CodingKey {
        case id, label
        case globalChannels = "global_channels"
        case countryChannels = "country_channels"
    }
}

// MARK: - Sport

struct Sport: Identifiable, Hashable, Codable {
    let id: String                  // "soccer", "nba"
    let label: String               // "Soccer"
    let icon: String                // SF Symbol name
    let competitions: [Competition]
}

// MARK: - Catalog (top-level payload of channels.json)

struct Catalog: Codable {
    let sports: [Sport]
}

// MARK: - Video

struct VideoItem: Identifiable, Hashable {
    let id: String                  // YouTube video ID
    let title: String
    let channelTitle: String
    let channelId: String
    let publishedAt: Date
    let thumbnailURL: URL?
    let competitionId: String
    let competitionLabel: String
    let sportId: String
    let sportLabel: String
    let sportIcon: String

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
}
