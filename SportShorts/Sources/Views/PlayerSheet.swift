import SwiftUI
import WebKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var unrecoverable = false
    @State private var watchdog: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                // Mobile YouTube site in a WKWebView — not the iframe-embed API.
                // Publishers can disable iframe embedding (Error 152-4), but the
                // full YouTube site usually still plays.
                MobileYouTubeWebView(
                    videoId: item.id,
                    onLoaded: {
                        loaded = true
                        watchdog?.cancel()
                    },
                    onUnplayable: { unrecoverable = true }
                )
                .ignoresSafeArea(edges: .bottom)
                .opacity(loaded && !unrecoverable ? 1 : 0)

                if !unrecoverable {
                    OverlayBanner(item: item)
                        .padding(.top, 8)
                        .padding(.horizontal, 12)
                        .opacity(loaded ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: loaded)
                }

                if unrecoverable {
                    embedFailedView
                } else if !loaded {
                    LiquidGlassLoader(title: item.title)
                }
            }
            .navigationTitle(item.competition)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { startWatchdog() }
        .onDisappear { watchdog?.cancel() }
    }

    private func startWatchdog() {
        watchdog = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
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
                Text("The publisher has restricted in-app playback for this video. Watch it on YouTube and come back when you're done.")
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
        .padding(.bottom, 80)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: item.watchURL) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Title-derived overlay banner

private struct OverlayBanner: View {
    let item: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sportIcon)
                .font(.headline)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.competition)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(matchupOrTitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer()
            Text(item.publishedAt, format: .relative(presentation: .numeric))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }

    private var sportIcon: String {
        switch item.sport.lowercased() {
        case let s where s.contains("rugby league"): return "shield.fill"
        case let s where s.contains("rugby union"): return "shield.fill"
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

    /// Best-effort: extract "Team A v Team B" out of the title and present that.
    private var matchupOrTitle: String {
        let pattern = #"\b[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\s+v(?:s|s\.)?\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3}\b"#
        if let r = item.title.range(of: pattern, options: .regularExpression) {
            return String(item.title[r])
        }
        return item.title
    }
}

// MARK: - Mobile YouTube WebView

/// Loads `m.youtube.com/watch?v=<id>` directly inside a WKWebView. Many publisher
/// "embed disabled" restrictions only apply to iframe embeds, not the full mobile site.
/// We inject CSS to hide YouTube's navigation chrome / suggested videos so the user
/// mostly sees just the player.
struct MobileYouTubeWebView: UIViewRepresentable {
    let videoId: String
    let onLoaded: () -> Void
    let onUnplayable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded, onUnplayable: onUnplayable)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        // Inject CSS that strips YouTube's chrome — keeps the player visible and hides
        // navigation, related videos, comments, "up next" panels.
        let css = """
        ytm-mobile-topbar-renderer,
        ytm-pivot-bar-renderer,
        ytm-search-bar,
        ytm-app-header-renderer,
        ytm-engagement-panel,
        ytm-watch-metadata,
        ytm-channel-bar-renderer,
        ytm-item-section-renderer,
        ytm-video-with-context-renderer,
        ytm-shorts-shelf-renderer,
        ytm-rich-shelf-renderer,
        ytm-section-list-renderer,
        ytm-feed-filter-chip-bar-renderer,
        ytm-companion-slot,
        .floating-button-wrap-bottom,
        .mobile-topbar-header-content,
        .item-section,
        .single-column-watch-next-modern-panels,
        #masthead-container,
        #scroll-container,
        ytm-button-renderer[button-renderer][role=button] { display:none !important; }

        body, html { background:#000 !important; }
        ytd-player, ytm-player, .player-container, #player { background:#000 !important; }
        """
        let cssScript = WKUserScript(
            source: "var s=document.createElement('style');s.textContent=`\(css)`;document.documentElement.appendChild(s);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )

        let userContent = WKUserContentController()
        userContent.addUserScript(cssScript)
        userContent.add(context.coordinator, name: "playerEvent")

        // JS that polls the DOM for YouTube error containers and reports back if the
        // video can't be played.
        let errorWatchScript = WKUserScript(
            source: errorWatchJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContent.addUserScript(errorWatchScript)

        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))
    }

    private var errorWatchJS: String {
        """
        (function() {
          let reported = false;
          function check() {
            if (reported) return;
            // YouTube renders various error containers; look for any of them.
            const errSelectors = [
              '.ytp-error', '.ytm-player-error', '.player-unavailable',
              'ytm-player-error-message-renderer', 'ytm-alert-renderer',
              '.message-renderer'
            ];
            for (const sel of errSelectors) {
              const el = document.querySelector(sel);
              if (el && el.offsetParent !== null) {
                const txt = (el.textContent || '').toLowerCase();
                if (txt.includes('unavailable') || txt.includes("can't play") || txt.includes("error") || txt.length > 10) {
                  reported = true;
                  if (window.webkit && window.webkit.messageHandlers.playerEvent) {
                    window.webkit.messageHandlers.playerEvent.postMessage({type: 'error'});
                  }
                  return;
                }
              }
            }
            // Heuristic: a successfully loaded watch page has a video element
            const video = document.querySelector('video');
            if (video) {
              if (window.webkit && window.webkit.messageHandlers.playerEvent) {
                window.webkit.messageHandlers.playerEvent.postMessage({type: 'ready'});
              }
            }
          }
          // Initial pass + an interval to catch async error renders.
          setInterval(check, 800);
          setTimeout(check, 200);
        })();
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
            case "error":
                onUnplayable()
            default:
                break
            }
        }
    }
}

/// Loading view in the app's Liquid Glass theme.
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
