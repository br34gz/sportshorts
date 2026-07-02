import SwiftUI

struct BrowseView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    section(title: "Following", sports: followingSports)
                    section(title: "Not following", sports: notFollowingSports)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $playing) { PlayerSheet(item: $0) }
        }
    }

    @ViewBuilder
    private func section(title: String, sports: [Sport]) -> some View {
        if !sports.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(sports) { sport in
                        NavigationLink {
                            SportFeedView(sport: sport, playing: $playing)
                        } label: {
                            SportTile(
                                sport: sport,
                                videoCount: videoCount(for: sport)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// All sports the user follows, sorted by their most-recent clip first.
    private var followingSports: [Sport] {
        sortedSports(within: session.catalog.sports.filter { session.followedSportIds.contains($0.id) })
    }

    /// Every other sport, also sorted by most-recent clip first.
    private var notFollowingSports: [Sport] {
        sortedSports(within: session.catalog.sports.filter { !session.followedSportIds.contains($0.id) })
    }

    private func sortedSports(within sports: [Sport]) -> [Sport] {
        let mostRecent = Dictionary(grouping: session.feed, by: { $0.sportId })
            .mapValues { $0.map(\.publishedAt).max() ?? .distantPast }
        return sports.sorted { a, b in
            let av = mostRecent[a.id] ?? .distantPast
            let bv = mostRecent[b.id] ?? .distantPast
            if av == bv {
                let ai = session.catalog.sports.firstIndex(where: { $0.id == a.id }) ?? 0
                let bi = session.catalog.sports.firstIndex(where: { $0.id == b.id }) ?? 0
                return ai < bi
            }
            return av > bv
        }
    }

    private func videoCount(for sport: Sport) -> Int {
        session.feed.lazy.filter { $0.sportId == sport.id }.count
    }
}

// MARK: - Sport tile

/// Plain square tile: a tinted background with the sport icon at the centre
/// and the sport name + count below. No thumbnail clutter — easier to scan
/// at a glance.
private struct SportTile: View {
    let sport: Sport
    let videoCount: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                Image(systemName: sport.icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if videoCount > 0 {
                    Text("\(videoCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(6)
                }
            }

            Text(sport.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
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
        .navigationBarTitleDisplayMode(.inline)
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
