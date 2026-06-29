import SwiftUI

struct ChannelsSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                ForEach(builtInRows, id: \.channelId) { ch in
                    ChannelRow(channel: ch, hidden: session.hiddenChannelIds.contains(ch.channelId)) {
                        if session.hiddenChannelIds.contains(ch.channelId) {
                            session.hiddenChannelIds.remove(ch.channelId)
                        } else {
                            session.hiddenChannelIds.insert(ch.channelId)
                        }
                    }
                }
            } header: {
                Text("Built-in (\(session.country?.name ?? "your country") + global leagues)")
            } footer: {
                Text("Toggle a channel off to remove its highlights from your feed.")
            }

            if !session.userAddedChannels.isEmpty {
                Section("Added by you") {
                    ForEach(session.userAddedChannels, id: \.channelId) { ch in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ch.name).font(.body.weight(.medium))
                            if let note = ch.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: removeUserChannel)
                }
            }
        }
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddChannelSheet()
        }
    }

    private var builtInRows: [YouTubeChannel] {
        let country = country.flatMap { session.catalog.countries[$0.code] } ?? []
        let global = session.catalog.globalChannels
        var seen = Set<String>()
        return (country + global).filter { seen.insert($0.channelId).inserted }
    }

    private var country: Country? { session.country }

    private func removeUserChannel(at offsets: IndexSet) {
        session.userAddedChannels.remove(atOffsets: offsets)
    }
}

private struct ChannelRow: View {
    let channel: YouTubeChannel
    let hidden: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let note = channel.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    } else if !channel.sportHints.isEmpty {
                        Text(channel.sportHints.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: hidden ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(hidden ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add channel

private struct AddChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var input = ""
    @State private var resolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube URL or @handle", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit {
                            if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                                resolveAndAdd()
                            }
                        }
                } footer: {
                    Text("Paste any YouTube channel link — `youtube.com/channel/UC…`, `youtube.com/@handle`, or just `@handle`.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if resolving {
                        ProgressView()
                    } else {
                        Button("Add") { resolveAndAdd() }
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func resolveAndAdd() {
        resolving = true
        errorMessage = nil
        Task {
            let trimmed = input.trimmingCharacters(in: .whitespaces)
            do {
                let (channelId, name) = try await ChannelResolver.resolve(input: trimmed)
                if session.userAddedChannels.contains(where: { $0.channelId == channelId }) ||
                   session.catalog.globalChannels.contains(where: { $0.channelId == channelId }) ||
                   (session.country.flatMap { session.catalog.countries[$0.code] } ?? []).contains(where: { $0.channelId == channelId }) {
                    errorMessage = "That channel is already tracked."
                } else {
                    let ch = YouTubeChannel(channelId: channelId, name: name, note: nil, sportHints: [], userAdded: true)
                    session.userAddedChannels.append(ch)
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            resolving = false
        }
    }
}
