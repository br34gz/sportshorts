import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var showingResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Region") {
                    Picker("Country", selection: Binding<String>(
                        get: { session.country?.code ?? "AU" },
                        set: { code in
                            session.country = Country.supported.first(where: { $0.code == code })
                        }
                    )) {
                        ForEach(Country.supported) { c in
                            Text("\(c.flag)  \(c.name)").tag(c.code)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SportsSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.tint).frame(width: 22)
                            Text("Sports")
                            Spacer()
                            Text("\(session.followedSportIds.count) of \(session.catalog.sports.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        ChannelsSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "tv").foregroundStyle(.tint).frame(width: 22)
                            Text("Channels")
                            Spacer()
                            Text("\(session.activeChannels.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Choose which sports to follow and which YouTube channels to pull from.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                    Link("GitHub", destination: URL(string: "https://github.com/sb86-dev/sportshorts")!)
                    Button("Refresh channel catalog") {
                        Task { session.catalog = await ChannelCatalog.load(forceRefresh: true) }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset App")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Removes all manually added channels and returns to the welcome screen.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset SportShorts?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { session.resetApp() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears your country, followed sports, hidden channels and any channels you added manually.")
            }
        }
    }
}

// MARK: - Sports settings sub-page

private struct SportsSettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                ForEach(session.catalog.sports) { sport in
                    Toggle(isOn: Binding(
                        get: { session.followedSportIds.contains(sport.id) },
                        set: { newVal in
                            if newVal { session.followedSportIds.insert(sport.id) }
                            else { session.followedSportIds.remove(sport.id) }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: sport.icon).foregroundStyle(.tint).frame(width: 22)
                            Text(sport.label)
                        }
                    }
                }
            } footer: {
                Text("Highlights from any broadcaster will be filtered to just the sports you follow.")
            }
        }
        .navigationTitle("Sports")
    }
}
