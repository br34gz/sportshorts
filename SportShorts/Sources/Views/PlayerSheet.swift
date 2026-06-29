import SwiftUI
import WebKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var skipRanges: [[Double]] = []
    @State private var skipRangesLoaded = false

    var body: some View {
        NavigationStack {
            YouTubeBrowserView(videoId: item.id, skipRanges: skipRanges, skipRangesLoaded: skipRangesLoaded)
                .ignoresSafeArea(edges: .bottom)
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
    }
}

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

/// WKWebView loading m.youtube.com directly. SponsorBlock segments (when loaded)
/// drive a passive currentTime → seek loop. Ad blocker is a content rule list.
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

        installAdBlocker(on: webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        // SponsorBlock skip script: re-evaluate once skipRanges arrive (passive seek-only).
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

    /// Compile a small content rule list to block common ad-network endpoints.
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
