import SwiftUI
import WebKit

// MARK: - Player sheet (rewritten clean from scratch in v1.3)
//
// The premise is deliberately small: a sheet with a navigation bar (matchup title,
// X to dismiss, share button) and a WKWebView that loads the actual YouTube mobile
// watch URL. No injected JavaScript. No content rule list. No SwiftUI overlays.
// No tap-to-play prompts. The only thing the app does is open the URL — YouTube's
// own page handles every other concern, exactly like Mobile Safari would.
//
// Once playback is confirmed working, SponsorBlock / ad-skip / etc can be layered
// back in, isolated and tested individually.

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlainYouTubeWebView(videoId: item.id)
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
                Image(systemName: sportIcon)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                Text(item.competition)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: 240)
    }

    private var sportIcon: String {
        switch item.sport.lowercased() {
        case let s where s.contains("rugby"): return "shield.fill"
        case let s where s.contains("rules"): return "sportscourt.fill"
        case let s where s.contains("football"): return "soccerball"
        case let s where s.contains("cricket"): return "baseball.fill"
        case let s where s.contains("tennis"): return "tennis.racket"
        case let s where s.contains("basketball"): return "basketball.fill"
        case let s where s.contains("hockey"): return "hockey.puck.fill"
        case let s where s.contains("baseball"): return "baseball.fill"
        case let s where s.contains("motorsport"): return "flag.checkered.2.crossed"
        case let s where s.contains("american"): return "football.fill"
        case let s where s.contains("gaelic"): return "shield.fill"
        default: return "sportscourt.fill"
        }
    }

    private var matchupOrTitle: String {
        let pattern = #"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\s+v(?:s|s\.)?\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\b"#
        if let r = item.title.range(of: pattern, options: .regularExpression) {
            return String(item.title[r])
        }
        return item.title
    }
}

// MARK: - Plain WKWebView

/// Pure WKWebView wrapper — opens m.youtube.com/watch?v=… and gets out of the way.
/// No JavaScript injection, no content blocker, no special UA, no scroll lock.
/// This is the minimum viable surface to test whether WKWebView+YouTube plays at all.
struct PlainYouTubeWebView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
