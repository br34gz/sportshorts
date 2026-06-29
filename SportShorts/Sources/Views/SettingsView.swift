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

                Section {
                    let entries = (session.catalog[session.country?.code ?? ""] ?? [])
                        .reduce(into: [(sport: String, competition: String)]()) { acc, e in
                            if !acc.contains(where: { $0.competition == e.competition }) {
                                acc.append((e.sport, e.competition))
                            }
                        }
                    ForEach(entries, id: \.competition) { e in
                        Toggle(isOn: Binding(
                            get: { session.followedCompetitions.contains(e.competition) },
                            set: { isOn in
                                if isOn { session.followedCompetitions.insert(e.competition) }
                                else { session.followedCompetitions.remove(e.competition) }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(e.competition).font(.body)
                                Text(e.sport).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Sports & competitions")
                } footer: {
                    Text("Channels are curated per country. Pull to refresh on Today to fetch latest highlights.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                    Link("GitHub", destination: URL(string: "https://github.com/sb86-dev/sportshorts")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
