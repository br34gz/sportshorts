import SwiftUI

struct BrowseView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(sortedSports) { sport in
                        NavigationLink {
                            SportFeedView(sport: sport, playing: $playing)
                        } label: {
                            SportTile(
                                sport: sport,
                                videos: videosForSport(sport)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Browse")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $playing) { PlayerSheet(item: $0) }
        }
    }

    /// Every sport in the catalog, sorted by the recency of its most-recent
    /// video in the current 7-day feed. Sports with zero clips fall to the
    /// bottom in catalog order so the user can still see + tap them.
    private var sortedSports: [Sport] {
        let mostRecentBySport = Dictionary(grouping: session.feed, by: { $0.sportId })
            .mapValues { $0.map(\.publishedAt).max() ?? .distantPast }
        return session.catalog.sports.sorted { a, b in
            let av = mostRecentBySport[a.id] ?? .distantPast
            let bv = mostRecentBySport[b.id] ?? .distantPast
            if av == bv {
                let ai = session.catalog.sports.firstIndex(where: { $0.id == a.id }) ?? 0
                let bi = session.catalog.sports.firstIndex(where: { $0.id == b.id }) ?? 0
                return ai < bi
            }
            return av > bv
        }
    }

    private func videosForSport(_ sport: Sport) -> [VideoItem] {
        session.feed.filter { $0.sportId == sport.id }
    }
}

// MARK: - Sport tile (Browse grid)

/// A sport tile shows a stacked-card preview: the most-recent video's
/// thumbnail dominates, with up to two slightly offset/scaled thumbnails
/// behind it to suggest "more like this". Sport icon + name overlay on top,
/// count badge in the corner. Empty sports show a flat placeholder.
private struct SportTile: View {
    let sport: Sport
    let videos: [VideoItem]

    private var count: Int { videos.count }
    private var primary: VideoItem? { videos.first }
    private var second: VideoItem? { videos.dropFirst().first }
    private var third: VideoItem? { videos.dropFirst(2).first }

    var body: some View {
        ZStack {
            if let third {
                ThumbBackdrop(item: third)
                    .offset(x: 6, y: 6)
                    .scaleEffect(0.92)
                    .opacity(0.45)
            }
            if let second {
                ThumbBackdrop(item: second)
                    .offset(x: 3, y: 3)
                    .scaleEffect(0.96)
                    .opacity(0.7)
            }
            if let primary {
                ThumbBackdrop(item: primary)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }

            // Foreground content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: sport.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(sport.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                Spacer()
                HStack {
                    Spacer()
                    Text("\(count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                }
            }
            .padding(8)
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}

private struct ThumbBackdrop: View {
    let item: VideoItem

    var body: some View {
        ZStack {
            AsyncImage(url: item.thumbnailURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(Color.white.opacity(0.08))
                }
            }
            // Darken so the foreground text reads clearly on busy thumbnails.
            Rectangle().fill(Color.black.opacity(0.28))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Per-sport feed (drill-in from Browse)

private struct SportFeedView: View {
    let sport: Sport
    @Environment(AppSession.self) private var session
    @Binding var playing: VideoItem?

    var body: some View {
        List {
            Section {
                SportFollowHeader(
                    sport: sport,
                    count: items.count,
                    isFollowing: session.followedSportIds.contains(sport.id),
                    toggle: {
                        if session.followedSportIds.contains(sport.id) {
                            session.followedSportIds.remove(sport.id)
                        } else {
                            session.followedSportIds.insert(sport.id)
                        }
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }
            if items.isEmpty {
                Section {
                    Text("No clips for \(sport.label) this week.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(items) { item in
                    VideoCard(item: item) { playing = item }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(sport.label)
        .toolbarTitleDisplayMode(.inline)
    }

    private var items: [VideoItem] {
        session.feed.filter { $0.sportId == sport.id }
    }
}

private struct SportFollowHeader: View {
    let sport: Sport
    let count: Int
    let isFollowing: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: sport.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(sport.label).font(.title3.weight(.bold))
                Text("\(count) clip\(count == 1 ? "" : "s") this week")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: toggle) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(isFollowing ? Color.white.opacity(0.15) : Color.accentColor))
                    .foregroundStyle(isFollowing ? AnyShapeStyle(.white) : AnyShapeStyle(.black))
                    .overlay(Capsule().stroke(Color.white.opacity(isFollowing ? 0.25 : 0), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
    }
}
