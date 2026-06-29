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
                    session.followedCompetitions = selected
                })
            }
        }
    }
}

private struct CountryStep: View {
    @Environment(AppSession.self) private var session
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
                        Button {
                            picked = country
                        } label: {
                            CountryRow(country: country, isSelected: picked == country)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Button {
                if let picked { onContinue(picked) }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
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

private struct SportsStep: View {
    @Environment(AppSession.self) private var session
    let onContinue: (Set<String>) -> Void
    @State private var picked = Set<String>()
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 32)
            Text("Pick your sports.")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
            Text("Tap as many as you like. You can change this any time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let competitions = (session.catalog[session.country?.code ?? ""] ?? [])
                    .reduce(into: [(sport: String, competition: String)]()) { acc, entry in
                        if !acc.contains(where: { $0.competition == entry.competition }) {
                            acc.append((entry.sport, entry.competition))
                        }
                    }
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(competitions, id: \.competition) { item in
                            CompetitionToggle(
                                sport: item.sport,
                                competition: item.competition,
                                isSelected: picked.contains(item.competition),
                                onToggle: {
                                    if picked.contains(item.competition) { picked.remove(item.competition) }
                                    else { picked.insert(item.competition) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Spacer()
            Button {
                onContinue(picked)
            } label: {
                Text("Show me my highlights")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.glass)
            .tint(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .disabled(picked.isEmpty)
            .opacity(picked.isEmpty ? 0.4 : 1)
        }
        .task {
            if session.catalog.isEmpty {
                session.catalog = await ChannelCatalog.load()
            }
            loading = false
        }
    }
}

private struct CompetitionToggle: View {
    let sport: String
    let competition: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(competition).font(.headline)
                    Text(sport).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .glassEffect(isSelected ? .regular.tint(Color.accentColor.opacity(0.25)).interactive() : .regular)
            }
        }
        .buttonStyle(.plain)
    }
}
