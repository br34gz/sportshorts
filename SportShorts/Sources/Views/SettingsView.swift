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
    @State private var expanded: Set<String> = []

    var body: some View {
        Form {
            Section {
                ForEach(session.catalog.sports) { sport in
                    SportSettingsRow(
                        sport: sport,
                        expanded: expanded.contains(sport.id),
                        followedSports: session.followedSportIds,
                        followedComps: session.followedCompetitionIds,
                        toggleExpanded: {
                            if expanded.contains(sport.id) { expanded.remove(sport.id) }
                            else { expanded.insert(sport.id) }
                        },
                        toggleSport: {
                            if session.followedSportIds.contains(sport.id) {
                                session.followedSportIds.remove(sport.id)
                                // Drop any competition picks for this sport.
                                let compIds = Set(sport.competitions.map(\.id))
                                session.followedCompetitionIds.subtract(compIds)
                            } else {
                                session.followedSportIds.insert(sport.id)
                            }
                        },
                        toggleComp: { compId in
                            if session.followedCompetitionIds.contains(compId) {
                                session.followedCompetitionIds.remove(compId)
                            } else {
                                session.followedCompetitionIds.insert(compId)
                            }
                        }
                    )
                }
            } footer: {
                Text("Toggle a sport on to follow it. Expand a sport to narrow it to specific competitions; with no competitions picked, all of that sport's videos show.")
            }
        }
        .navigationTitle("Sports")
    }
}

private struct SportSettingsRow: View {
    let sport: Sport
    let expanded: Bool
    let followedSports: Set<String>
    let followedComps: Set<String>
    let toggleExpanded: () -> Void
    let toggleSport: () -> Void
    let toggleComp: (String) -> Void

    private var sportOn: Bool { followedSports.contains(sport.id) }
    private var hasMultipleComps: Bool { sport.competitions.count > 1 }
    private var pickedCompCount: Int { sport.competitions.filter { followedComps.contains($0.id) }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header row: sport toggle + chevron if expandable.
            HStack(spacing: 10) {
                Image(systemName: sport.icon).foregroundStyle(.tint).frame(width: 22)
                Text(sport.label)
                Spacer()
                if sportOn && hasMultipleComps {
                    if pickedCompCount > 0 {
                        Text("\(pickedCompCount) of \(sport.competitions.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("All")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: toggleExpanded) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Toggle("", isOn: Binding(get: { sportOn }, set: { _ in toggleSport() }))
                    .labelsHidden()
            }

            if sportOn && hasMultipleComps && expanded {
                let groups = groupedCompetitions(sport.competitions)
                let anyGrouped = groups.contains(where: { $0.group != nil })
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, section in
                        if anyGrouped, let group = section.group {
                            Text(group.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 32)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(section.comps) { comp in
                            Divider().padding(.leading, 32)
                            Toggle(isOn: Binding(
                                get: { followedComps.contains(comp.id) },
                                set: { _ in toggleComp(comp.id) }
                            )) {
                                Text(comp.label)
                                    .font(.subheadline)
                                    .padding(.leading, 32)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func groupedCompetitions(_ comps: [CompetitionMeta]) -> [(group: String?, comps: [CompetitionMeta])] {
        var out: [(String?, [CompetitionMeta])] = []
        for c in comps {
            if let last = out.last, last.0 == c.group {
                out[out.count - 1].1.append(c)
            } else {
                out.append((c.group, [c]))
            }
        }
        return out
    }
}
