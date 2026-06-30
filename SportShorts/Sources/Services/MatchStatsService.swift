import Foundation

/// Pulls completed-match data from ESPN's public scoreboard JSON for the
/// supported team sports, then matches it to a video title via team-name
/// parsing. Free, no API key.

struct MatchStats: Hashable {
    let homeTeam: String
    let homeAbbr: String
    let homeScore: Int                          // sets won (tennis), goals/points (team sports)
    let awayTeam: String
    let awayAbbr: String
    let awayScore: Int
    let lineScore: String?                      // tennis only: "6-4 7-5 6-3"
    let detail: String
    let kickoff: Date?
    let competitionName: String?
    let venue: String?
    let lines: [StatLine]
    /// Set instead of homeTeam/awayTeam when the result is a race (F1 etc).
    /// When present, the StatsPanel renders this leaderboard rather than the
    /// team-vs-team scoreblock.
    let raceLeaderboard: [RaceEntry]?

    struct StatLine: Hashable {
        let label: String
        let home: String
        let away: String
        let homeRatio: Double?
    }

    struct RaceEntry: Hashable {
        let position: Int
        let driverName: String
        let teamName: String?
        let timeOrGap: String?
    }
}

enum MatchStatsService {

    /// Maps our internal competition IDs to ESPN sport+league slugs + the per-sport
    /// stat fields we want to surface. Stat keys come from ESPN's `statistics[].name`;
    /// labels are what we render in the UI.
    private struct SportConfig {
        let espnSport: String
        let espnLeague: String
        let stats: [(key: String, label: String, isPercent: Bool)]
    }

    private static let configs: [String: SportConfig] = [
        // Soccer
        "fifa_wc":    .init(espnSport: "soccer", espnLeague: "fifa.world",     stats: soccerStats),
        "epl":        .init(espnSport: "soccer", espnLeague: "eng.1",          stats: soccerStats),
        "laliga":     .init(espnSport: "soccer", espnLeague: "esp.1",          stats: soccerStats),
        "bundesliga": .init(espnSport: "soccer", espnLeague: "ger.1",          stats: soccerStats),
        "ligue1":     .init(espnSport: "soccer", espnLeague: "fra.1",          stats: soccerStats),
        "seriea":     .init(espnSport: "soccer", espnLeague: "ita.1",          stats: soccerStats),
        "ucl":        .init(espnSport: "soccer", espnLeague: "uefa.champions", stats: soccerStats),
        "uel":        .init(espnSport: "soccer", espnLeague: "uefa.europa",    stats: soccerStats),
        "fac":        .init(espnSport: "soccer", espnLeague: "eng.fa",         stats: soccerStats),
        "efl":        .init(espnSport: "soccer", espnLeague: "eng.league_cup", stats: soccerStats),

        // Basketball
        "nba": .init(espnSport: "basketball", espnLeague: "nba", stats: basketballStats),
        "nbl": .init(espnSport: "basketball", espnLeague: "nbl", stats: basketballStats),

        // American football
        "nfl": .init(espnSport: "football",   espnLeague: "nfl", stats: nflStats),

        // Ice hockey
        "nhl": .init(espnSport: "hockey",     espnLeague: "nhl", stats: nhlStats),

        // Australian Rules
        "afl": .init(espnSport: "australian-football", espnLeague: "afl", stats: aflStats),

        // Tennis — same league slug for all Grand Slams; matches are filtered
        // by date and team-name parsing.
        "ao":       .init(espnSport: "tennis", espnLeague: "atp", stats: tennisStats),
        "wimbledon":.init(espnSport: "tennis", espnLeague: "atp", stats: tennisStats),
        "us_open":  .init(espnSport: "tennis", espnLeague: "atp", stats: tennisStats),
        "rg":       .init(espnSport: "tennis", espnLeague: "atp", stats: tennisStats),

        // Formula 1 — handled via the dedicated race code path below
        // (raceLeaderboard instead of homeTeam/awayTeam). stats list unused.
        "f1": .init(espnSport: "racing", espnLeague: "f1", stats: []),
    ]

