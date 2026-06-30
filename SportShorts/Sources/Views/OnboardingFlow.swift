import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppSession.self) private var session
    @State private var step: Step = .country

    enum Step { case country, sports }

    var body: some View {
        NavigationStack {
            switch step {
            case .country:
                CountryStep(onContinue: { country in
                    session.country = country
                    step = .sports
                })
            case .sports:
                SportsStep(onContinue: { pair in
                    session.followedSportIds = pair.sports
                    session.followedCompetitionIds = pair.comps
                })
            }
        }
    }
}

// MARK: - Country picker

private struct CountryStep: View {
    let onContinue: (Country) -> Void
    @State private var picked: Country?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 32)
            Text("Welcome to\nSportShorts.")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .lineLimit(2)
                .padding(.horizontal, 24)
            Text("Sports highlights, tuned to where you are.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            Text("WHERE DO YOU LIVE?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Country.supported) { country in
                        Button { picked = country } label: {
                            CountryRow(country: country, isSelected: picked == country)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Button { if let picked { onContinue(picked) } } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.glass)
            .tint(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .disabled(picked == nil)
            .opacity(picked == nil ? 0.4 : 1)
        }
    }
}

private struct CountryRow: View {
    let country: Country
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(country.flag).font(.system(size: 36))
            Text(country.name).font(.title3.weight(.medium))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
                }
        }
    }
}

// MARK: - Sports picker

private struct SportsStep: View {
    @Environment(AppSession.self) private var session
    let onContinue: ((sports: Set<String>, comps: Set<String>)) -> Void
    @State private var pickedSports = Set<String>()
    @State private var pickedComps = Set<String>()
    @State private var expanded = Set<String>()
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)
            Text("Pick your sports.")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
            Text("We'll pull highlights from every major broadcaster in \(session.country?.name ?? "your country"). Expand a sport to narrow it to specific competitions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(session.catalog.sports) { sport in
                            OnboardingSportRow(
                                sport: sport,
                                expanded: expanded.contains(sport.id),
                                pickedSports: pickedSports,
                                pickedComps: pickedComps,
                                toggleExpanded: {
                                    if expanded.contains(sport.id) { expanded.remove(sport.id) }
                                    else { expanded.insert(sport.id) }
                                },
                                toggleSport: {
                                    if pickedSports.contains(sport.id) {
                                        pickedSports.remove(sport.id)
                                        for c in sport.competitions { pickedComps.remove(c.id) }
                                    } else {
                                        pickedSports.insert(sport.id)
                                    }
                                },
                                toggleComp: { compId in
                                    if pickedComps.contains(compId) { pickedComps.remove(compId) }
                                    else { pickedComps.insert(compId) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }

            Button { onContinue((pickedSports, pickedComps)) } label: {
                Text("Show me my highlights")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.glass)
            .tint(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .disabled(pickedSports.isEmpty)
            .opacity(pickedSports.isEmpty ? 0.4 : 1)
        }
        .task {
            if session.catalog.sports.isEmpty {
                session.catalog = await ChannelCatalog.load()
            }
            loading = false
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

private struct OnboardingSportRow: View {
    let sport: Sport
    let expanded: Bool
    let pickedSports: Set<String>
    let pickedComps: Set<String>
    let toggleExpanded: () -> Void
    let toggleSport: () -> Void
    let toggleComp: (String) -> Void

    private var sportOn: Bool { pickedSports.contains(sport.id) }
    private var hasMultipleComps: Bool { sport.competitions.count > 1 }
    private var pickedCompCount: Int { sport.competitions.filter { pickedComps.contains($0.id) }.count }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleSport) {
                HStack(spacing: 14) {
                    Image(systemName: sport.icon).font(.title3).foregroundStyle(.tint).frame(width: 28)
                    Text(sport.label).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    if sportOn && hasMultipleComps {
                        Text(pickedCompCount == 0 ? "All" : "\(pickedCompCount)/\(sport.competitions.count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                            .foregroundStyle(.tint)
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
                    Image(systemName: sportOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(sportOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if sportOn && hasMultipleComps && expanded {
                let groups = groupedCompetitions(sport.competitions)
                let anyGrouped = groups.contains(where: { $0.group != nil })
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, section in
                        if anyGrouped, let group = section.group {
                            Text(group.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 46)
                                .padding(.top, 6)
                        }
                        ForEach(section.comps) { comp in
                            Button { toggleComp(comp.id) } label: {
                                HStack {
                                    Text(comp.label).font(.subheadline).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: pickedComps.contains(comp.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(pickedComps.contains(comp.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                }
                                .padding(.leading, 46).padding(.trailing, 18).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}
