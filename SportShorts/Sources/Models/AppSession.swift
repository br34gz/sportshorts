import Foundation
import SwiftUI

/// App-wide observable state: country, followed sports, user-added channels,
/// hidden built-in channels, loaded catalog, current feed.
@Observable
final class AppSession {
    var country: Country? {
        didSet { UserDefaults.standard.set(country?.code, forKey: "sportshorts.country") }
    }

    var followedSportIds: Set<String> {
        didSet { persistSet(followedSportIds, key: "sportshorts.followed_sports") }
    }

    /// Channels the user added manually via Settings (not in the catalog).
    var userAddedChannels: [YouTubeChannel] {
        didSet {
            if let data = try? JSONEncoder().encode(userAddedChannels) {
                UserDefaults.standard.set(data, forKey: "sportshorts.user_channels")
            }
        }
    }

    /// Channel IDs the user has hidden from their feed (built-ins they don't want).
    var hiddenChannelIds: Set<String> {
        didSet { persistSet(hiddenChannelIds, key: "sportshorts.hidden_channels") }
    }

    var catalog: Catalog = .empty
    var feed: [VideoItem] = []
    var isLoadingFeed = false
    var lastFeedError: String?

    init() {
        let code = UserDefaults.standard.string(forKey: "sportshorts.country")
        self.country = Country.supported.first { $0.code == code }

        self.followedSportIds = Self.loadSet("sportshorts.followed_sports")
        self.hiddenChannelIds = Self.loadSet("sportshorts.hidden_channels")

        if let data = UserDefaults.standard.data(forKey: "sportshorts.user_channels"),
           let decoded = try? JSONDecoder().decode([YouTubeChannel].self, from: data) {
            self.userAddedChannels = decoded
        } else {
            self.userAddedChannels = []
        }

        // Migrate legacy 'followed_ids' (which held competition IDs) → followed_sports.
        // Translate any competition IDs that map cleanly to a sport ID, keep the rest as-is
        // (sport IDs already in the legacy list will pass through).
        let legacy = UserDefaults.standard.string(forKey: "sportshorts.followed_ids") ?? ""
        if !legacy.isEmpty && followedSportIds.isEmpty {
            let legacyIds = Set(legacy.split(separator: ",").map(String.init))
            let translated = legacyIds.compactMap(Self.legacyCompToSport(_:))
            if !translated.isEmpty {
                self.followedSportIds = Set(translated)
                persistSet(followedSportIds, key: "sportshorts.followed_sports")
            }
            UserDefaults.standard.removeObject(forKey: "sportshorts.followed_ids")
        }
    }

    var hasCompletedOnboarding: Bool {
        country != nil && !followedSportIds.isEmpty
    }

    /// Wipes country, sports, manually added channels and hidden built-ins.
    /// Caller-visible effect: app returns to onboarding's country step.
    func resetApp() {
        country = nil
        followedSportIds = []
        userAddedChannels = []
        hiddenChannelIds = []
        feed = []
        lastFeedError = nil
    }

    /// Every channel the feed should pull from for the current country:
    /// country broadcasters + global league channels + user-added — minus
    /// anything the user has hidden.
    var activeChannels: [YouTubeChannel] {
        let countryChannels = country.flatMap { catalog.countries[$0.code] } ?? []
        var all = countryChannels + catalog.globalChannels + userAddedChannels
        // Dedupe by channelId (a channel listed both for a country and globally).
        var seen = Set<String>()
        all = all.filter { seen.insert($0.channelId).inserted }
        all.removeAll { hiddenChannelIds.contains($0.channelId) }
        return all
    }

    // MARK: - Persistence helpers

    private func persistSet(_ set: Set<String>, key: String) {
        UserDefaults.standard.set(set.sorted().joined(separator: ","), forKey: key)
    }

    private static func loadSet(_ key: String) -> Set<String> {
        let joined = UserDefaults.standard.string(forKey: key) ?? ""
        return Set(joined.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    /// Map old competition IDs to a sport ID for one-off migration.
    private static func legacyCompToSport(_ id: String) -> String? {
        switch id {
        case "epl", "laliga", "bundesliga", "ligue1", "seriea",
             "ucl", "uel", "fac", "efl", "fifa_wc":
            return "soccer"
        case "nba": return "nba"
        case "nbl": return "nbl"
        case "nfl": return "nfl"
        case "nhl": return "nhl"
        case "f1":  return "f1"
        case "afl": return "afl"
        case "nrl": return "nrl"
        case "ao", "wimbledon", "us_open", "rg": return "tennis"
        case "cricket_intl": return "cricket"
        default:
            // Maybe the legacy entry is already a sport id.
            let known: Set<String> = ["soccer","nba","nbl","nfl","nhl","f1","afl","nrl","tennis","cricket"]
            return known.contains(id) ? id : nil
        }
    }
}
