import SwiftUI

struct BrowseView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?

    var body: some View {
        NavigationStack {
            List {
                Section("Sports") {
                    ForEach(sportsWithVideos) { sport in
                        NavigationLink {
                            SportFeedView(sport: sport, playing: $playing)
                        } label: {
                            SportRow(
                                sport: sport,
                                videoCount: videoCount(for: sport),
                                isFollowing: session.followedSportIds.contains(sport.id),
                                toggleFollow: {
                                    if session.followedSportIds.contains(sport.id) {
                                        session.followedSportIds.remove(sport.id)
                                    } else {
                                        session.followedSportIds.insert(sport.id)
                                    }
                                }
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Channels") {
                    ForEach(channelsWithVideos, id: \.channelId) { ch in
                        NavigationLink {
                            ChannelFeedView(channel: ch, playing: $playing)
                        } label: {
                            ChannelBrowseRow(channel: ch, videoCount: videoCount(for: ch))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Browse")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $playing) { PlayerSheet(item: $0) }
        }
    }

    // Show every sport that has at least one video in the current feed, in
    // catalog order (which now puts soccer first).
    private var sportsWithVideos: [Sport] {
        let counts = Dictionary(grouping: session.feed, by: { $0.sportId }).mapValues { $0.count }
        return session.catalog.sports.filter { (counts[$0.id] ?? 0) > 0 }
    }

    private func videoCount(for sport: Sport) -> Int {
        session.feed.lazy.filter { $0.sportId == sport.id }.count
    }

    private var channelsWithVideos: [YouTubeChannel] {
        let countsByChannel = Dictionary(grouping: session.feed, by: { $0.channelId }).mapValues { $0.count }
        return session.activeChannels
            .filter { (countsByChannel[$0.channelId] ?? 0) > 0 }
            .sorted { (countsByChannel[$0.channelId] ?? 0) > (countsByChannel[$1.channelId] ?? 0) }
    }

    private func videoCount(for channel: YouTubeChannel) -> Int {
        session.feed.lazy.filter { $0.channelId == channel.channelId }.count
    }
}

// MARK: - Sport row (Browse)

private struct SportRow: View {
    let sport: Sport
    let videoCount: Int
    let isFollowing: Bool
    let toggleFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sport.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(sport.label).font(.body.weight(.semibold))
                Text("\(videoCount) clip\(videoCount == 1 ? "" : "s") this week")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            FollowPill(isOn: isFollowing, action: toggleFollow)
        }
        .padding(.vertical, 2)
    }
}

private struct ChannelBrowseRow: View {
    let channel: YouTubeChannel
    let videoCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.body.weight(.semibold))
                if let handle = channel.displayHandle {
                    Text(handle).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(videoCount) clip\(videoCount == 1 ? "" : "s") this week")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(videoCount)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct FollowPill: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isOn ? "Following" : "Follow")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? Color.white.opacity(0.15) : Color.accentColor))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.black))
                .overlay(
                    Capsule().stroke(Color.white.opacity(isOn ? 0.25 : 0), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Per-sport feed (drill-in from Browse)

private struct SportFeedView: View {
    let sport: Sport
    @Environment(AppSession.self) private var session
    @Binding var playing: VideoItem?

    var body: some View {
        List {
            ForEach(items) { item in
                VideoCard(item: item) { playing = item }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
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

// MARK: - Per-channel feed (drill-in from Channels list)

private struct ChannelFeedView: View {
    let channel: YouTubeChannel
    @Environment(AppSession.self) private var session
    @Binding var playing: VideoItem?

    var body: some View {
        List {
            Section {
                ChannelFeedHeader(channel: channel,
                                  count: items.count,
                                  isFollowing: session.isFollowing(channelId: channel.channelId),
                                  toggleFollow: {
                                      let cur = session.isFollowing(channelId: channel.channelId)
                                      session.setFollowing(!cur, forChannelId: channel.channelId)
                                  })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }
            ForEach(items) { item in
                VideoCard(item: item) { playing = item }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(channel.name)
        .toolbarTitleDisplayMode(.inline)
    }

    private var items: [VideoItem] {
        session.feed.filter { $0.channelId == channel.channelId }
    }
}

private struct ChannelFeedHeader: View {
    let channel: YouTubeChannel
    let count: Int
    let isFollowing: Bool
    let toggleFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "tv.fill").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text("Channel feed").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                Text(channel.name).font(.title3.weight(.bold))
                if let handle = channel.displayHandle {
                    Text(handle).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(count) clip\(count == 1 ? "" : "s") this week")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            FollowPill(isOn: isFollowing, action: toggleFollow)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }
}
