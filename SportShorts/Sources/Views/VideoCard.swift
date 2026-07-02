import SwiftUI

struct VideoCard: View {
    let item: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: item.thumbnailURL) { phase in
                        switch phase {
                        case .success(let img):
                            // Preserve native aspect ratio — YouTube serves both 16:9
                            // and 4:3 thumbnails and forcing one stretches the other.
                            img.resizable().scaledToFit()
                        default:
                            Rectangle().fill(Color.white.opacity(0.06)).aspectRatio(16/9, contentMode: .fit)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Sport icon + competition tag — top-left overlay on thumbnail.
                    HStack(spacing: 6) {
                        Image(systemName: item.sportIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(item.competitionLabel ?? item.sportLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule(style: .continuous))
                    .padding(10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    metadataLine
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
    }

    /// Metadata line under the title. YouTube items show channel · time.
    /// Reddit items follow the design doc: `r/name · ▲ score · time`.
    @ViewBuilder
    private var metadataLine: some View {
        switch item.origin {
        case .subreddit:
            HStack(spacing: 6) {
                Text(item.channelTitle)  // already `r/name`
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                if let score = item.redditScore {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(spacing: 2) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.caption2)
                        Text(compactScore(score))
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(item.publishedAt, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .youtubeChannel:
            HStack(spacing: 6) {
                Text(item.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                Text(item.publishedAt, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func compactScore(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
