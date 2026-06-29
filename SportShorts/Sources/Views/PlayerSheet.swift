import SwiftUI
import WebKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var embedFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                YouTubeIframeView(
                    videoId: item.id,
                    onLoaded: { loaded = true },
                    onEmbedError: { embedFailed = true }
                )
                .ignoresSafeArea(edges: .bottom)
                .opacity(loaded && !embedFailed ? 1 : 0)

                if embedFailed {
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
    }

    private var embedFailedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.55))
            VStack(spacing: 6) {
                Text("Can't play this one here")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("The publisher has restricted in-app playback for this video. You can still watch it on YouTube.")
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

/// YouTube iframe player with JS bridge so we can detect "embedding disabled" errors
/// (YouTube iframe API onError codes 101 and 150) and tell SwiftUI to swap in a
/// "Watch on YouTube" fallback.
struct YouTubeIframeView: UIViewRepresentable {
    let videoId: String
    let onLoaded: () -> Void
    let onEmbedError: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded, onEmbedError: onEmbedError)
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
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html>
        <html><head>
          <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
          <style>html,body{margin:0;padding:0;background:#000;height:100%;width:100%;overflow:hidden}
          #player{position:absolute;inset:0;background:#000}</style>
        </head><body>
          <div id="player"></div>
          <script>
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            var firstScriptTag = document.getElementsByTagName('script')[0];
            firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
            var player;
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(videoId)',
                playerVars: {
                  'autoplay': 1, 'playsinline': 1, 'rel': 0,
                  'modestbranding': 1, 'iv_load_policy': 3, 'fs': 1
                },
                events: {
                  'onReady': function(e) {
                    if (window.webkit && window.webkit.messageHandlers.playerEvent) {
                      window.webkit.messageHandlers.playerEvent.postMessage({type: 'ready'});
                    }
                  },
                  'onError': function(e) {
                    if (window.webkit && window.webkit.messageHandlers.playerEvent) {
                      window.webkit.messageHandlers.playerEvent.postMessage({type: 'error', code: e.data});
                    }
                  }
                }
              });
            }
          </script>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onLoaded: () -> Void
        let onEmbedError: () -> Void
        init(onLoaded: @escaping () -> Void, onEmbedError: @escaping () -> Void) {
            self.onLoaded = onLoaded
            self.onEmbedError = onEmbedError
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Fallback in case the JS onReady event doesn't arrive (e.g. video that
            // can be played but where the iframe API errors silently).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onLoaded()
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                onLoaded()
            case "error":
                // YouTube iframe error codes:
                //  2  = invalid parameter
                //  5  = HTML5 player error
                //  100 = video not found
                //  101 = embed disabled by uploader
                //  150 = embed disabled by uploader (different rights flavour)
                let code = body["code"] as? Int ?? -1
                if code == 101 || code == 150 || code == 100 {
                    onEmbedError()
                }
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
