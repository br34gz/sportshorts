import SwiftUI
import AVKit
import WebKit
import YouTubeKit

enum PlayerMode: Equatable {
    case loading
    case avplayer(AVPlayer)
    case webview                                    // YouTube iframe fallback
    case error(String)
}

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlayerMode = .loading
    @State private var statusObserver: NSKeyValueObservation?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(item.competition)
                .toolbarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await loadStream() }
        .onDisappear {
            statusObserver?.invalidate()
            if case let .avplayer(p) = mode { p.pause() }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch mode {
            case .loading:
                LiquidGlassLoader(title: item.title)
            case .avplayer(let player):
                AVPlayerControllerRepresentable(player: player)
                    .ignoresSafeArea(edges: .bottom)
            case .webview:
                YouTubeIframeView(videoId: item.id)
                    .ignoresSafeArea(edges: .bottom)
            case .error(let msg):
                errorView(message: msg)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.yellow)
            Text("Can't play this video")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Open in YouTube") {
                UIApplication.shared.open(item.watchURL)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.top, 8)
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

    private func loadStream() async {
        // Phase 1: try YouTubeKit stream extraction.
        do {
            let yt = YouTube(videoID: item.id)
            let streams = try await yt.streams
            if let stream = pickBestStream(streams) {
                let p = AVPlayer(url: stream.url)
                p.automaticallyWaitsToMinimizeStalling = true
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)

                // Observe item status; if it goes to .failed, fall back to iframe.
                if let pi = p.currentItem {
                    statusObserver = pi.observe(\.status, options: [.new]) { obj, _ in
                        Task { @MainActor in
                            if obj.status == .failed {
                                mode = .webview
                            }
                        }
                    }
                }
                await MainActor.run { mode = .avplayer(p) }
                p.play()
                return
            }
        } catch {
            // Fall through to iframe fallback.
        }
        // Phase 2: fall back to WKWebView iframe.
        await MainActor.run { mode = .webview }
    }

    private func pickBestStream(_ streams: [YouTubeKit.Stream]) -> YouTubeKit.Stream? {
        let nativelyPlayable = streams.filter { $0.isNativelyPlayable }
        if let best = nativelyPlayable.highestResolutionStream() { return best }
        if let best = streams.filterVideoAndAudio().highestResolutionStream() { return best }
        return streams.first
    }
}

struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

/// WKWebView wrapping YouTube's iframe embed — used as a fallback when stream
/// extraction fails (some videos require signature ciphers YouTubeKit can't yet handle).
struct YouTubeIframeView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html>
        <html><head>
          <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
          <style>html,body{margin:0;padding:0;background:#000;height:100%;width:100%;overflow:hidden}
          .frame-wrap{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
          iframe{border:0;width:100%;height:100%;background:#000}</style>
        </head><body>
          <div class="frame-wrap">
            <iframe src="https://www.youtube.com/embed/\(videoId)?autoplay=1&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3" allowfullscreen allow="autoplay; encrypted-media; picture-in-picture"></iframe>
          </div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
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
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: rotate)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)

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
            rotate = true
            pulse = true
        }
    }
}
