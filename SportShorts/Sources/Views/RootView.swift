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
        session.catalog = await ChannelCatalog.load()
    }

    private func loadCatalogAndFeed() async {
        session.catalog = await ChannelCatalog.load()
        await refreshFeed()
    }

    private func refreshFeed() async {
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
