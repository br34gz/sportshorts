import SwiftUI

struct BrowseView: View {
    @Environment(AppSession.self) private var session
    @State private var playing: VideoItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(groupedSports, id: \.competition) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(section.competition)
                                    .font(.title3.weight(.bold))
                                Text(section.sport)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)

                            let items = session.feed.filter { $0.competition == section.competition }
                            if items.isEmpty {
                                Text("No recent highlights for \(section.competition).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(items.prefix(8)) { item in
                                            HorizontalVideoCard(item: item) { playing = item }
                                                .frame(width: 260)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .navigationTitle("Browse")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $playing) { PlayerSheet(item: $0) }
        }
    }

    private var groupedSports: [(sport: String, competition: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for entry in session.activeChannels {
            if !seen.contains(entry.competition) {
                seen.insert(entry.competition)
                out.append((entry.sport, entry.competition))
            }
        }
        return out
    }
}

private struct HorizontalVideoCard: View {
    let item: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: item.thumbnailURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(16/9, contentMode: .fill)
                    default: Rectangle().fill(.tertiary).aspectRatio(16/9, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                Text(item.publishedAt, format: .relative(presentation: .numeric))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
