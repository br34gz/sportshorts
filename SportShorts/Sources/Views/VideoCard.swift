import SwiftUI

struct VideoCard: View {
    let item: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: item.thumbnailURL) { phase in
                        switch phase {
                        case .success(let img):
                            // Preserve native aspect ratio — YouTube serves both 16:9
                            // and 4:3, forcing one stretches the other.
                            img.resizable().scaledToFit()
                        default:
                            Rectangle().fill(Color.white.opacity(0.06)).aspectRatio(16/9, contentMode: .fit)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

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
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}
