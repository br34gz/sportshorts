import SwiftUI

struct TodayFeedView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?

    var body: some View {
        NavigationStack {
            ZStack {
                if session.isLoadingFeed && session.feed.isEmpty {
                    ProgressView().controlSize(.large)
                } else if session.feed.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "sparkles",
                        description: Text(session.lastFeedError ?? "Pull to refresh once you've got a network.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(session.feed) { item in
                                VideoCard(item: item) {
                                    playing = item
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("Today")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(session.isLoadingFeed)
                }
            }
            .sheet(item: $playing) { item in
                PlayerSheet(item: item)
            }
        }
    }

    private func refresh() async {
        session.isLoadingFeed = true
        defer { session.isLoadingFeed = false }
        do {
            session.feed = try await FeedFetcher.fetch(channels: session.activeChannels)
            session.lastFeedError = nil
        } catch {
            session.lastFeedError = error.localizedDescription
        }
    }
}
