import Foundation

/// Heuristic filter to keep only "real match highlight" videos and drop reels,
/// shorts, player-of-the-week clips, news segments, etc.
enum HighlightsFilter {

    static func isMatchHighlight(title: String) -> Bool {
        let lower = title.lowercased()

        // Hard rejects.
        let reject = [
            "#shorts", "shorts", "#short", "tiktok", "instagram",
            "best moments of", "top 10", "top ten", "top 5", "top five",
            "player of the week", "player of the month", "all goals", "all tries",
            "all sixes", "all wickets", "moment of the year", "every goal", "every try",
            "every wicket", "all wickets", "compilation",
            "press conference", "presser", "interview", "post-match interview",
            "media call", "media conference", "newsbreak", "opinion",
            "tribute", "preview", "the panel", "podcast", "fans react",
        ]
        for kw in reject where lower.contains(kw) {
            return false
        }

        // Strong positives — title looks like a recap.
        let positives = [
            "match highlights", "match recap", "extended highlights", "full highlights",
            "highlights:", "recap:", "match report", "test highlights",
            "round-up", " ft ", " full-time", " - highlights", "| highlights",
            "highlight package",
        ]
        for kw in positives where lower.contains(kw) {
            return true
        }

        // Soft positive: "Team A v Team B" / "Team A vs Team B" pattern + has "highlights" loosely.
        let teamVsPattern = #"\b[A-Z][a-zA-Z]+(?:[ -][A-Z][a-zA-Z]+)*\s+(?:v|vs|vs\.)\s+[A-Z][a-zA-Z]+(?:[ -][A-Z][a-zA-Z]+)*\b"#
        if let _ = title.range(of: teamVsPattern, options: .regularExpression) {
            // The presence of the matchup pattern is informative but not enough on its own —
            // require either "highlights" or "recap" elsewhere in the title.
            if lower.contains("highlight") || lower.contains("recap") {
                return true
            }
        }

        // Last-resort accept: title plainly contains "highlights" or "recap" without rejected words.
        if lower.contains("highlights") || lower.contains("recap") {
            return true
        }

        return false
    }
}
