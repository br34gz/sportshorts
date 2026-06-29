import SwiftUI

struct BrowseView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(followedSports) { sport in
                        let items = session.feed.filter { $0.sportId == sport.id }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: sport.icon).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                                Text(sport.label).font(.title3.weight(.bold))
                                Text("\(items.count) clips").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)

                            if items.isEmpty {
                                Text("No recent highlights for \(sport.label).")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(items.prefix(12)) { item in
                                            HorizontalVideoCard(item: item) { playing = item }
                                                .frame(width: 260)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8).padding(.bottom, 40)
            }
            .navigationTitle("Browse")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $playing) { PlayerSheet(item: $0) }
        }
    }

    private var followedSports: [Sport] {
        session.catalog.sports.filter { session.followedSportIds.contains($0.id) }
    }
}

private struct HorizontalVideoCard: View {
    let item: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: item.thumbnailURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(16/9, contentMode: .fill)
                    default: Rectangle().fill(.tertiary).aspectRatio(16/9, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                Text(item.publishedAt, format: .relative(presentation: .numeric))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
