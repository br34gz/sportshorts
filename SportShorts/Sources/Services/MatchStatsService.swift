import Foundation

/// Pulls completed-match data from ESPN's public scoreboard JSON for football
/// competitions, then matches it to a video title via team-name parsing.
///
/// Free, no API key, used elsewhere in the project for the daily news Match
/// Results section.

struct MatchStats: Hashable {
    let homeTeam: String
    let homeAbbr: String
    let homeScore: Int
    let awayTeam: String
    let awayAbbr: String
    let awayScore: Int
    let detail: String              // "FT", "FT-Pens", etc
    let kickoff: Date?
    let competitionName: String?    // "FIFA World Cup 2026"
    let venue: String?
    let lines: [StatLine]           // shots, possession, fouls etc

    struct StatLine: Hashable {
        let label: String
        let home: String
        let away: String
        /// 0.0 → fully favours away; 1.0 → fully favours home. Used for the bar overlay.
        let homeRatio: Double?
    }
}

enum MatchStatsService {

    /// Mapping from our internal competition IDs to ESPN's soccer league slugs.
    private static let espnSlug: [String: String] = [
        "fifa_wc":    "fifa.world",
        "epl":        "eng.1",
        "laliga":     "esp.1",
        "bundesliga": "ger.1",
        "ligue1":     "fra.1",
        "seriea":     "ita.1",
        "ucl":        "uefa.champions",
        "uel":        "uefa.europa",
        "fac":        "eng.fa",
        "efl":        "eng.league_cup",
    ]

    static func supports(competitionId: String) -> Bool {
        espnSlug[competitionId] != nil
    }

    /// Try to find a completed match matching the given video.
    /// - Parameters:
    ///   - title: the YouTube video title to parse team names from
    ///   - publishedAt: when the video was posted (typically same day as kickoff)
    ///   - competitionId: which competition the video belongs to
    static func fetchMatch(title: String, publishedAt: Date, competitionId: String) async -> MatchStats? {
        guard let slug = espnSlug[competitionId] else { return nil }
        guard let teamHints = parseTeams(from: title) else { return nil }

        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd"
            return f
        }()

