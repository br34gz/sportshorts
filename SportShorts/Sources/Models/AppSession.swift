import Foundation
import SwiftUI

/// App-wide observable state: country, followed competitions, loaded catalog,
/// current feed. The catalog is sport-centric; per-country channels are
/// resolved at query time via Competition.effectiveChannels(for:).
@Observable
final class AppSession {
    var country: Country? {
        didSet {
            UserDefaults.standard.set(country?.code, forKey: "sportshorts.country")
        }
    }

    /// Set of competition IDs the user follows (e.g. ["epl", "ucl", "nba"]).
    var followedCompetitionIds: Set<String> {
        didSet {
            UserDefaults.standard.set(
                followedCompetitionIds.sorted().joined(separator: ","),
                forKey: "sportshorts.followed_ids"
            )
        }
    }

    var catalog: Catalog = Catalog(sports: [])
    var feed: [VideoItem] = []
    var isLoadingFeed = false
    var lastFeedError: String?

    init() {
        let code = UserDefaults.standard.string(forKey: "sportshorts.country")
        self.country = Country.supported.first { $0.code == code }
        let joined = UserDefaults.standard.string(forKey: "sportshorts.followed_ids") ?? ""
        self.followedCompetitionIds = Set(joined.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    var hasCompletedOnboarding: Bool {
        country != nil && !followedCompetitionIds.isEmpty
    }

    /// Flat list of (sport, competition) pairs the user follows.
    var followedCompetitions: [(sport: Sport, competition: Competition)] {
        var out: [(Sport, Competition)] = []
        for sport in catalog.sports {
            for comp in sport.competitions where followedCompetitionIds.contains(comp.id) {
                out.append((sport, comp))
            }
        }
        return out
    }

    /// All channels to query for the current country, with their owning sport/competition.
    var activeQueries: [(sport: Sport, competition: Competition, channel: Channel)] {
        let code = country?.code ?? ""
        var out: [(Sport, Competition, Channel)] = []
        for (sport, comp) in followedCompetitions {
            for ch in comp.effectiveChannels(for: code) {
                out.append((sport, comp, ch))
            }
        }
        return out
    }
}
