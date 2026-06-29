import SwiftUI

struct MainTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            Tab("Highlights", systemImage: "film.stack") {
                TodayFeedView()
            }
            Tab("Browse", systemImage: "square.grid.2x2") {
                BrowseView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
