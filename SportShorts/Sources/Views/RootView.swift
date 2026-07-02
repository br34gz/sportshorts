import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.hasCompletedOnboarding {
                MainTabView()
                    .task { await loadCatalogAndFeed() }
            } else {
                OnboardingFlow()
                    .task { await loadCatalogOnly() }
            }
        }
        .animation(.smooth, value: session.hasCompletedOnboarding)
    }

    private func loadCatalogOnly() async {
        async let ch = ChannelCatalog.load()
        async let sub = SubredditCatalogService.load()
        session.catalog = await ch
        session.subredditCatalog = await sub
    }

    private func loadCatalogAndFeed() async {
        async let ch = ChannelCatalog.load()
        async let sub = SubredditCatalogService.load()
        session.catalog = await ch
        session.subredditCatalog = await sub
        await refreshFeed()
    }

    private func refreshFeed() async {
        session.isLoadingFeed = true
        defer { session.isLoadingFeed = false }
        do {
            session.feed = try await FeedFetcher.fetch(
                channels: session.activeChannels,
                subreddits: session.activeSubreddits,
                redditEnabled: session.redditEnabled && session.subredditCatalog.enabled,
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
