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

                if unrecoverable {
                    embedFailedView
                } else if !loaded {
                    LiquidGlassLoader(title: item.title)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitleBlock(item: item)
                }
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

// MARK: - Nav-bar title block (matchup + competition)

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

        // Inject CSS that strips YouTube's chrome AND locks the page in a non-scrollable
        // state so it stays fixed on the player.
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
        ytm-watch-below-the-player-area,
        .floating-button-wrap-bottom,
        .mobile-topbar-header-content,
        .item-section,
        .single-column-watch-next-modern-panels,
        ytm-modal-with-title-and-button-renderer,
        ytm-comments-entry-point-header-renderer,
        ytm-related-video-list-renderer,
        ytm-rich-section-renderer,
        ytm-info-panel-content-renderer,
        #masthead-container,
        #related,
        #scroll-container,
        ytm-button-renderer[button-renderer][role=button] { display:none !important; }

        html, body {
          background:#000 !important;
          margin:0 !important; padding:0 !important;
          overflow:hidden !important;
          height:100% !important; width:100% !important;
          position:fixed !important;
          touch-action: none !important;
          -webkit-user-select: none !important;
        }
        ytd-player, ytm-player, .player-container, #player {
          background:#000 !important;
          position:fixed !important; inset:0 !important;
        }
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
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
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
          let reportedReady = false;
          let attemptedPlay = false;
          let unmutedOnTap = false;

          // Force the YouTube player container to fill the viewport. YouTube's mobile
          // layout otherwise sizes the player to a 16:9 slice in the middle of the page.
          function fitPlayer() {
            const candidates = [
              '#movie_player',
              'ytm-player',
              '.html5-video-player',
              '.player-container',
              'ytm-watch-flexy-player-container',
              'ytm-watch-flexy'
            ];
            for (const sel of candidates) {
              const el = document.querySelector(sel);
              if (el) {
                el.style.setProperty('position', 'fixed', 'important');
                el.style.setProperty('top', '0', 'important');
                el.style.setProperty('left', '0', 'important');
                el.style.setProperty('right', '0', 'important');
                el.style.setProperty('bottom', '0', 'important');
                el.style.setProperty('width', '100vw', 'important');
                el.style.setProperty('height', '100vh', 'important');
                el.style.setProperty('max-width', 'none', 'important');
                el.style.setProperty('max-height', 'none', 'important');
                el.style.setProperty('z-index', '99999', 'important');
                el.style.setProperty('background', '#000', 'important');
              }
            }
            // The video element itself: fill its container.
            const v = document.querySelector('video');
            if (v) {
              v.style.setProperty('width', '100vw', 'important');
              v.style.setProperty('height', '100vh', 'important');
              v.style.setProperty('object-fit', 'contain', 'important');
              v.style.setProperty('background', '#000', 'important');
            }
          }

          function tryPlay() {
            if (attemptedPlay) return;
            const video = document.querySelector('video');
            if (!video) return;
            attemptedPlay = true;
            const p = video.play();
            if (p && p.catch) {
              p.catch(() => {
                const btn = document.querySelector('.ytp-large-play-button, .ytm-play-button, button[aria-label*="Play" i], .ytp-play-button');
                if (btn) btn.click();
              });
            }
          }

          // On the first user tap anywhere in the page, unmute.
          document.addEventListener('click', function() {
            if (unmutedOnTap) return;
            const v = document.querySelector('video');
            if (v) { v.muted = false; unmutedOnTap = true; }
          }, true);

          function check() {
            const errSelectors = [
              '.ytp-error', '.ytm-player-error', '.player-unavailable',
              'ytm-player-error-message-renderer', 'ytm-alert-renderer'
            ];
            for (const sel of errSelectors) {
              const el = document.querySelector(sel);
              if (el && el.offsetParent !== null) {
                const txt = (el.textContent || '').toLowerCase();
                if (txt.includes('unavailable') || txt.includes("can't play") || txt.includes("error")) {
                  if (window.webkit && window.webkit.messageHandlers.playerEvent) {
                    window.webkit.messageHandlers.playerEvent.postMessage({type: 'error'});
                  }
                  return;
                }
              }
            }
            fitPlayer();
            const video = document.querySelector('video');
            if (video) {
              if (!reportedReady) {
                reportedReady = true;
                if (window.webkit && window.webkit.messageHandlers.playerEvent) {
                  window.webkit.messageHandlers.playerEvent.postMessage({type: 'ready'});
                }
              }
              tryPlay();
            }
          }
          setInterval(check, 400);
          setTimeout(check, 100);
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
