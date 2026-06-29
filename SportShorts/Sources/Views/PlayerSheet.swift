import SwiftUI
import WebKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var skipRanges: [[Double]] = []
    @State private var skipRangesLoaded = false
    @State private var matchStats: MatchStats?
    @State private var revealStats = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Player block: WKWebView underneath, black overlay above to mask YouTube
                // chrome (related videos / comments / description — which may contain
                // spoilers).
                GeometryReader { geo in
                    let videoHeight = min(geo.size.height * 0.45, geo.size.width * 9 / 16)
                    ZStack(alignment: .top) {
                        YouTubeBrowserView(
                            videoId: item.id,
                            skipRanges: skipRanges,
                            skipRangesLoaded: skipRangesLoaded
                        )
                        VStack(spacing: 0) {
                            Color.clear.frame(height: videoHeight)
                            Color.black
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color.black)

                // Stats panel (football only, when ESPN has the match)
                if let stats = matchStats {
                    StatsPanel(stats: stats, revealed: $revealStats)
                        .frame(maxHeight: 360)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) { NavTitleBlock(item: item) }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: item.watchURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            skipRanges = await SponsorBlock.fetchSkipRanges(videoId: item.id)
            skipRangesLoaded = true
        }
        .task {
            if MatchStatsService.supports(competitionId: item.competitionId) {
                matchStats = await MatchStatsService.fetchMatch(
                    title: item.title,
                    publishedAt: item.publishedAt,
                    competitionId: item.competitionId
                )
            }
        }
    }
}

// MARK: - Nav title

private struct NavTitleBlock: View {
    let item: VideoItem
    var body: some View {
        VStack(spacing: 1) {
            Text(matchupOrTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 5) {
                Image(systemName: item.sportIcon)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                Text(item.competitionLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: 240)
    }

    private var matchupOrTitle: String {
        let pattern = #"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\s+v(?:s|s\.)?\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\b"#
        if let r = item.title.range(of: pattern, options: .regularExpression) {
            return String(item.title[r])
        }
        return item.title
    }
}

// MARK: - WebView

struct YouTubeBrowserView: UIViewRepresentable {
    let videoId: String
    let skipRanges: [[Double]]
    let skipRangesLoaded: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userContent = WKUserContentController()
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        installAdBlocker(on: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if skipRangesLoaded {
            let rangesJSON = (try? String(data: JSONSerialization.data(withJSONObject: skipRanges), encoding: .utf8)) ?? "[]"
            let js = """
            (function() {
              if (window.__sportshortsSponsorBlockInstalled) return;
              window.__sportshortsSponsorBlockInstalled = true;
              const SKIP_RANGES = \(rangesJSON);
              if (!SKIP_RANGES.length) return;
              setInterval(function() {
                try {
                  const v = document.querySelector('video');
                  if (!v) return;
                  const t = v.currentTime;
                  for (const r of SKIP_RANGES) {
                    const [start, end] = r;
                    if (t >= start && t < end - 0.2) {
                      v.currentTime = end;
                      return;
                    }
                  }
                } catch (e) {}
              }, 300);
            })();
            """
            webView.evaluateJavaScript(js)
        }
    }

    private func installAdBlocker(on webView: WKWebView) {
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": #".*doubleclick\.net.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*googleadservices\.com.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*googlesyndication\.com.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*adservice\.google\..*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*google-analytics\.com.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*youtube\.com\/api\/stats\/ads.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*youtube\.com\/pagead\/.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*\/get_midroll_info.*"#], "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*\/ad_companion.*"#], "action": ["type": "block"]],
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
}

// MARK: - Match stats panel

struct StatsPanel: View {
    let stats: MatchStats
    @Binding var revealed: Bool

    var body: some View {
        VStack(spacing: 0) {
            if revealed {
                revealedContent
            } else {
                spoilerCurtain
            }
        }
        .background(
            LinearGradient(colors: [Color.black, Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
        )
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
            VStack(spacing: 16) {
                scoreBlock
                Divider().background(.white.opacity(0.15))
                statsLines
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var scoreBlock: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 2) {
                Text(stats.homeTeam).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(stats.homeAbbr).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("\(stats.homeScore)  –  \(stats.awayScore)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(stats.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(spacing: 2) {
                Text(stats.awayTeam).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(stats.awayAbbr).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
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
