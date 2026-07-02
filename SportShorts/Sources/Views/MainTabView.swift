import SwiftUI

struct MainTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            TodayFeedView()
                .tabItem { Label("Highlights", systemImage: "film.stack") }
            BrowseView()
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
