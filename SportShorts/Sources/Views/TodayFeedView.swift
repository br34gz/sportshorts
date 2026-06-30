import SwiftUI

struct TodayFeedView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?
    /// Sport IDs the user has toggled on for the current view. nil = all followed.
    @State private var filterSports: Set<String> = []
    @State private var pageSize: Int = 20

    var body: some View {
        NavigationStack {
            // List as the outer container — pull-to-refresh on List is rock-solid
            // (and works from an empty state, unlike a ScrollView whose pull
            // gesture can be ambiguous when content is short).
            List {
                if !followedSports.isEmpty {
                    Section {
                        SportFilterChips(
                            sports: followedSports,
                            selected: $filterSports
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                if session.isLoadingFeed && session.feed.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView().controlSize(.large); Spacer() }
                            .padding(.vertical, 60)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else if visibleFeed.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nothing yet",
                            systemImage: "film.stack",
                            description: Text(session.lastFeedError ?? "Pull down to refresh.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(visibleFeed.prefix(pageSize)) { item in
                            VideoCard(item: item) { playing = item }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                .onAppear {
                                    // Infinite scroll — bump the visible count
                                    // when the last-visible item appears.
                                    if let last = visibleFeed.prefix(pageSize).last,
                                       item.id == last.id,
                                       pageSize < visibleFeed.count {
                                        pageSize = min(pageSize + 20, visibleFeed.count)
                                    }
                                }
                        }
                        if pageSize < visibleFeed.count {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .padding(.vertical, 12)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                pageSize = 20
                await refresh()
            }
            .navigationTitle("Highlights")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { pageSize = 20; await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(session.isLoadingFeed)
                }
            }
            .sheet(item: $playing) { item in
                PlayerSheet(item: item)
            }
            .onChange(of: filterSports) { _, _ in pageSize = 20 }
        }
    }

    private var followedSports: [Sport] {
        session.catalog.sports.filter { session.followedSportIds.contains($0.id) }
    }

    /// The feed, after applying the user's per-view sport chip selection.
    /// Empty selection = show all followed sports.
    private var visibleFeed: [VideoItem] {
        if filterSports.isEmpty { return session.feed }
        return session.feed.filter { filterSports.contains($0.sportId) }
    }

    private func refresh() async {
        session.isLoadingFeed = true
        defer { session.isLoadingFeed = false }
        do {
            session.feed = try await FeedFetcher.fetch(
                channels: session.activeChannels,
                followedSports: session.followedSportIds,
                catalog: session.catalog
            )
            session.lastFeedError = nil
        } catch {
            session.lastFeedError = error.localizedDescription
        }
    }
}

// MARK: - Sport filter chips

private struct SportFilterChips: View {
    let sports: [Sport]
    @Binding var selected: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", icon: nil, isOn: selected.isEmpty) {
                    selected.removeAll()
                }
                ForEach(sports) { sport in
                    FilterChip(label: sport.label, icon: sport.icon, isOn: selected.contains(sport.id)) {
                        if selected.contains(sport.id) {
                            selected.remove(sport.id)
                        } else {
                            selected.insert(sport.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct FilterChip: View {
    let label: String
    let icon: String?
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.caption.weight(.semibold)) }
                Text(label).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(isOn ? Color.accentColor : Color.white.opacity(0.08), lineWidth: 0.7)
                    }
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }
}