        // Highlight videos are usually posted same-day or 1 day after kickoff.
        // Try [publishedAt - 1 day, publishedAt, publishedAt + 1 day] in turn.
        for delta in [0, -1, -2, 1] {
            let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: delta, to: publishedAt) ?? publishedAt
            let dateStr = dayFormatter.string(from: day)
            if let stats = await fetchAndMatch(slug: slug, dateStr: dateStr, hints: teamHints) {
                return stats
            }
        }
        return nil
    }

    // MARK: - Internal

    private static func fetchAndMatch(slug: String, dateStr: String, hints: TeamHints) async -> MatchStats? {
        let summaryListURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(slug)/scoreboard?dates=\(dateStr)")!
        do {
            var req = URLRequest(url: summaryListURL)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = root["events"] as? [[String: Any]] else { return nil }

            for event in events {
                guard let stype = (event["status"] as? [String: Any])?["type"] as? [String: Any],
                      let completed = stype["completed"] as? Bool, completed else { continue }

                guard let competitions = event["competitions"] as? [[String: Any]],
                      let comp = competitions.first,
                      let competitors = comp["competitors"] as? [[String: Any]],
                      competitors.count == 2 else { continue }

                let home = competitors.first(where: { ($0["homeAway"] as? String) == "home" }) ?? competitors[0]
                let away = competitors.first(where: { ($0["homeAway"] as? String) == "away" }) ?? competitors[1]

                let homeName = teamName(home)
                let awayName = teamName(away)
                if !teamsMatch(homeName: homeName, awayName: awayName, hints: hints) { continue }

                // Found our match — pull score + summary.
                let homeScore = Int(String(home["score"] as? String ?? "0")) ?? 0
                let awayScore = Int(String(away["score"] as? String ?? "0")) ?? 0
                let detail = (stype["detail"] as? String) ?? "FT"
                let venue = (comp["venue"] as? [String: Any])?["fullName"] as? String

                var kickoff: Date?
                if let iso = event["date"] as? String {
                    kickoff = ISO8601DateFormatter().date(from: iso)
                }

                let eventId = event["id"] as? String ?? ""
                let lines = await fetchStatLines(slug: slug, eventId: eventId, homeAbbr: teamAbbr(home), awayAbbr: teamAbbr(away))

                return MatchStats(
                    homeTeam: homeName,
                    homeAbbr: teamAbbr(home),
                    homeScore: homeScore,
                    awayTeam: awayName,
                    awayAbbr: teamAbbr(away),
                    awayScore: awayScore,
                    detail: detail,
                    kickoff: kickoff,
                    competitionName: (event["league"] as? [String: Any])?["name"] as? String,
                    venue: venue,
                    lines: lines
                )
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Fetch per-match team statistics from ESPN's summary endpoint.
    private static func fetchStatLines(slug: String, eventId: String, homeAbbr: String, awayAbbr: String) async -> [MatchStats.StatLine] {
        guard !eventId.isEmpty else { return [] }
        let summaryURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(slug)/summary?event=\(eventId)")!
        do {
            var req = URLRequest(url: summaryURL)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

            // Team stats live under `boxscore.teams[].statistics[]`.
            guard let boxscore = root["boxscore"] as? [String: Any],
                  let teams = boxscore["teams"] as? [[String: Any]],
                  teams.count == 2 else { return [] }

            let homeStats = teams.first(where: { (($0["homeAway"] as? String) ?? ($0["team"] as? [String: Any])?["abbreviation"] as? String) == "home" || (($0["team"] as? [String: Any])?["abbreviation"] as? String) == homeAbbr }) ?? teams[0]
            let awayStats = teams.first(where: { ($0 as NSObject) !== (homeStats as NSObject) }) ?? teams[1]

            let homeArr = (homeStats["statistics"] as? [[String: Any]]) ?? []
            let awayArr = (awayStats["statistics"] as? [[String: Any]]) ?? []

            // Build keyed lookups
            var homeByKey: [String: String] = [:]
            for s in homeArr {
                if let n = s["name"] as? String, let v = s["displayValue"] as? String {
                    homeByKey[n] = v
                }
            }
            var awayByKey: [String: String] = [:]
            for s in awayArr {
                if let n = s["name"] as? String, let v = s["displayValue"] as? String {
                    awayByKey[n] = v
                }
            }

            // The stats we want to surface, in display order, with human labels.
            let wanted: [(String, String)] = [
                ("possessionPct", "Possession"),
                ("totalShots", "Shots"),
                ("shotsOnTarget", "Shots on target"),
                ("foulsCommitted", "Fouls"),
                ("yellowCards", "Yellow cards"),
                ("redCards", "Red cards"),
                ("offsides", "Offsides"),
                ("wonCorners", "Corners"),
                ("totalPasses", "Passes"),
                ("accuratePasses", "Pass accuracy"),
            ]

            var lines: [MatchStats.StatLine] = []
            for (key, label) in wanted {
                guard let h = homeByKey[key], let a = awayByKey[key] else { continue }
                let homeNum = Double(h.replacingOccurrences(of: "%", with: "")) ?? 0
                let awayNum = Double(a.replacingOccurrences(of: "%", with: "")) ?? 0
                let total = homeNum + awayNum
                let ratio: Double? = total > 0 ? max(0, min(1, homeNum / total)) : nil
                lines.append(.init(label: label, home: h, away: a, homeRatio: ratio))
            }
            return lines
        } catch {
            return []
        }
    }

    // MARK: - Team-name parsing + matching

    struct TeamHints {
        let homeTokens: [String]
        let awayTokens: [String]
    }

    private static func parseTeams(from title: String) -> TeamHints? {
        // Look for "X v Y" or "X vs Y", possibly with a colon / dash / | suffix afterwards.
        let pattern = #"\b([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3})\s+(?:v|vs|vs\.)\s+([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3})\b"#
        guard let r = title.range(of: pattern, options: .regularExpression) else { return nil }
        let chunk = String(title[r])
        // Re-split the chunk on " v " / " vs ".
        let separators = [" v ", " vs ", " vs. "]
        for sep in separators {
            if let range = chunk.range(of: sep) {
                let left = String(chunk[..<range.lowerBound])
                let right = String(chunk[range.upperBound...])
                return TeamHints(
                    homeTokens: tokenize(left),
                    awayTokens: tokenize(right)
                )
            }
        }
        return nil
    }

    private static func tokenize(_ name: String) -> [String] {
        name.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func teamsMatch(homeName: String, awayName: String, hints: TeamHints) -> Bool {
        let espnHomeTokens = tokenize(homeName)
        let espnAwayTokens = tokenize(awayName)
        // Sometimes ESPN's home/away mapping flips. Accept either ordering.
        return overlaps(espnHomeTokens, hints.homeTokens) && overlaps(espnAwayTokens, hints.awayTokens)
            || overlaps(espnHomeTokens, hints.awayTokens) && overlaps(espnAwayTokens, hints.homeTokens)
    }

    private static func overlaps(_ a: [String], _ b: [String]) -> Bool {
        for ta in a {
            for tb in b where ta == tb || ta.contains(tb) || tb.contains(ta) {
                return true
            }
        }
        return false
    }

    private static func teamName(_ competitor: [String: Any]) -> String {
        let team = competitor["team"] as? [String: Any]
        return (team?["displayName"] as? String)
            ?? (team?["name"] as? String)
            ?? (team?["abbreviation"] as? String)
            ?? "?"
    }

    private static func teamAbbr(_ competitor: [String: Any]) -> String {
        let team = competitor["team"] as? [String: Any]
        return (team?["abbreviation"] as? String) ?? ""
    }
}
