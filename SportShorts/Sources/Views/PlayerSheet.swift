import SwiftUI
import WebKit

/// "Browser-style" YouTube viewer: a WKWebView that loads the actual YouTube watch
/// URL and stays out of YouTube's way layout-wise. We inject two helpers on top:
///   1. SponsorBlock — auto-seeks past community-flagged sponsor / intro / outro
///      segments returned by the SponsorBlock community API.
///   2. Ad-skip — clicks YouTube's "Skip ad" button as soon as it appears.
/// We also install a WKContentRuleList that blocks common ad-network domains
/// (doubleclick, googleads, etc) at the network level.
struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var skipRanges: [[Double]] = []
    @State private var loadingSkipRanges = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if !loadingSkipRanges {
                    YouTubeBrowserView(videoId: item.id, skipRanges: skipRanges)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    LiquidGlassLoader(title: item.title)
                }
            }
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
            loadingSkipRanges = false
        }
    }
}

// MARK: - Nav title block

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

// MARK: - WKWebView "browser" loading YouTube directly

struct YouTubeBrowserView: UIViewRepresentable {
    let videoId: String
    let skipRanges: [[Double]]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        let userContent = WKUserContentController()
        let rangesJSON = (try? String(data: JSONSerialization.data(withJSONObject: skipRanges), encoding: .utf8)) ?? "[]"

        // SponsorBlock-only helper. NO ad-skip clicks, NO automated mute/unmute —
        // earlier versions of those handlers were interfering with iOS's
        // gesture-tracking for media playback. Now we just observe currentTime
        // and seek past community-flagged segments. Everything else is YouTube's job.
        let helperJS = WKUserScript(
            source: """
            (function() {
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
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(helperJS)

        config.userContentController = userContent

        // Network-level ad blocking via WKContentRuleList. Applied async at first
        // load — falls back gracefully if compilation fails.
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        installAdBlocker(on: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    private func installAdBlocker(on webView: WKWebView) {
        // Minimal block list — common ad/tracking endpoints used by YouTube and others.
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": #".*doubleclick\.net.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*googleadservices\.com.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*googlesyndication\.com.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*adservice\.google\..*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*google-analytics\.com.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*youtube\.com\/api\/stats\/ads.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*youtube\.com\/pagead\/.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*\/get_midroll_info.*"#],
             "action": ["type": "block"]],
            ["trigger": ["url-filter": #".*\/ad_companion.*"#],
             "action": ["type": "block"]],
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        // Optional: trap external links so navigation away from YouTube opens externally.
    }
}

// MARK: - Tap-to-play overlay (user-gesture relay)

/// Full-bleed transparent button that the user taps once to satisfy iOS's
/// "audio playback requires a user gesture" rule. On tap, calls the closure
/// (which invokes `video.play()` in JS) and removes itself.
struct TapToPlayOverlay: View {
    let onTap: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 88, height: 88)
                        .scaleEffect(pulse ? 1.05 : 0.95)
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        .frame(width: 88, height: 88)
                    Image(systemName: "play.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                        .offset(x: 3)
                }
                Text("Tap to play")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("(unlocks sound & playback)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
        .transition(.opacity)
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Glass loader

struct LiquidGlassLoader: View {
    let title: String
    @State private var rotate = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.3), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 4)
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(rotate ? 360 : 0))

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.08 : 0.94)

                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            VStack(spacing: 4) {
                Text("Loading highlights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { rotate = true }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
