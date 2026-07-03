import Foundation

/// Heuristic filter to keep only real per-match highlight videos, excluding
/// reels, season compilations, top-N clips, shorts, pressers, podcasts, etc.
enum HighlightsFilter {

    static func isMatchHighlight(title: String,
                                 allowSpoilers: Bool = true,
                                 customBlocklist: [String] = [],
                                 englishOnly: Bool = false,
                                 // When true, we skip the positive-signal
                                 // requirements and the non-ASCII language
                                 // check — Reddit highlight subs post
                                 // single-clip titles like "⚽ GOAL | 31'"
                                 // that have neither a "highlights" word
                                 // nor mostly-ASCII content, but ARE
                                 // highlights by virtue of the sub.
                                 relaxedForReddit: Bool = false) -> Bool {
        let lower = title.lowercased()

        // Spoiler gate — when spoilers are off, drop titles that reveal the
        // result before the user has chosen to see it. Anything beyond
        // "Team A v Team B | Competition | Date"-style markers is considered
        // a spoiler: explicit scores, goal/score verbs, and result language.
        if !allowSpoilers && isLikelySpoiler(title: title, lower: lower) {
            return false
        }

        // Custom user blocklist — case-insensitive substring reject.
        for term in customBlocklist {
            let t = term.trimmingCharacters(in: .whitespaces).lowercased()
            guard !t.isEmpty else { continue }
            if lower.contains(t) { return false }
        }

        // English-only gate.
        if englishOnly {
            // Explicit non-English markers always reject (Hindi, Español, etc).
            for marker in nonEnglishMarkers where lower.contains(marker) {
                return false
            }
            // Non-ASCII heuristic — skip for Reddit (emoji/flags are Reddit
            // convention, not a language indicator).
            if !relaxedForReddit {
                let asciiCount = title.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 0) }
                let total = title.unicodeScalars.count
                if total > 0 {
                    let nonAsciiRatio = 1.0 - (Double(asciiCount) / Double(total))
                    if nonAsciiRatio > 0.3 { return false }
                }
            }
        }

        // Reddit relaxation: skip the built-in reject-keyword list (Reddit
        // titles rarely conform to those patterns), but still require SOME
        // highlight-shape signal so we don't surface opinion/discussion posts
        // with random screenshots.
        if relaxedForReddit {
            // Discussion-style patterns — reject outright.
            for kw in Self.redditDiscussionRejects where lower.contains(kw) {
                return false
            }
            // Require at least one positive signal that this is actual
            // highlight content — score, team pattern, goal/highlight
            // verb, or the Reddit-scoring bracket convention "[1]".
            if title.range(of: scoreRegex, options: .regularExpression) != nil { return true }
            if title.range(of: #"\[\d+\]"#, options: .regularExpression) != nil { return true }   // [1] Arsenal — reddit convention
            if title.range(of: teamVsTeamRegex, options: .regularExpression) != nil { return true }
            let highlightSignal = [" goal ", "goal!", "goal.", " scores ", " scored ",
                                    " highlight", "highlights", " try ", " tries ",
                                    " td ", " touchdown", " home run", " homer ", " ace ",
                                    " assist", " basket", " dunk ", " ko ",
                                    " point ", " points ", " win ", " goal:", "goal|",
                                    " brace", " hat trick", " hat-trick"]
            for sig in highlightSignal where lower.contains(sig) { return true }
            return false
        }

        // 1. Hard rejects — any of these wins, video is dropped.
        for kw in Self.builtInRejectKeywords where lower.contains(kw) {
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
        "nba", "nfl", "nhl", "mlb", "afl", "nrl",
        "stanley cup", "super bowl", "world series",
        "wimbledon", "australian open", "us open", "roland garros", "french open",
        "atp tour", "wta tour", "atp", "wta",
        "the ashes", "icc", "ipl ", "big bash", "bbl", "t20i", " t20 ", " odi ", "test match",
        "formula 1", "grand prix",
    ]

    private static func matchesCompetitionPhrase(_ lower: String) -> Bool {
        for p in competitionPhrases where lower.contains(p) { return true }
        return false
    }

    /// If the title would be rejected, returns a short human-readable reason
    /// (e.g. "matches spoiler word: goal", "matches your custom blocklist: X").
    /// Returns nil if the title would pass.
    static func rejectionReason(title: String,
                                 allowSpoilers: Bool = true,
                                 customBlocklist: [String] = [],
                                 englishOnly: Bool = false) -> String? {
        let lower = title.lowercased()
        if !allowSpoilers && isLikelySpoiler(title: title, lower: lower) {
            return "Looks like a spoiler (score / result verb). Flip the eye icon on Highlights to show spoilers."
        }
        for term in customBlocklist {
            let t = term.trimmingCharacters(in: .whitespaces).lowercased()
            if !t.isEmpty, lower.contains(t) {
                return "Matches your custom blocklist term: \"\(term)\"."
            }
        }
        if englishOnly && !isLikelyEnglish(title: title, lower: lower) {
            return "Non-English title. Turn off 'English highlights only' in Advanced settings to include this."
        }
        for kw in Self.builtInRejectKeywords where lower.contains(kw) {
            return "Matches built-in reject term: \"\(kw)\"."
        }
        if lower.range(of: #"rounds?\s+\d+\s*[-–to]+\s*\d"#, options: .regularExpression) != nil {
            return "Looks like a season-round compilation ('Rounds X-Y')."
        }
        return nil
    }

    /// Public copy of the reject keyword list so the tester can iterate them
    /// without duplicating the constant. Keep in sync with the private list
    /// used by isMatchHighlight.
    static let builtInRejectKeywords: [String] = [
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

    // MARK: - Spoiler detection

    private static let spoilerVerbs: [String] = [
        " goal ", " goals ", " goal!", " goal:", "goal|",
        " scores ", " scored ", " scoring ", " scorer",
        " wins ", " winning ", " winner ", " win!", " win:",
        " loses ", " loss ", " losing ", " loser",
        " beat ", " beats ", " beaten ", " thrash", " hammer",
        " defeat ", " defeats ", " defeated ", " stuns ", " stunner",
        " upset ", " comeback ", " collapse", " demolish",
        " smashed ", " crushed ", " edge ", " edges ", " pip ", " pips ",
        " knockout ", " knock out ", " knocked out ", " eliminated ",
        " through to ", " advance to ", " advances to ",
        " hat-trick ", " hattrick ", " brace ", " double ", " triple ",
        " penalty shootout ", " shootout ",
        " send off", " sent off", " red card", " sending off",
        " dismissed ", " own goal",
    ]

    private static let scoreRegex = #"\b\d{1,3}\s*[-–]\s*\d{1,3}\b"#

    // MARK: - Reddit discussion rejects

    /// Patterns that reliably identify opinion / discussion / meta posts on
    /// highlight subs, so we don't ship a "rigged referee???" screenshot as
    /// a highlight.
    private static let redditDiscussionRejects: [String] = [
        " rigged", " biased", " bias ", " unfair",
        " opinion", " unpopular ", " rant ", " hot take",
        " thoughts?", " discuss", " controversy", " controversial",
        " why is", " why does", " why don't", " why can't",
        " am i the only", " does anyone", " looking for",
        "megathread", "match thread", "official thread", "post match thread",
        "hate ", "love or hate", "worst ",
        "help me", "recommendation", "recommend me",
    ]

    // MARK: - Language detection

    /// Explicit non-English tags that broadcasters add when re-uploading the
    /// same clip per language (FIFA, ICC, UEFA, DAZN etc all do this).
    private static let nonEnglishMarkers: [String] = [
        // language names in English (as they appear in titles)
        " hindi", "in hindi", "hindi commentary", "hindi highlights",
        " tamil", "in tamil", "tamil commentary",
        " telugu", "in telugu",
        " bengali", "in bengali",
        " marathi", "in marathi",
        " urdu", "in urdu", "urdu commentary",
        " arabic", "in arabic",
        " español", "en español", "español highlights",
        " spanish", "in spanish",
        " português", "em português",
        " portuguese", "in portuguese",
        " français", "en français",
        " french", "in french",
        " deutsch", "auf deutsch",
        " german", "in german",
        " italiano", "in italiano",
        " italian", "in italian",
        " nederlands", "in nederlands",
        " dutch", "in dutch",
        " russian", "in russian", " русский",
        " japanese", "in japanese", " 日本語",
        " korean", "in korean", " 한국어",
        " chinese", "in chinese", " mandarin", " cantonese",
        " indonesian", "bahasa",
        " thai", "in thai",
        " vietnamese", "in vietnamese",
        " turkish", "in turkish", " türkçe",
        " polish", "in polish", " polski",
        " swahili", "in swahili",
    ]

    private static func isLikelyEnglish(title: String, lower: String) -> Bool {
        // Explicit non-English language marker → not English.
        for marker in nonEnglishMarkers where lower.contains(marker) { return false }

        // Non-ASCII heavy title → likely non-English script.
        let asciiCount = title.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 0) }
        let total = title.unicodeScalars.count
        guard total > 0 else { return true }
        let nonAsciiRatio = 1.0 - (Double(asciiCount) / Double(total))
        if nonAsciiRatio > 0.3 { return false }

        return true
    }

    private static func isLikelySpoiler(title: String, lower: String) -> Bool {
        // Numeric score line gives away the result.
        if title.range(of: scoreRegex, options: .regularExpression) != nil {
            // 4-digit year ranges shouldn't count as a score — pad with spaces
            // and check whether the matched range looks like a small score.
            // For simplicity, treat any X-Y where both X,Y < 100 as a spoiler.
            let paddedLower = " " + lower + " "
            if let r = paddedLower.range(of: scoreRegex, options: .regularExpression) {
                let parts = paddedLower[r].split(whereSeparator: { $0 == "-" || $0 == "–" })
                if parts.count == 2,
                   let a = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let b = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                   a < 100, b < 100 {
                    return true
                }
            }
        }
        let padded = " " + lower + " "
        for verb in spoilerVerbs where padded.contains(verb) { return true }
        return false
    }
}