    private static let soccerStats: [(String, String, Bool)] = [
        ("possessionPct",   "Possession",       true),
        ("totalShots",      "Shots",            false),
        ("shotsOnTarget",   "Shots on target",  false),
        ("foulsCommitted",  "Fouls",            false),
        ("yellowCards",     "Yellow cards",     false),
        ("redCards",        "Red cards",        false),
        ("offsides",        "Offsides",         false),
        ("wonCorners",      "Corners",          false),
        ("totalPasses",     "Passes",           false),
        ("accuratePasses",  "Pass accuracy",    true),
    ]

    private static let basketballStats: [(String, String, Bool)] = [
        ("fieldGoalsMade-fieldGoalsAttempted",         "Field Goals",  false),
        ("fieldGoalPct",                               "FG %",         true),
        ("threePointFieldGoalsMade-threePointFieldGoalsAttempted", "3-Pointers", false),
        ("threePointFieldGoalPct",                     "3-Pt %",       true),
        ("freeThrowsMade-freeThrowsAttempted",         "Free Throws",  false),
        ("totalRebounds",                              "Rebounds",     false),
        ("assists",                                    "Assists",      false),
        ("steals",                                     "Steals",        false),
        ("blocks",                                     "Blocks",        false),
        ("turnovers",                                  "Turnovers",     false),
        ("personalFouls",                              "Fouls",         false),
    ]

    private static let nflStats: [(String, String, Bool)] = [
        ("firstDowns",         "1st Downs",       false),
        ("totalYards",         "Total Yards",     false),
        ("yardsPerPlay",       "Yards / Play",    false),
        ("passingYards",       "Passing Yards",   false),
        ("rushingYards",       "Rushing Yards",   false),
        ("turnovers",          "Turnovers",       false),
        ("possessionTime",     "Possession",      false),
        ("totalPenaltyYards",  "Penalty Yards",   false),
        ("thirdDownEff",       "3rd Down",        false),
        ("redZoneAttempts",    "Red Zone",        false),
    ]

    private static let nhlStats: [(String, String, Bool)] = [
        ("goals",                "Goals",          false),
        ("shotsTotal",           "Shots",          false),
        ("faceoffWinPercent",    "Faceoff %",      true),
        ("powerPlayGoals",       "PP Goals",       false),
        ("penaltyMinutes",       "PIM",            false),
        ("hits",                 "Hits",           false),
        ("blockedShots",         "Blocks",         false),
        ("giveaways",            "Giveaways",      false),
        ("takeaways",            "Takeaways",      false),
    ]

    private static let aflStats: [(String, String, Bool)] = [
        ("goals",       "Goals",     false),
        ("behinds",     "Behinds",   false),
        ("marks",       "Marks",     false),
        ("disposals",   "Disposals", false),
        ("kicks",       "Kicks",     false),
        ("handballs",   "Handballs", false),
        ("tackles",     "Tackles",   false),
        ("inside50s",   "Inside 50s", false),
    ]

    // NRL removed — ESPN's public API does not carry NRL data.

    private static let tennisStats: [(String, String, Bool)] = [
        ("aces",                "Aces",            false),
        ("doubleFaults",        "Double Faults",   false),
        ("winners",             "Winners",         false),
        ("unforcedErrors",      "Unforced Errors", false),
        ("breakPointsConverted","Break Points",    false),
        ("firstServePct",       "1st Serve %",     true),
        ("firstServePointsWonPct","1st Serve Won %", true),
        ("secondServePointsWonPct","2nd Serve Won %", true),
        ("netPointsWonPct",     "Net Points %",    true),
        ("totalPointsWon",      "Total Points",    false),
    ]

    static func supports(competitionId: String) -> Bool {
        // NRL is handled via TheSportsDB rather than ESPN, so it's not in
        // `configs` but is supported.
        if competitionId == "nrl" { return true }
        return configs[competitionId] != nil
    }

