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

                ForEach(session.catalog.sports) { sport in
                    Section {
                        ForEach(sport.competitions) { comp in
                            Toggle(isOn: Binding(
                                get: { session.followedCompetitionIds.contains(comp.id) },
                                set: { isOn in
                                    if isOn { session.followedCompetitionIds.insert(comp.id) }
                                    else { session.followedCompetitionIds.remove(comp.id) }
                                }
                            )) {
                                Text(comp.label)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: sport.icon)
                            Text(sport.label)
                        }
                    }
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
