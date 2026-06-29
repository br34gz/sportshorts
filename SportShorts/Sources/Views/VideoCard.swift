import SwiftUI

struct VideoCard: View {
    let item: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: item.thumbnailURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(16/9, contentMode: .fill)
                        default:
                            Rectangle().fill(.tertiary).aspectRatio(16/9, contentMode: .fit)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()

                    // Sport icon — top-left, mirrors where the YouTube watermark sits top-right.
                    HStack(spacing: 6) {
                        Image(systemName: item.sportIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(item.competitionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .padding(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(item.channelTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.publishedAt, format: .relative(presentation: .numeric))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .glassEffect(.regular.interactive())
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