    /// Try to find a completed match (or race, for F1) for the given video.
    static func fetchMatch(title: String, publishedAt: Date, competitionId: String) async -> MatchStats? {
        // F1 is a race, not a team match — different fetch path entirely.
        if competitionId == "f1" {
            guard let config = configs[competitionId] else { return nil }
            return await fetchRace(config: config, publishedAt: publishedAt)
        }
        // NRL has no ESPN coverage — use TheSportsDB.
        if competitionId == "nrl" {
            return await fetchNRLMatch(title: title, publishedAt: publishedAt)
        }
        guard let config = configs[competitionId] else { return nil }
        guard let teamHints = parseTeams(from: title) else { return nil }

        // Tennis tournaments wrap a multi-day bracket — the event has
        // event.groupings[].competitions[] (one per match) rather than
        // event.competitions[].competitors[]. Walk the bracket separately.
        if config.espnSport == "tennis" {
            for delta in [0, -1, -2, 1, -3, -4] {
                let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: delta, to: publishedAt) ?? publishedAt
                let dateStr = utcDay(day)
                if let stats = await fetchTennisMatch(config: config, dateStr: dateStr, hints: teamHints) {
                    return stats
                }
            }
            return nil
        }

        // Highlight videos are usually posted same-day or 1 day after kickoff.
        for delta in [0, -1, -2, 1] {
            let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: delta, to: publishedAt) ?? publishedAt
            let dateStr = utcDay(day)
            if let stats = await fetchAndMatch(config: config, dateStr: dateStr, hints: teamHints) {
                return stats
            }
        }
        return nil
    }

    private static func utcDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    // MARK: - Tennis (ESPN bracket walker)

    private static func fetchTennisMatch(config: SportConfig, dateStr: String, hints: TeamHints) async -> MatchStats? {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard?dates=\(dateStr)")!
        // Also probe WTA for women's matches — the title parser doesn't tell us
        // which tour the players belong to.
        let wtaURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/tennis/wta/scoreboard?dates=\(dateStr)")!
        for src in [url, wtaURL] {
            if let stats = await walkTennisBracket(url: src, hints: hints) { return stats }
        }
        return nil
    }

    private static func walkTennisBracket(url: URL, hints: TeamHints) async -> MatchStats? {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = root["events"] as? [[String: Any]] else { return nil }

            for event in events {
                let tournamentName = event["name"] as? String
                // Tennis-shaped event → has groupings; flat events fall through.
                guard let groupings = event["groupings"] as? [[String: Any]] else { continue }
                for grouping in groupings {
                    guard let competitions = grouping["competitions"] as? [[String: Any]] else { continue }
                    for comp in competitions {
                        guard let stype = (comp["status"] as? [String: Any])?["type"] as? [String: Any],
                              (stype["completed"] as? Bool) ?? false else { continue }
                        guard let competitors = comp["competitors"] as? [[String: Any]],
                              competitors.count == 2 else { continue }
                        let p1Name = teamName(competitors[0])
                        let p2Name = teamName(competitors[1])
                        if !teamsMatch(homeName: p1Name, awayName: p2Name, hints: hints) { continue }

                        // Tally sets won + build a "6-2 7-5" linescore.
                        let lines1 = (competitors[0]["linescores"] as? [[String: Any]]) ?? []
                        let lines2 = (competitors[1]["linescores"] as? [[String: Any]]) ?? []
                        let setCount = min(lines1.count, lines2.count)
                        var p1Sets = 0, p2Sets = 0
                        var parts: [String] = []
                        for i in 0..<setCount {
                            let a = Int((lines1[i]["value"] as? Double) ?? 0)
                            let b = Int((lines2[i]["value"] as? Double) ?? 0)
                            if a > b { p1Sets += 1 } else if b > a { p2Sets += 1 }
                            parts.append("\(a)-\(b)")
                        }

                        let detail = (stype["detail"] as? String) ?? "Final"
                        var kickoff: Date?
                        if let iso = comp["date"] as? String {
                            kickoff = ISO8601DateFormatter().date(from: iso)
                        }
                        let venue = (comp["venue"] as? [String: Any])?["fullName"] as? String

                        return MatchStats(
                            homeTeam: p1Name,
                            homeAbbr: teamAbbr(competitors[0]),
                            homeScore: p1Sets,
                            awayTeam: p2Name,
                            awayAbbr: teamAbbr(competitors[1]),
                            awayScore: p2Sets,
                            lineScore: parts.isEmpty ? nil : parts.joined(separator: " "),
                            detail: detail,
                            kickoff: kickoff,
                            competitionName: tournamentName,
                            venue: venue,
                            lines: [],
                            raceLeaderboard: nil
                        )
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - NRL (TheSportsDB)

    /// TheSportsDB free key "3" is the documented test key; rate limit is
    /// generous for a single-user app. League id 4416 = Australian NRL.
    private static let theSportsDBKey = "3"
    private static let nrlLeagueId = 4416

    private static func fetchNRLMatch(title: String, publishedAt: Date) async -> MatchStats? {
        guard let hints = parseTeams(from: title) else { return nil }
        // Past 15 events from the league — good enough for "within the last
        // 7 days" matching of a highlight video that just dropped.
        let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(theSportsDBKey)/eventspastleague.php?id=\(nrlLeagueId)")!
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = root["events"] as? [[String: Any]] else { return nil }

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")

            for event in events {
                let homeTeam = (event["strHomeTeam"] as? String) ?? ""
                let awayTeam = (event["strAwayTeam"] as? String) ?? ""
                guard !homeTeam.isEmpty, !awayTeam.isEmpty else { continue }

                let homeTokens = tokenize(homeTeam)
                let awayTokens = tokenize(awayTeam)
                let matched = (overlaps(homeTokens, hints.homeTokens) && overlaps(awayTokens, hints.awayTokens))
                           || (overlaps(homeTokens, hints.awayTokens) && overlaps(awayTokens, hints.homeTokens))
                if !matched { continue }

                if let dateStr = event["dateEvent"] as? String,
                   let eventDate = df.date(from: dateStr),
                   abs(publishedAt.timeIntervalSince(eventDate)) > 5 * 86_400 {
                    continue
                }

                let homeScore = Int((event["intHomeScore"] as? String) ?? "0") ?? 0
                let awayScore = Int((event["intAwayScore"] as? String) ?? "0") ?? 0
                let round: String = {
                    if let r = event["intRound"] as? String, !r.isEmpty { return "Round \(r)" }
                    return "FT"
                }()
                let venue = event["strVenue"] as? String
                let kickoff: Date? = (event["dateEvent"] as? String).flatMap(df.date(from:))

                return MatchStats(
                    homeTeam: homeTeam,
                    homeAbbr: abbreviate(homeTeam),
                    homeScore: homeScore,
                    awayTeam: awayTeam,
                    awayAbbr: abbreviate(awayTeam),
                    awayScore: awayScore,
                    lineScore: nil,
                    detail: round,
                    kickoff: kickoff,
                    competitionName: "NRL",
                    venue: venue,
                    lines: [],
                    raceLeaderboard: nil
                )
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func abbreviate(_ name: String) -> String {
        // "Newcastle Knights" → "NEW", "St. George Illawara Dragons" → "STG"
        let parts = name.split(separator: " ")
        if parts.count == 1, parts[0].count >= 3 { return String(parts[0].prefix(3)).uppercased() }
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    // MARK: - F1 race fetcher

    private static func fetchRace(config: SportConfig, publishedAt: Date) async -> MatchStats? {
        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd"
            return f
        }()
        // F1 highlight videos can be posted hours after the race; check the
        // race day + the two days before.
        for delta in [0, -1, -2, -3] {
            let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: delta, to: publishedAt) ?? publishedAt
            let dateStr = dayFormatter.string(from: day)
            if let stats = await fetchRaceForDate(config: config, dateStr: dateStr) {
                return stats
            }
        }
        return nil
    }

    private static func fetchRaceForDate(config: SportConfig, dateStr: String) async -> MatchStats? {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(config.espnSport)/\(config.espnLeague)/scoreboard?dates=\(dateStr)")!
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = root["events"] as? [[String: Any]],
                  let event = events.first else { return nil }

            guard let stype = (event["status"] as? [String: Any])?["type"] as? [String: Any],
                  (stype["completed"] as? Bool) ?? false else { return nil }

            let raceName = (event["name"] as? String) ?? "Race"
            let detail = (stype["detail"] as? String) ?? "Final"

            guard let competition = (event["competitions"] as? [[String: Any]])?.first,
                  let competitors = competition["competitors"] as? [[String: Any]] else { return nil }

            let entries: [MatchStats.RaceEntry] = competitors
                .sorted { (a, b) in
                    let ao = (a["order"] as? Int) ?? Int.max
                    let bo = (b["order"] as? Int) ?? Int.max
                    return ao < bo
                }
                .prefix(10)
                .map { c in
                    let athlete = c["athlete"] as? [String: Any]
                    let team = c["team"] as? [String: Any]
                    let pos = (c["order"] as? Int) ?? 0
                    return MatchStats.RaceEntry(
                        position: pos,
                        driverName: (athlete?["displayName"] as? String) ?? "?",
                        teamName: team?["displayName"] as? String,
                        timeOrGap: (c["score"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    )
                }

            guard !entries.isEmpty else { return nil }

            var kickoff: Date?
            if let iso = event["date"] as? String {
                kickoff = ISO8601DateFormatter().date(from: iso)
            }
            let venue = (competition["venue"] as? [String: Any])?["fullName"] as? String

            // Stuff race header into the homeTeam/competitionName slots so
            // existing StatsPanel infrastructure has something sensible to
            // render when raceLeaderboard isn't being shown (it always is for
            // F1, but defensive defaults).
            return MatchStats(
                homeTeam: raceName,
                homeAbbr: "",
                homeScore: 0,
                awayTeam: "",
                awayAbbr: "",
                awayScore: 0,
                lineScore: nil,
                detail: detail,
                kickoff: kickoff,
                competitionName: raceName,
                venue: venue,
                lines: [],
                raceLeaderboard: entries
            )
        } catch {
            return nil
        }
    }

    // MARK: - Internal

    private static func fetchAndMatch(config: SportConfig, dateStr: String, hints: TeamHints) async -> MatchStats? {
        let scoreboardURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(config.espnSport)/\(config.espnLeague)/scoreboard?dates=\(dateStr)")!
        do {
            var req = URLRequest(url: scoreboardURL)
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

                let homeScore = Int(home["score"] as? String ?? "0") ?? 0
                let awayScore = Int(away["score"] as? String ?? "0") ?? 0
                let detail = (stype["detail"] as? String) ?? "FT"
                let venue = (comp["venue"] as? [String: Any])?["fullName"] as? String

                // Tennis: per-set linescores ("6-4 7-5 6-3")
                let lineScore: String? = {
                    guard config.espnSport == "tennis" else { return nil }
                    let homeLines = (home["linescores"] as? [[String: Any]]) ?? []
                    let awayLines = (away["linescores"] as? [[String: Any]]) ?? []
                    let n = min(homeLines.count, awayLines.count)
                    guard n > 0 else { return nil }
                    var parts: [String] = []
                    for i in 0..<n {
                        let hv = Int(homeLines[i]["value"] as? Double ?? 0)
                        let av = Int(awayLines[i]["value"] as? Double ?? 0)
                        parts.append("\(hv)-\(av)")
                    }
                    return parts.joined(separator: " ")
                }()

                var kickoff: Date?
                if let iso = event["date"] as? String {
                    kickoff = ISO8601DateFormatter().date(from: iso)
                }

                let eventId = event["id"] as? String ?? ""
                let lines = await fetchStatLines(config: config, eventId: eventId, homeAbbr: teamAbbr(home), awayAbbr: teamAbbr(away))

                return MatchStats(
                    homeTeam: homeName,
                    homeAbbr: teamAbbr(home),
                    homeScore: homeScore,
                    awayTeam: awayName,
                    awayAbbr: teamAbbr(away),
                    awayScore: awayScore,
                    lineScore: lineScore,
                    detail: detail,
                    kickoff: kickoff,
                    competitionName: (event["league"] as? [String: Any])?["name"] as? String,
                    venue: venue,
                    lines: lines,
                    raceLeaderboard: nil
                )
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func fetchStatLines(config: SportConfig, eventId: String, homeAbbr: String, awayAbbr: String) async -> [MatchStats.StatLine] {
        guard !eventId.isEmpty else { return [] }
        let summaryURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(config.espnSport)/\(config.espnLeague)/summary?event=\(eventId)")!
        do {
            var req = URLRequest(url: summaryURL)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            guard let boxscore = root["boxscore"] as? [String: Any],
                  let teams = boxscore["teams"] as? [[String: Any]],
                  teams.count == 2 else { return [] }

            // Identify by team abbreviation match — relying on Swift dictionary
            // identity comparisons doesn't work (they're value types), so the
            // previous `!==` check was always returning the same dict for BOTH
            // sides and the panel showed identical stats for home and away.
            let firstAbbr = ((teams[0]["team"] as? [String: Any])?["abbreviation"] as? String) ?? ""
            let homeStats: [String: Any]
            let awayStats: [String: Any]
            if firstAbbr == homeAbbr {
                homeStats = teams[0]
                awayStats = teams[1]
            } else if firstAbbr == awayAbbr {
                homeStats = teams[1]
                awayStats = teams[0]
            } else {
                // Fall back to ESPN's `homeAway` field if abbreviations don't match.
                if (teams[0]["homeAway"] as? String) == "home" {
                    homeStats = teams[0]; awayStats = teams[1]
                } else {
                    homeStats = teams[1]; awayStats = teams[0]
                }
            }

            var homeByKey: [String: String] = [:]
            for s in (homeStats["statistics"] as? [[String: Any]]) ?? [] {
                if let n = s["name"] as? String, let v = s["displayValue"] as? String {
                    homeByKey[n] = v
                }
            }
            var awayByKey: [String: String] = [:]
            for s in (awayStats["statistics"] as? [[String: Any]]) ?? [] {
                if let n = s["name"] as? String, let v = s["displayValue"] as? String {
                    awayByKey[n] = v
                }
            }

            var lines: [MatchStats.StatLine] = []
            for (key, label, _) in config.stats {
                guard let h = homeByKey[key], let a = awayByKey[key] else { continue }
                let homeNum = Double(numericPart(h)) ?? 0
                let awayNum = Double(numericPart(a)) ?? 0
                let total = homeNum + awayNum
                let ratio: Double? = total > 0 ? max(0, min(1, homeNum / total)) : nil
                lines.append(.init(label: label, home: h, away: a, homeRatio: ratio))
            }
            return lines
        } catch {
            return []
        }
    }

    /// Extract a leading numeric portion from values like "45-92" / "12:34" / "58.4%"
    /// so we can compute a ratio for the bar visualization.
    private static func numericPart(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isNumber || ch == "." { out.append(ch) }
            else { break }
        }
        return out.isEmpty ? "0" : out
    }

    // MARK: - Team name parsing + matching (unchanged from prior)

    struct TeamHints {
        let homeTokens: [String]
        let awayTokens: [String]
    }

    private static func parseTeams(from title: String) -> TeamHints? {
        let pattern = #"\b([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3})\s+(?:v|vs|vs\.)\s+([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3})\b"#
        guard let r = title.range(of: pattern, options: .regularExpression) else { return nil }
        let chunk = String(title[r])
        let separators = [" v ", " vs ", " vs. "]
        for sep in separators {
            if let range = chunk.range(of: sep) {
                let left = String(chunk[..<range.lowerBound])
                let right = String(chunk[range.upperBound...])
                return TeamHints(homeTokens: tokenize(left), awayTokens: tokenize(right))
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
        // Tennis events carry the player under `athlete`, not `team`.
        if let athlete = competitor["athlete"] as? [String: Any] {
            if let name = athlete["displayName"] as? String { return name }
            if let name = athlete["fullName"] as? String { return name }
            if let last = athlete["lastName"] as? String { return last }
        }
        let team = competitor["team"] as? [String: Any]
        return (team?["displayName"] as? String)
            ?? (team?["name"] as? String)
            ?? (team?["abbreviation"] as? String)
            ?? "?"
    }

    private static func teamAbbr(_ competitor: [String: Any]) -> String {
        if let athlete = competitor["athlete"] as? [String: Any] {
            if let abbr = athlete["shortName"] as? String, !abbr.isEmpty { return abbr }
            if let last = athlete["lastName"] as? String, !last.isEmpty { return String(last.prefix(3)).uppercased() }
        }
        let team = competitor["team"] as? [String: Any]
        return (team?["abbreviation"] as? String) ?? ""
    }
}
