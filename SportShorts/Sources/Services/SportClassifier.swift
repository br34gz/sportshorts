import Foundation

/// Maps a video (title + the channel it came from) to a Sport and optionally
/// a Competition. Used after we've fetched all channels for a country —
/// the result drives the user's sport-filter and labels the video card.
///
/// The classifier never returns a sport "we don't know" — it returns nil and
/// the FeedFetcher drops the item.
enum SportClassifier {

    struct Match {
        let sport: Sport
        let competition: CompetitionMeta?
    }

    /// Classify a video by title, using the source channel's sport hints as a
    /// prior. If the channel is single-sport (e.g. "Sky Sports F1") we trust
    /// that hint and only fall back to keyword matching for the competition.
    /// Otherwise keyword matching does the sport assignment too.
    static func classify(title: String, channel: YouTubeChannel, catalog: Catalog) -> Match? {
        let lower = title.lowercased()

        // 1. Channel sport-hint as a strong prior
        if channel.sportHints.count == 1,
           let sport = catalog.sports.first(where: { $0.id == channel.sportHints[0] }) {
            return Match(sport: sport, competition: matchCompetition(lower, in: sport))
        }

        // 2. Keyword match on the title
        // Try competitions first — a competition match implies the sport.
        for sport in catalog.sports {
            if let comp = matchCompetition(lower, in: sport) {
                return Match(sport: sport, competition: comp)
            }
        }
        for sport in catalog.sports {
            for kw in sport.keywords where lower.contains(kw) {
                return Match(sport: sport, competition: matchCompetition(lower, in: sport))
            }
        }

        // 3. If the channel had multiple sport hints, fall back to the first
        // as a last resort (rather than dropping the video entirely).
        if let hintId = channel.sportHints.first,
           let sport = catalog.sports.first(where: { $0.id == hintId }) {
            return Match(sport: sport, competition: matchCompetition(lower, in: sport))
        }

        return nil
    }

    private static func matchCompetition(_ lowerTitle: String, in sport: Sport) -> CompetitionMeta? {
        for comp in sport.competitions {
            for kw in comp.keywords where lowerTitle.contains(kw) {
                return comp
            }
        }
        return nil
    }
}
