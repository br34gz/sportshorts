import SwiftUI
import AVKit
import YouTubeKit

struct PlayerSheet: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var loading = true
    @State private var loadError: String?

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
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                AVPlayerControllerRepresentable(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else if loading {
                loadingView
            } else if let loadError {
                errorView(message: loadError)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(.white)
            Text("Loading…")
                .foregroundStyle(.white.opacity(0.8))
                .font(.subheadline)
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
        do {
            let yt = YouTube(videoID: item.id)
            let streams = try await yt.streams
            guard let stream = pickBestStream(streams) else {
                loadError = "No playable stream available."
                loading = false
                return
            }
            let p = AVPlayer(url: stream.url)
            p.automaticallyWaitsToMinimizeStalling = true
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = p
            loading = false
            p.play()
        } catch {
            loadError = error.localizedDescription
            loading = false
        }
    }

    private func pickBestStream(_ streams: [Stream]) -> Stream? {
        // Prefer streams that contain both video and audio in one file (progressive),
        // which AVPlayer can play directly without HLS muxing.
        let progressive = streams.filter { $0.includesVideoAndAudioTrack }
        if let best = progressive.max(by: { ($0.videoResolution?.height ?? 0) < ($1.videoResolution?.height ?? 0) }) {
            return best
        }
        // Otherwise: highest-resolution video-only stream — AVPlayer can usually play these.
        let videoOnly = streams.filter { $0.includesVideoTrack }
        if let best = videoOnly.max(by: { ($0.videoResolution?.height ?? 0) < ($1.videoResolution?.height ?? 0) }) {
            return best
        }
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
