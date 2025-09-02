import SwiftUI

/// Read-only drug search powered by OpenFDAService.
/// Shows Recent searches first. Searching lists only the drug name; details open on tap.
struct SearchView: View {
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var resultNames: [String] = []
    @State private var errorText: String? = nil

    @State private var searchTask: Task<Void, Never>? = nil

    // Recent queries (persisted locally)
    @AppStorage("search_recent_queries") private var recentJSON: String = "[]"

    private var recentQueries: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(recentJSON.utf8))) ?? [] }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue.prefix(10))) {
                recentJSON = String(data: data, encoding: .utf8) ?? "[]"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Recent searches (always visible on open)
                if !recentQueries.isEmpty {
                    Section("Recent searches") {
                        ForEach(recentQueries, id: \.self) { q in
                            Button {
                                query = q
                                triggerSearch()
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(q)
                                    Spacer()
                                }
                            }
                        }
                        .onDelete { idx in
                            var cur = recentQueries
                            cur.remove(atOffsets: idx)
                            updateRecents(cur)
                        }
                        Button(role: .destructive) {
                            updateRecents([])
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    }
                }

                // MARK: Results
                if isSearching {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Searching…")
                        }
                    }
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !resultNames.isEmpty {
                        Section("Results") {
                            ForEach(resultNames, id: \.self) { name in
                                NavigationLink {
                                    // Open details ONLY when tapped
                                    MedDetailView(medName: name)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "pills.fill")
                                            .foregroundStyle(.secondary)
                                        Text(name)
                                        Spacer()
                                    }
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    // Update recents on selection (MRU, unique)
                                    var cur = recentQueries.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
                                    cur.insert(name, at: 0)
                                    updateRecents(cur)
                                })
                            }
                        }
                    } else if let err = errorText {
                        Section("Results") {
                            ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text(err))
                        }
                    } else {
                        // Query present but no results yet (e.g., very short query)
                        EmptyView()
                    }
                } else if recentQueries.isEmpty {
                    // Fully empty state (no query, no recents)
                    Section {
                        ContentUnavailableView(
                            "Search medicines",
                            systemImage: "magnifyingglass",
                            description: Text("Type a medicine name to read FDA-based information. This won’t add anything to your meds.")
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer, prompt: "Search medicines")
            .onSubmit(of: .search) { triggerSearch() }
            .onChange(of: query) { newValue in
                // Debounce typing
                searchTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3 else {
                    // Reset results while typing short strings
                    resultNames = []
                    errorText = nil
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    await runSearch(for: trimmed)
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateRecents(_ new: [String]) {
        if let data = try? JSONEncoder().encode(Array(new.prefix(10))) {
            recentJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    private func triggerSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        Task { await runSearch(for: trimmed) }
    }

    @MainActor
    private func runSearch(for name: String) async {
        isSearching = true
        errorText = nil
        resultNames = []
        defer { isSearching = false }

        do {
            // We keep this simple and reliable: ask for details to validate the name,
            // then show only the resolved title as a clickable row.
            if let details = try await OpenFDAService.fetchDetails(forName: name) {
                self.resultNames = [details.title]
                // Do NOT push details here; only on user tap via NavigationLink above.
            } else {
                errorText = "Couldn’t find an FDA label for “\(name)”. Try a brand or generic name."
            }
        } catch {
            errorText = "Network error. Please try again."
        }
    }
}
