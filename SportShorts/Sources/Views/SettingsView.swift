import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session

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

                Section("Sports") {
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
                }

                Section {
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
                    Text("View, hide, or add YouTube channels the app pulls highlights from.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                    Link("GitHub", destination: URL(string: "https://github.com/sb86-dev/sportshorts")!)
                    Button("Refresh channel catalog") {
                        Task { session.catalog = await ChannelCatalog.load(forceRefresh: true) }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
