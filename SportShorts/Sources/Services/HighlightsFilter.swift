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
        ]
        for kw in rejectKeywords where lower.contains(kw) {
            return false
        }

        // Reject "Rounds X-Y" / "Rounds X to Y" — these are season compilations.
        if lower.range(of: #"rounds?\s+\d+\s*[-–to]+\s*\d"#, options: .regularExpression) != nil {
            return false
        }

        // 2. Positive signals — must match at least one of these to be kept.

        let hasHighlightWord = lower.contains("highlight") || lower.contains("recap")

        // (a) "match highlights", "extended highlights", "full highlights", "match recap"
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

        // (c) Score pattern (e.g. "Liverpool 3-1 Man United", "21-7", "South Africa 3 Canada 0").
        if title.range(of: #"\b\d{1,3}\s*[-–]\s*\d{1,3}\b"#, options: .regularExpression) != nil,
           hasHighlightWord {
            return true
        }

        // (d) "Team A v(s) Team B" pattern with two capitalized phrases + highlights word.
        let teamVsTeam = #"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\s+v(?:s|s\.)?\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\b"#
        if title.range(of: teamVsTeam, options: .regularExpression) != nil,
           hasHighlightWord {
            return true
        }

        // (e) "Test highlights" / "Test Match" — typical cricket / rugby Test marker.
        if lower.contains("test highlights") || lower.contains("test match highlights") {
            return true
        }

        // (f) "Highlights:" or "| Highlights" form (suffix or colon) — common for tournament games.
        if lower.contains("| highlights") ||
           lower.contains(": highlights") ||
           lower.contains("highlights:") {
            return true
        }

        return false
    }
}
