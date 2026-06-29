import SwiftUI
import WebKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var unrecoverable = false
    @State private var watchdog: Task<Void, Never>?
    @State private var skipRanges: [[Double]] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                IFramePlayerView(
                    videoId: item.id,
                    skipRanges: skipRanges,
                    onLoaded: { loaded = true; watchdog?.cancel() },
                    onUnplayable: { unrecoverable = true }
                )
                .ignoresSafeArea(edges: .bottom)
                .opacity(loaded && !unrecoverable ? 1 : 0)

                if unrecoverable {
                    embedFailedView
                } else if !loaded {
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
            // Fire-and-forget: fetch SponsorBlock segments in parallel with the iframe load.
            skipRanges = await SponsorBlock.fetchSkipRanges(videoId: item.id)
        }
        .onAppear { startWatchdog() }
        .onDisappear { watchdog?.cancel() }
    }

    private func startWatchdog() {
        watchdog = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled, !loaded {
                await MainActor.run { unrecoverable = true }
            }
        }
    }

    private var embedFailedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.55))
            VStack(spacing: 6) {
                Text("This one needs YouTube")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("The publisher has restricted in-app playback for this video. Watch on YouTube and come back.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                UIApplication.shared.open(item.watchURL)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Watch on YouTube")
                        .font(.headline)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .tint(.white)
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

// MARK: - Custom-HTML iframe player

/// Hosts a hand-built HTML page that contains a YouTube iframe sized to fill the
/// WKWebView. Uses the YouTube IFrame Player API for state + error events. When
/// SponsorBlock skip ranges are supplied, JS monitors the player's current time
/// and seeks past any matching segment automatically.
struct IFramePlayerView: UIViewRepresentable {
    let videoId: String
    let skipRanges: [[Double]]
    let onLoaded: () -> Void
    let onUnplayable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded, onUnplayable: onUnplayable)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "playerEvent")
        config.userContentController = userContent
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let rangesJSON = (try? String(data: JSONSerialization.data(withJSONObject: skipRanges), encoding: .utf8)) ?? "[]"
        webView.loadHTMLString(html(rangesJSON: rangesJSON), baseURL: URL(string: "https://www.youtube.com"))
    }

    private func html(rangesJSON: String) -> String {
        """
        <!DOCTYPE html>
        <html><head>
          <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
          <style>
            html, body {
              margin: 0; padding: 0;
              background: #000;
              width: 100vw; height: 100vh;
              overflow: hidden;
              touch-action: manipulation;
            }
            #player-wrap {
              position: absolute; inset: 0;
              display: flex; align-items: center; justify-content: center;
            }
            #player {
              width: 100vw; height: 100vh;
              border: 0; background: #000;
            }
          </style>
        </head>
        <body>
          <div id="player-wrap"><div id="player"></div></div>
          <script>
            const SKIP_RANGES = \(rangesJSON);
            let player;
            let monitor;

            function post(payload) {
              try { window.webkit.messageHandlers.playerEvent.postMessage(payload); } catch (e) {}
            }

            const tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            document.head.appendChild(tag);

            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                width: '100%',
                height: '100%',
                videoId: '\(videoId)',
                playerVars: {
                  autoplay: 1,
                  playsinline: 1,
                  rel: 0,
                  modestbranding: 1,
                  iv_load_policy: 3,
                  fs: 1,
                  controls: 1
                },
                events: {
                  onReady: function(e) {
                    post({type:'ready'});
                    // Try to play (autoplay isn't always honoured)
                    try { e.target.playVideo(); } catch (err) {}
                    // Start SponsorBlock monitor
                    if (SKIP_RANGES.length > 0) {
                      monitor = setInterval(() => {
                        try {
                          const t = e.target.getCurrentTime();
                          for (const r of SKIP_RANGES) {
                            const [start, end] = r;
                            if (t >= start && t < end - 0.2) {
                              e.target.seekTo(end, true);
                              break;
                            }
                          }
                        } catch (err) {}
                      }, 250);
                    }
                  },
                  onError: function(e) {
                    // 2 = invalid parameter; 5 = HTML5 player error;
                    // 100 = video not found; 101 = embed disabled; 150 = embed disabled (alt).
                    if (e.data === 100 || e.data === 101 || e.data === 150) {
                      post({type: 'unplayable', code: e.data});
                    } else {
                      post({type: 'error', code: e.data});
                    }
                  }
                }
              });
            }
          </script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onLoaded: () -> Void
        let onUnplayable: () -> Void
        private var loadedReported = false

        init(onLoaded: @escaping () -> Void, onUnplayable: @escaping () -> Void) {
            self.onLoaded = onLoaded
            self.onUnplayable = onUnplayable
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                if !loadedReported {
                    loadedReported = true
                    onLoaded()
                }
            case "unplayable":
                onUnplayable()
            default:
                break
            }
        }
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
