import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var expandedSports: Set<String> = []

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
                        SportSettingsRow(
                            sport: sport,
                            expanded: expandedSports.contains(sport.id),
                            pickedIds: session.followedCompetitionIds,
                            toggleExpanded: {
                                if expandedSports.contains(sport.id) { expandedSports.remove(sport.id) }
                                else { expandedSports.insert(sport.id) }
                            },
                            toggleCompetition: { compId in
                                if session.followedCompetitionIds.contains(compId) {
                                    session.followedCompetitionIds.remove(compId)
                                } else {
                                    session.followedCompetitionIds.insert(compId)
                                }
                            }
                        )
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

private struct SportSettingsRow: View {
    let sport: Sport
    let expanded: Bool
    let pickedIds: Set<String>
    let toggleExpanded: () -> Void
    let toggleCompetition: (String) -> Void

    private var isSingleCompetition: Bool { sport.competitions.count == 1 }
    private var pickedCount: Int { sport.competitions.filter { pickedIds.contains($0.id) }.count }

    var body: some View {
        if isSingleCompetition {
            Toggle(isOn: Binding(
                get: { pickedIds.contains(sport.competitions[0].id) },
                set: { _ in toggleCompetition(sport.competitions[0].id) }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: sport.icon).foregroundStyle(.tint).frame(width: 22)
                    Text(sport.label)
                }
            }
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded },
                set: { _ in toggleExpanded() }
            )) {
                let groups = groupedCompetitions
                let anyGrouped = groups.contains(where: { $0.group != nil })
                ForEach(Array(groups.enumerated()), id: \.offset) { _, section in
                    if anyGrouped, let group = section.group {
                        Text(group)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(section.items) { comp in
                        Toggle(isOn: Binding(
                            get: { pickedIds.contains(comp.id) },
                            set: { _ in toggleCompetition(comp.id) }
                        )) {
                            Text(comp.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sport.icon).foregroundStyle(.tint).frame(width: 22)
                    Text(sport.label)
                    Spacer()
                    if pickedCount > 0 {
                        Text("\(pickedCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private var groupedCompetitions: [(group: String?, items: [Competition])] {
        var out: [(String?, [Competition])] = []
        for c in sport.competitions {
            if let last = out.last, last.0 == c.group {
                out[out.count - 1].1.append(c)
            } else {
                out.append((c.group, [c]))
            }
        }
        return out
    }
}
