import SwiftUI
import WebKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var skipRanges: [[Double]] = []
    @State private var skipRangesLoaded = false
    @State private var matchStats: MatchStats?
    @State private var revealStats = false
    @State private var unplayable = false

    var body: some View {
        VStack(spacing: 0) {
            PlayerHeader(item: item, onClose: { dismiss() })

            ZStack {
                Color.black
                if unplayable {
                    embedFailedView.padding()
                } else {
                    IFramePlayer(
                        videoId: item.id,
                        skipRanges: skipRanges,
                        skipRangesLoaded: skipRangesLoaded,
                        onUnplayable: { unplayable = true }
                    )
                }
            }
            .aspectRatio(16/9, contentMode: .fit)

            ChannelFollowRow(
                channelId: item.channelId,
                channelTitle: item.channelTitle,
                videoURL: item.watchURL,
                fallbackName: item.channelTitle
            )

            if let stats = matchStats {
                StatsPanel(stats: stats, revealed: $revealStats)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                LinearGradient(colors: [Color.black, Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            skipRanges = await SponsorBlock.fetchSkipRanges(videoId: item.id)
            skipRangesLoaded = true
        }
        .task {
            if let compId = item.competitionId,
               MatchStatsService.supports(competitionId: compId) {
                matchStats = await MatchStatsService.fetchMatch(
                    title: item.title,
                    publishedAt: item.publishedAt,
                    competitionId: compId
                )
            }
        }
    }

    private var embedFailedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.55))
            Text("Publisher disabled in-app playback")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button {
                    UIApplication.shared.open(item.watchURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Open in YouTube")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                if session.channel(byId: item.channelId) != nil,
                   session.isFollowing(channelId: item.channelId) {
                    Button {
                        session.setFollowing(false, forChannelId: item.channelId)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.slash")
                            Text("Hide channel")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
    }
}

// MARK: - Custom player header

/// Tight header that replaces the NavigationStack toolbar. SwiftUI's
/// navigation chrome adds ~30pt of slack below the title bar even with
/// inline placement; this gives us the X / title / share row with no
/// extra padding so the video sits flush against it.
private struct PlayerHeader: View {
    let item: VideoItem
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text(matchupOrTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: item.sportIcon)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(item.competitionLabel ?? item.sportLabel)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: 240)

            Spacer(minLength: 0)

            ShareLink(item: item.watchURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black)
    }

    private var matchupOrTitle: String {
        let pattern = #"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\s+v(?:s|s\.)?\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\b"#
        if let r = item.title.range(of: pattern, options: .regularExpression) {
            return String(item.title[r])
        }
        return item.title
    }
}

// MARK: - Custom-HTML iframe player

/// Player iframe that loads via a CodePen-hosted YouTube proxy. CodePen's
/// `cdpn.io` domain is on most publishers' "allowed embed" lists, which
/// bypasses the "Video unavailable / Watch on YouTube" iframe restrictions
/// that direct youtube.com embeds hit.
/// (Original pen: https://codepen.io/brownsugar/pen/oNPzxKo )
///
/// Trade-off: we lose SponsorBlock skip integration. SponsorBlock requires
/// access to the YouTube IFrame Player API, which sits inside a cross-origin
/// nested iframe we can't reach into from this WebView. SponsorBlock ranges
/// are still fetched and could be reattached via postMessage in a follow-up.
struct IFramePlayer: UIViewRepresentable {
    let videoId: String
    let skipRanges: [[Double]]
    let skipRangesLoaded: Bool
    let onUnplayable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onUnplayable: onUnplayable) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "playerEvent")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .black
        installAdBlocker(on: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastVideoId != videoId {
            context.coordinator.lastVideoId = videoId
            // Wrap the CodePen proxy iframe in a custom HTML host so we can pass the
            // full `allow` attribute set — accelerometer + gyroscope are what give
            // the YouTube player permission to auto-rotate to landscape full-screen
            // when the device turns.
            // Drop mute=1 so the first tap on YouTube's play button gives sound
            // from frame 0 instead of the user needing a second tap on
            // "tap to unmute". iOS Safari blocks unmuted autoplay regardless,
            // so the video will appear paused on a thumbnail until the user
            // taps play — that tap is the user gesture iOS requires.
            let cdpnURL = "https://cdpn.io/pen/debug/oNPzxKo?v=\(videoId)&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3&fs=1"
            let html = """
            <!DOCTYPE html>
            <html><head>
              <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
              <style>
                html, body { margin:0; padding:0; background:#000; width:100vw; height:100vh; overflow:hidden; touch-action:manipulation; }
                iframe { border:0; width:100%; height:100%; background:#000; display:block; }
              </style>
            </head><body>
              <iframe
                src="\(cdpnURL)"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
                allowfullscreen="allowfullscreen"
              ></iframe>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: URL(string: "https://codepen.io"))
        }
    }

    private func installAdBlocker(on webView: WKWebView) {
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": #".*doubleclick\.net.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*googleadservices\.com.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*googlesyndication\.com.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*google-analytics\.com.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*youtube\.com\/api\/stats\/ads.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*youtube\.com\/pagead\/.*"#], "action": ["type": "block"]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "SportShortsAdBlock",
            encodedContentRuleList: json
        ) { list, _ in
            if let list { webView.configuration.userContentController.add(list) }
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onUnplayable: () -> Void
        var lastVideoId: String?

        init(onUnplayable: @escaping () -> Void) { self.onUnplayable = onUnplayable }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "unplayable" { onUnplayable() }
        }
    }
}

// MARK: - Channel follow row

/// Sits below the video, above the stats panel. Shows the channel @handle and a
/// one-tap toggle to follow / unfollow. Mainly there so a user who hits a
/// YouTube geoblock or "Video unavailable" can quickly drop the source from
/// their feed without leaving the player.
private struct ChannelFollowRow: View {
    let channelId: String
    let channelTitle: String
    let videoURL: URL
    let fallbackName: String
    @Environment(AppSession.self) private var session

    var body: some View {
        let ch = session.channel(byId: channelId)
        let visible = session.isFollowing(channelId: channelId)
        let canHide = ch != nil

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ch?.name ?? fallbackName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(ch?.displayHandle ?? "@" + fallbackName.lowercased().replacingOccurrences(of: " ", with: ""))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    UIApplication.shared.open(videoURL)
                } label: {
                    Label("Open in YouTube", systemImage: "arrow.up.right.square")
                }
                if canHide {
                    if visible {
                        Button(role: .destructive) {
                            session.setFollowing(false, forChannelId: channelId)
                        } label: {
                            Label("Hide \(ch?.displayHandle ?? "channel")", systemImage: "eye.slash")
                        }
                    } else {
                        Button {
                            session.setFollowing(true, forChannelId: channelId)
                        } label: {
                            Label("Unhide \(ch?.displayHandle ?? "channel")", systemImage: "eye")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
    }
}

// MARK: - Match stats panel

struct StatsPanel: View {
    let stats: MatchStats
    @Binding var revealed: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color.black, Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                if revealed {
                    revealedContent
                } else {
                    spoilerCurtain
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var spoilerCurtain: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
            Text("Match stats available")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Tapping below will reveal the score and key stats — spoilers ahead.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button { withAnimation(.easeOut(duration: 0.2)) { revealed = true } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                    Text("Show stats")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
    }

    private var revealedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(spacing: 10) {
                        if stats.raceLeaderboard != nil {
                            raceBody
                        } else {
                            statsLines
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                } header: {
                    VStack(spacing: 12) {
                        if let entries = stats.raceLeaderboard {
                            raceHeader(entries: entries)
                        } else {
                            scoreBlock
                        }
                        Rectangle().fill(Color.white.opacity(0.15)).frame(height: 0.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func raceHeader(entries: [MatchStats.RaceEntry]) -> some View {
        VStack(spacing: 4) {
            Text(stats.competitionName ?? "Race")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(stats.detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            if let winner = entries.first {
                Text("Winner: \(winner.driverName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var raceBody: some View {
        if let entries = stats.raceLeaderboard {
            VStack(spacing: 8) {
                ForEach(entries, id: \.self) { entry in
                    HStack(alignment: .center, spacing: 12) {
                        Text("\(entry.position)")
                            .font(.callout.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 28, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.driverName)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                            if let team = entry.teamName, !team.isEmpty {
                                Text(team)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        Spacer()
                        if let gap = entry.timeOrGap {
                            Text(gap)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var scoreBlock: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                VStack(spacing: 2) {
                    Text(stats.homeTeam)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(stats.homeAbbr).font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("\(stats.homeScore)  –  \(stats.awayScore)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .layoutPriority(1)
                    Text(stats.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 2) {
                    Text(stats.awayTeam)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(stats.awayAbbr).font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
            if let lineScore = stats.lineScore {
                Text(lineScore)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var statsLines: some View {
        VStack(spacing: 10) {
            ForEach(stats.lines, id: \.self) { line in
                VStack(spacing: 4) {
                    HStack {
                        Text(line.home)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(line.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(line.away)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    if let ratio = line.homeRatio {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: max(2, geo.size.width * ratio))
                                Capsule().fill(Color.red.opacity(0.7))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }
}
