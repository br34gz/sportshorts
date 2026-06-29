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
            ZStack {
                Color.black.ignoresSafeArea()

                if let player {
                    AVPlayerControllerRepresentable(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else if loading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Loading…")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.subheadline)
                    }
                } else if let loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.yellow)
                        Text("Can't play this video")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(loadError)
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
            }
            .navigationTitle(item.competition)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
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
        .task { await loadStream() }
        .onDisappear { player?.pause() }
    }

    private func loadStream() async {
        do {
            let yt = YouTube(videoID: item.id)
            let streams = try await yt.streams
            // Prefer progressive (audio+video in one stream) for AVPlayer compatibility.
            // Otherwise the highest-quality adaptive video; AVPlayer handles HLS / DASH too in most cases.
            let pick = streams
                .filterVideoAndAudio()
                .sorted { ($0.videoResolution?.height ?? 0) > ($1.videoResolution?.height ?? 0) }
                .first
                ?? streams.highestResolutionStream()
                ?? streams.first
            guard let stream = pick else {
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
