import SwiftUI

struct SourcesSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { session.redditEnabled },
                    set: { session.redditEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Reddit as a source")
                        Text("Pulls video posts from subreddits alongside YouTube. Requires an OAuth client_id you register once with Reddit — takes about 60 seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    RedditCredentialsView()
                } label: {
                    HStack {
                        Text("Reddit credentials")
                        Spacer()
                        if session.redditCredentials.isConfigured {
                            Label("Set", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                    }
                }
                if session.redditEnabled && !session.redditCredentials.isConfigured {
                    Label("Add credentials to start pulling posts.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !session.subredditCatalog.enabled {
                    Label("Reddit source disabled remotely — will resume when the catalog re-enables it.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Reddit")
            } footer: {
                Text("YouTube channels are always on. Reddit is optional and requires a one-time OAuth setup.")
            }

            if session.redditEnabled {
                Section {
                    ForEach(catalogSubs, id: \.id) { sub in
                        Toggle(isOn: Binding(
                            get: { session.followedSubredditIds.contains(sub.id) },
                            set: { on in
                                if on { session.followedSubredditIds.insert(sub.id) }
                                else { session.followedSubredditIds.remove(sub.id) }
                            }
                        )) {
                            SubredditRow(sub: sub)
                        }
                    }
                } header: {
                    Text("Curated subreddits")
                } footer: {
                    Text("Toggle on to include a sub's video posts in your feed.")
                }

                Section {
                    if session.userAddedSubreddits.isEmpty {
                        Text("No subs added yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.userAddedSubreddits, id: \.id) { sub in
                            Toggle(isOn: Binding(
                                get: { session.followedSubredditIds.contains(sub.id) },
                                set: { on in
                                    if on { session.followedSubredditIds.insert(sub.id) }
                                    else { session.followedSubredditIds.remove(sub.id) }
                                }
                            )) {
                                SubredditRow(sub: sub)
                            }
                        }
                        .onDelete(perform: removeUserSubs)
                    }
                    Button {
                        showAddSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add subreddit")
                        }
                    }
                } header: {
                    Text("Your subreddits")
                } footer: {
                    Text("Add any subreddit that posts video highlights. Paste the name (with or without r/).")
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddSubredditSheet()
        }
    }

    private var catalogSubs: [SubredditSource] {
        session.subredditCatalog.subreddits
    }

    private func removeUserSubs(at offsets: IndexSet) {
        session.userAddedSubreddits.remove(atOffsets: offsets)
    }
}

// MARK: - Credentials page

private struct RedditCredentialsView: View {
    @Environment(AppSession.self) private var session
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var testing = false
    @State private var testStatus: String?
    @State private var testOK: Bool = false

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                TextField("Client Secret (optional for installed apps)", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Reddit App")
            } footer: {
                Text("Values from the app you registered at reddit.com/prefs/apps. If you selected 'installed app', leave the secret blank.")
            }

            Section {
                Button {
                    testCredentials()
                } label: {
                    HStack {
                        if testing { ProgressView().padding(.trailing, 6) }
                        Text(testing ? "Testing…" : "Save & test")
                    }
                }
                .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                if let testStatus {
                    HStack {
                        Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testOK ? Color.green : Color.red)
                        Text(testStatus).font(.footnote)
                    }
                }
            }

            Section {
                Link(destination: URL(string: "https://www.reddit.com/prefs/apps")!) {
                    Label("Open reddit.com/prefs/apps", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("How to get a client ID")
            } footer: {
                Text("1. Sign in to Reddit → prefs/apps.\n2. Click 'are you a developer? create an app'.\n3. Select 'installed app'.\n4. Name: SportShorts. Redirect URI: http://localhost.\n5. Create → copy the short string under your app's name (that's the client_id).")
            }

            if session.redditCredentials.isConfigured {
                Section {
                    Button(role: .destructive) {
                        session.redditCredentials = RedditCredentials(clientId: "", clientSecret: nil)
                        clientId = ""
                        clientSecret = ""
                        testStatus = nil
                    } label: {
                        Text("Clear credentials")
                    }
                }
            }
        }
        .navigationTitle("Reddit credentials")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            clientId = session.redditCredentials.clientId
            clientSecret = session.redditCredentials.clientSecret ?? ""
        }
    }

    private func testCredentials() {
        testing = true
        testStatus = nil
        let creds = RedditCredentials(
            clientId: clientId.trimmingCharacters(in: .whitespaces),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespaces).isEmpty ? nil : clientSecret.trimmingCharacters(in: .whitespaces)
        )
        Task {
            do {
                try await RedditGateway.testCredentials(creds)
                testOK = true
                testStatus = "Working — saved."
                session.redditCredentials = creds
            } catch {
                testOK = false
                testStatus = error.localizedDescription
            }
            testing = false
        }
    }
}

private struct SubredditRow: View {
    let sub: SubredditSource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sub.displayName).font(.body.weight(.medium))
            HStack(spacing: 6) {
                if let m = sub.minScore {
                    Text("min ▲ \(m)")
                }
                if !sub.sportHints.isEmpty {
                    Text("· \(sub.sportHints.joined(separator: ", "))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add subreddit sheet

private struct AddSubredditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var input = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. r/NRLmemes or NRLmemes", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(add)
                } footer: {
                    Text("The sub must be public. If it doesn't post videos, adding it won't hurt — nothing will show up in the feed.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add subreddit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(cleanedInput.isEmpty)
                }
            }
        }
    }

    private var cleanedInput: String {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("r/") || s.hasPrefix("R/") { s = String(s.dropFirst(2)) }
        if s.hasPrefix("/r/") { s = String(s.dropFirst(3)) }
        return s
    }

    private func add() {
        let name = cleanedInput
        guard !name.isEmpty else { return }
        let id = name.lowercased()

        // Prevent duplicates against catalog and existing user-added.
        if session.subredditCatalog.subreddits.contains(where: { $0.id == id }) ||
           session.userAddedSubreddits.contains(where: { $0.id == id }) {
            errorMessage = "You already follow r/\(name)."
            return
        }
        let sub = SubredditSource(name: name, userAdded: true)
        session.userAddedSubreddits.append(sub)
        session.followedSubredditIds.insert(id)
        dismiss()
    }
}
