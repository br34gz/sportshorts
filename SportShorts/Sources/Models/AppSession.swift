import Foundation
import SwiftUI

/// App-wide observable session state: which country, which sports the user
/// follows, loaded channel catalog, current feed. Held by SportShortsApp as
/// an environment object.
@Observable
final class AppSession {
    var country: Country? {
        didSet {
            UserDefaults.standard.set(country?.code, forKey: "sportshorts.country")
        }
    }

    /// Set of competition labels the user follows (e.g. ["NRL", "AFL", "EPL"]).
    /// Stored as a comma-joined string under @AppStorage semantics via UserDefaults.
    var followedCompetitions: Set<String> {
        didSet {
            UserDefaults.standard.set(
                followedCompetitions.sorted().joined(separator: ","),
                forKey: "sportshorts.followed"
            )
        }
    }

    var catalog: ChannelCatalogPayload = [:]
    var feed: [VideoItem] = []
    var isLoadingFeed = false
    var lastFeedError: String?

    init() {
        let countryCode = UserDefaults.standard.string(forKey: "sportshorts.country")
        self.country = Country.supported.first { $0.code == countryCode }
        let joined = UserDefaults.standard.string(forKey: "sportshorts.followed") ?? ""
        self.followedCompetitions = Set(joined.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    var hasCompletedOnboarding: Bool {
        country != nil && !followedCompetitions.isEmpty
    }

    /// Channels for the current country filtered to followed competitions.
    var activeChannels: [ChannelEntry] {
        guard let country else { return [] }
        let all = catalog[country.code] ?? []
        if followedCompetitions.isEmpty { return all }
        return all.filter { followedCompetitions.contains($0.competition) }
    }
}
