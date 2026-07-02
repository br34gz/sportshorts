import SwiftUI

struct TodayFeedView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?
    @State private var filterSports: Set<String> = []
    @State private var pageSize: Int = 20
    @State private var lastRefresh: Date = .distantPast
    /// Signature of the session config that drives what gets fetched. When it
    /// changes (country flip, sport toggle, channel hide/unhide, spoiler
    /// toggle) onAppear forces a refresh regardless of the 30s throttle.
    @State private var lastConfigHash: Int = 0

    var body: some View {
        NavigationStack {
            List {
                if !followedSports.isEmpty {
                    Section {
                        SportFilterChips(sports: followedSports, selected: $filterSports)
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
                                .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                .onAppear {
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
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SpoilerToggle(isOn: Binding(
                        get: { session.allowSpoilers },
                        set: { newVal in
                            session.allowSpoilers = newVal
                            Task { pageSize = 20; await refresh(force: true) }
                        }
                    ))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { pageSize = 20; await refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(session.isLoadingFeed)
                }
            }
            .sheet(item: $playing, onDismiss: {
                Task { await refresh() }
            }) { item in
                PlayerSheet(item: item)
            }
            .onAppear {
                let current = computeConfigHash()
                let configChanged = (lastConfigHash != 0) && (current != lastConfigHash)
                lastConfigHash = current
                Task { await refresh(force: configChanged) }
            }
            .onChange(of: filterSports) { _, _ in pageSize = 20 }
        }
    }

    private var followedSports: [Sport] {
        session.catalog.sports.filter { session.followedSportIds.contains($0.id) }
    }

    private var visibleFeed: [VideoItem] {
        let base = session.followedFeed
        if filterSports.isEmpty { return base }
        return base.filter { filterSports.contains($0.sportId) }
    }

    private func computeConfigHash() -> Int {
        var hasher = Hasher()
        hasher.combine(session.country?.code)
        hasher.combine(session.followedSportIds.sorted())
        hasher.combine(session.followedCompetitionIds.sorted())
        hasher.combine(session.allowSpoilers)
        hasher.combine(session.englishOnly)
        hasher.combine(session.customBlocklist.sorted())
        hasher.combine(session.activeChannels.map(\.channelId).sorted())
        return hasher.finalize()
    }

    /// Refresh, throttled to once every 30s unless `force` is set.
    private func refresh(force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastRefresh) < 30 { return }
        lastRefresh = Date()
        session.isLoadingFeed = true
        defer { session.isLoadingFeed = false }
        do {
            session.feed = try await FeedFetcher.fetch(
                channels: session.activeChannels,
                catalog: session.catalog,
                allowSpoilers: session.allowSpoilers,
                customBlocklist: session.customBlocklist,
                englishOnly: session.englishOnly
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
                        if selected.contains(sport.id) { selected.remove(sport.id) }
                        else { selected.insert(sport.id) }
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

// MARK: - Spoiler toggle (toolbar)

private struct SpoilerToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "eye.fill" : "eye.slash.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
        }
        .accessibilityLabel(isOn ? "Hide spoilers" : "Show spoilers")
    }
}
