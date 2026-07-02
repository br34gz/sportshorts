import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var newBlocklistEntry = ""
    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { session.allowSpoilers },
                    set: { session.allowSpoilers = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show spoilers").font(.body)
                        Text("When off (default), titles that give away the result — explicit scores, goal/win/loss verbs, brackets in Reddit format — are dropped from the feed. When on, everything the filter would otherwise keep.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Spoilers")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { session.englishOnly },
                    set: { session.englishOnly = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("English highlights only").font(.body)
                        Text("Drops videos titled in other languages. Some broadcasters (FIFA, ICC, UEFA) publish the same highlight in a dozen languages — this keeps just the English one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Language")
            }

            Section {
                if session.customBlocklist.isEmpty {
                    Text("No terms in your blocklist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(session.customBlocklist, id: \.self) { term in
                        HStack {
                            Text(term)
                                .font(.body.monospaced())
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .onDelete(perform: removeTerms)
                }
                Button {
                    showAddSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add term")
                    }
                }
            } header: {
                Text("Custom title blocklist")
            } footer: {
                Text("Case-insensitive substring reject. Any highlight video whose title contains one of these terms gets dropped from the feed. Terms are matched anywhere in the title — no wildcards needed.")
            }

            Section {
                NavigationLink {
                    BlocklistTesterView()
                } label: {
                    Label("Test a title", systemImage: "text.magnifyingglass")
                }
            } footer: {
                Text("Paste any YouTube title to see whether the filter would let it through and, if not, which rule rejected it.")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddBlocklistTermSheet(term: $newBlocklistEntry) {
                let t = newBlocklistEntry.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, !session.customBlocklist.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                    session.customBlocklist.append(t)
                }
                newBlocklistEntry = ""
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Only touch these if you know what you're doing. Aggressive filters can empty your feed.")
                    .font(.caption)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.orange.opacity(0.15))
        }
    }

    private func removeTerms(at offsets: IndexSet) {
        session.customBlocklist.remove(atOffsets: offsets)
    }
}

// MARK: - Add sheet

private struct AddBlocklistTermSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var term: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 'best moments'", text: $term)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            onSave()
                            dismiss()
                        }
                } footer: {
                    Text("Enter one term. Case doesn't matter. You can add more terms afterwards.")
                }
            }
            .navigationTitle("Add term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                        dismiss()
                    }
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Tester

private struct BlocklistTesterView: View {
    @Environment(AppSession.self) private var session
    @State private var input = ""
    @State private var lastResult: TestResult?

    struct TestResult {
        let title: String
        let passed: Bool
        let reason: String
    }

    var body: some View {
        Form {
            Section {
                TextField("Paste a video title", text: $input, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    lastResult = runTest(input: input)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Test")
                    }
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Input")
            }

            if let r = lastResult {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(r.passed ? Color.green : Color.red)
                        Text(r.passed ? "Would show" : "Would be filtered out")
                            .font(.headline)
                    }
                    Text(r.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Result")
                }
            }
        }
        .navigationTitle("Test a title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runTest(input: String) -> TestResult {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let passed = HighlightsFilter.isMatchHighlight(
            title: title,
            allowSpoilers: session.allowSpoilers,
            customBlocklist: session.customBlocklist,
            englishOnly: session.englishOnly
        )
        let reason: String
        if passed {
            reason = "Passes every filter rule with your current settings."
        } else {
            reason = HighlightsFilter.rejectionReason(
                title: title,
                allowSpoilers: session.allowSpoilers,
                customBlocklist: session.customBlocklist,
                englishOnly: session.englishOnly
            ) ?? "Doesn't match any positive signal — no 'highlights' / 'recap' / score / team-vs-team pattern with a known competition."
        }
        return TestResult(title: title, passed: passed, reason: reason)
    }
}
