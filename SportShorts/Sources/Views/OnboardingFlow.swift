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
                SportsStep(onContinue: { selected in
                    session.followedCompetitionIds = selected
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
                .glassEffect(isSelected ? .regular.tint(Color.accentColor.opacity(0.3)).interactive() : .regular)
        }
    }
}

// MARK: - Sports picker

private struct SportsStep: View {
    @Environment(AppSession.self) private var session
    let onContinue: (Set<String>) -> Void
    @State private var picked = Set<String>()
    @State private var loading = true
    @State private var expanded = Set<String>()    // sport ids currently expanded

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)
            Text("Pick your sports.")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
            Text("Same list everywhere. We'll match each sport to the right broadcaster for \(session.country?.name ?? "your country").")
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
                            SportRow(
                                sport: sport,
                                expanded: expanded.contains(sport.id),
                                picked: picked,
                                toggleExpanded: {
                                    if expanded.contains(sport.id) { expanded.remove(sport.id) }
                                    else { expanded.insert(sport.id) }
                                },
                                toggleCompetition: { compId in
                                    if picked.contains(compId) { picked.remove(compId) }
                                    else { picked.insert(compId) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }

            Button { onContinue(picked) } label: {
                Text("Show me my highlights")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.glass)
            .tint(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .disabled(picked.isEmpty)
            .opacity(picked.isEmpty ? 0.4 : 1)
        }
        .task {
            if session.catalog.sports.isEmpty {
                session.catalog = await ChannelCatalog.load()
            }
            loading = false
        }
    }
}

private struct SportRow: View {
    let sport: Sport
    let expanded: Bool
    let picked: Set<String>
    let toggleExpanded: () -> Void
    let toggleCompetition: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: 14) {
                    Image(systemName: sport.icon).font(.title3).foregroundStyle(.tint).frame(width: 28)
                    Text(sport.label).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    let pickedCount = sport.competitions.filter { picked.contains($0.id) }.count
                    if pickedCount > 0 {
                        Text("\(pickedCount)").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                            .foregroundStyle(.tint)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    ForEach(sport.competitions) { comp in
                        Button { toggleCompetition(comp.id) } label: {
                            HStack {
                                Text(comp.label).font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: picked.contains(comp.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked.contains(comp.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            }
                            .padding(.horizontal, 18).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .glassEffect(.regular)
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}
