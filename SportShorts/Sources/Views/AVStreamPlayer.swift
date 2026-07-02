import SwiftUI
import AVKit

/// Plays HLS (`.m3u8`) or mp4 URLs via AVPlayer with the standard iOS
/// player controls. Used for v.redd.it native videos, imgur mp4s, and any
/// other direct-URL stream where the YouTube iframe path doesn't apply.
struct AVStreamPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = false

        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        vc.player = player
        // Auto-play. User's first tap on the app already served as the media
        // playback user gesture, so unlike iframe-YouTube we don't need to
        // wait for a second in-frame tap.
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Replace the item if the URL actually changed (e.g. resuming into
        // this sheet with a different source). Avoids restarting mid-playback.
        if (vc.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            vc.player?.replaceCurrentItem(with: AVPlayerItem(url: url))
            vc.player?.play()
        }
    }
}
