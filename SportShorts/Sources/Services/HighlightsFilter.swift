import Foundation

/// Heuristic filter to keep only real per-match highlight videos, excluding
/// reels, season compilations, top-N clips, shorts, pressers, podcasts, etc.
enum HighlightsFilter {

    static func isMatchHighlight(title: String) -> Bool {
        let lower = title.lowercased()

        // 1. Hard rejects — any of these wins, video is dropped.
        let rejectKeywords: [String] = [
            "#shorts", " shorts ", "shorts |", "tiktok", "instagram",
            "best moments", "best of", "best try", "best tries", "best goal", "best goals",
            "best moment", "best save", "best saves", "best wickets", "best catches",
            "biggest", "incredible", "insane", "amazing", "stunning", "epic", "wild",
            "must-see", "must see", "wow",
            "top 5", "top 10", "top ten", "top five",
            "of the week", "of the month", "of the season", "of the year",
            "every goal", "every try", "every wicket", "every six", "every basket",
            "all goals", "all tries", "all wickets", "all sixes", "all dunks",
            "player of", "team of",
            "compilation",
            "press conference", "presser", "post-match interview",
            "media call", "media conference",
            "preview", "podcast", "fans react", "tribute",
            "behind the scenes", "bonus features", "extras",
            "escapes", "tackles only", "saves only", "goals only",
            "ranked", "moments only",
            "takes questions", "questions ahead",
            "watch live", "live now",
            "train before", "training", "in training",
        ]
        for kw in rejectKeywords where lower.contains(kw) {
            return false
        }

        // Reject "Rounds X-Y" / "Rounds X to Y" — these are season compilations.
        if lower.range(of: #"rounds?\s+\d+\s*[-–to]+\s*\d"#, options: .regularExpression) != nil {
            return false
        }

        // 2. Positive signals — match any one to keep.

        let hasHighlightWord = lower.contains("highlight") || lower.contains("recap")
        let scoreRegex = #"\b\d{1,3}\s*[-–]\s*\d{1,3}\b"#
        let teamVsTeamRegex = #"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\s+v(?:s|s\.)?\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\b"#

        let hasScore = title.range(of: scoreRegex, options: .regularExpression) != nil
        let hasTeamVsTeam = title.range(of: teamVsTeamRegex, options: .regularExpression) != nil
        let hasCompetitionPhrase = matchesCompetitionPhrase(lower)

        // (a) Explicit "match highlights", "extended highlights", etc.
        if lower.contains("match highlights") ||
           lower.contains("match recap") ||
           lower.contains("extended highlights") ||
           lower.contains("full highlights") {
            return true
        }

        // (b) Single "Round N" reference (not a range) + highlights/recap word.
        if hasHighlightWord,
           lower.range(of: #"round\s+\d+\b"#, options: .regularExpression) != nil {
            return true
        }

        // (c) Score pattern + highlights word.
        if hasScore && hasHighlightWord { return true }

        // (d) "Team A v Team B" + highlights word.
        if hasTeamVsTeam && hasHighlightWord { return true }

        // (e) "Test highlights" / "Test Match" — typical cricket/rugby Test marker.
        if lower.contains("test highlights") || lower.contains("test match highlights") {
            return true
        }

        // (f) "Highlights" combined with a pipe/colon separator.
        if lower.contains("| highlights") ||
           lower.contains("highlights |") ||
           lower.contains(": highlights") ||
           lower.contains("highlights:") {
            return true
        }

        // (g) Title names a competition (Premier League, World Cup, NBA, etc.)
        // AND has a match-shape signal — even without the explicit "highlights"
        // word. This catches official-channel clip titles like
        // "Germany v Paraguay | FIFA World Cup 2026" or "Brazil 2-1 Japan | FIFA World Cup".
        if hasCompetitionPhrase && (hasScore || hasTeamVsTeam) {
            return true
        }

        // (h) Score pattern + competition phrase — even without team-v-team form.
        if hasScore && hasCompetitionPhrase { return true }

        return false
    }

    /// Substring presence test against a baked-in list of competition phrases.
    /// Mirrors the Sport.competitions[].keywords in channels.json but baked
    /// here to keep the filter self-contained and synchronous.
    private static let competitionPhrases: [String] = [
        "premier league", "la liga", "bundesliga", "ligue 1", "serie a",
        "champions league", "europa league", "uefa", "fifa", "world cup",
        "fa cup", "carabao cup", "league cup", "efl cup",
        "nba", "nfl", "nhl", "nbl", "afl", "nrl",
        "stanley cup", "super bowl",
        "wimbledon", "australian open", "us open", "roland garros", "french open",
        "atp tour", "wta tour", "atp", "wta",
        "the ashes", "icc", "ipl ", "big bash", "bbl", "t20i", " t20 ", " odi ", "test match",
        "formula 1", "grand prix",
    ]

    private static func matchesCompetitionPhrase(_ lower: String) -> Bool {
        for p in competitionPhrases where lower.contains(p) { return true }
        return false
    }
}
