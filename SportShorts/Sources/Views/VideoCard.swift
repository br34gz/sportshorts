import SwiftUI

struct VideoCard: View {
    let item: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
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

                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill").font(.title3)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(item.competition)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        Text("·").foregroundStyle(.tertiary)
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
